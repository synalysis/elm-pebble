defmodule Ide.PebbleToolchain do
  @moduledoc """
  Boundary for Pebble SDK and emulator command execution.
  """
  import Bitwise, only: [&&&: 2, |||: 2]

  alias Ide.CompanionProtocolGenerator
  alias Ide.PebblePreferences
  alias Ide.Resources.ResourceStore
  alias Ide.WatchModels
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @forbidden_build_warning_snippets [
    "warning: 'ELMC_PROCESS_SLOTS' defined but not used",
    "warning: 'ELMC_NEXT_PROCESS_ID' defined but not used"
  ]

  @type project_slug :: String.t()
  @type opts :: keyword()

  @type command_result :: %{
          status: :ok | :error,
          command: String.t(),
          output: String.t(),
          exit_code: integer(),
          cwd: String.t()
        }

  @callback build(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  @callback package(project_slug(), opts()) :: {:ok, map()} | {:error, term()}
  @callback publish(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  @callback run_emulator(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  @callback stop_emulator(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  @callback run_screenshot(project_slug(), String.t(), String.t()) ::
              {:ok, command_result()} | {:error, term()}

  @doc """
  Runs `pebble build` for a prepared Pebble app directory.
  """
  @spec build(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  def build(_project_slug, opts) do
    case Keyword.get(opts, :app_root) do
      app_root when is_binary(app_root) and app_root != "" ->
        run_pebble(["build"], cwd: app_root)

      _ ->
        run_pebble(["build"])
    end
  end

  @doc """
  Builds a project-specific PBW artifact and returns the package path.
  """
  @spec package(project_slug(), opts()) :: {:ok, map()} | {:error, term()}
  def package(project_slug, opts) do
    workspace_root = Keyword.get(opts, :workspace_root)
    target_type = Keyword.get(opts, :target_type, "app")
    project_name = Keyword.get(opts, :project_name, project_slug)

    with {:ok, workspace_root} <- normalize_workspace_root(workspace_root),
         {:ok, app_root} <-
           prepare_project_build_app(
             project_slug,
             workspace_root,
             target_type,
             project_name,
             opts
           ),
         {:ok, build_result} <- build(project_slug, Keyword.put(opts, :app_root, app_root)),
         :ok <- ensure_successful_build(build_result),
         :ok <- ensure_no_forbidden_build_warnings(build_result),
         {:ok, artifact_path} <- latest_pbw(app_root),
         {:ok, artifact_path} <- Ide.Emulator.PBW.prune_empty_media_resources(artifact_path),
         {:ok, artifact_path} <- Ide.Emulator.PBW.prune_development_artifacts(artifact_path) do
      {:ok,
       %{
         status: build_result.status,
         artifact_path: artifact_path,
         build_result: build_result,
         app_root: app_root,
         has_phone_companion: package_has_phone_companion?(app_root)
       }}
    end
  end

  @doc """
  Runs `pebble publish` for a prepared Pebble app directory.
  """
  @spec publish(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  def publish(_project_slug, opts) do
    with {:ok, app_root} <- normalize_publish_app_root(Keyword.get(opts, :app_root)) do
      release_notes = Keyword.get(opts, :release_notes, "")
      is_published = Keyword.get(opts, :is_published, false)
      all_platforms = Keyword.get(opts, :all_platforms, false)
      include_gifs = Keyword.get(opts, :gif_all_platforms, false)
      firebase_token = Keyword.get(opts, :firebase_id_token)

      args =
        ["publish", "--non-interactive"]
        |> maybe_append_release_notes(release_notes)
        |> maybe_append_flag(is_published, "--is-published")
        |> maybe_append_flag(all_platforms, "--all-platforms")
        |> maybe_append_flag(include_gifs, "--gif-all-platforms")
        |> maybe_append_flag(!include_gifs, "--no-gif-all-platforms")

      env =
        if is_binary(firebase_token) and String.trim(firebase_token) != "" do
          [{"PEBBLE_FIREBASE_ID_TOKEN", String.trim(firebase_token)}]
        else
          []
        end

      run_pebble(args, cwd: app_root, env: env)
    end
  end

  @spec ensure_successful_build(term()) :: term()
  defp ensure_successful_build(%{status: :ok}), do: :ok
  defp ensure_successful_build(result), do: {:error, {:pebble_build_failed, result}}

  @spec ensure_no_forbidden_build_warnings(term()) :: term()
  defp ensure_no_forbidden_build_warnings(%{output: output} = result) when is_binary(output) do
    present =
      Enum.filter(@forbidden_build_warning_snippets, fn snippet ->
        String.contains?(output, snippet)
      end)

    case present do
      [] -> :ok
      warnings -> {:error, {:forbidden_build_warnings, warnings, result}}
    end
  end

  @doc """
  Runs `pebble wipe` and then `pebble install --emulator` for a specific `.pbw` artifact.
  """
  @spec run_emulator(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  def run_emulator(_project_slug, opts) do
    emulator_target = Keyword.get(opts, :emulator_target, configured_emulator_target())
    package_path = Keyword.get(opts, :package_path)
    install_timeout_seconds = max(Keyword.get(opts, :install_timeout_seconds, 120), 30)

    with {:ok, package_path} <- normalize_package_path(package_path) do
      cwd = Path.dirname(package_path)

      with {:ok, install_result} <-
             install_on_emulator(cwd, emulator_target, package_path, install_timeout_seconds) do
        {:ok, attach_emulator_logs(install_result, emulator_target, cwd, opts)}
      end
    end
  end

  @doc """
  Stops running Pebble emulator processes via `pebble kill`.
  """
  @spec stop_emulator(project_slug(), opts()) :: {:ok, command_result()} | {:error, term()}
  def stop_emulator(_project_slug, opts \\ []) do
    args =
      if Keyword.get(opts, :force, false) do
        ["kill", "--force"]
      else
        ["kill"]
      end

    run_pebble_with_timeout(args, Keyword.get(opts, :timeout_seconds, 10), opts)
  end

  @spec install_on_emulator(String.t(), String.t(), String.t(), pos_integer()) ::
          {:ok, command_result()} | {:error, term()}
  defp install_on_emulator(cwd, emulator_target, package_path, timeout_seconds)
       when is_binary(cwd) and is_binary(emulator_target) and is_binary(package_path) and
              is_integer(timeout_seconds) and timeout_seconds > 0 do
    with {:ok, wipe_result} <- run_pebble_with_timeout(["wipe"], timeout_seconds, cwd: cwd),
         :ok <- ensure_successful_wipe(wipe_result) do
      run_pebble_with_timeout(
        emulator_install_args(emulator_target, package_path),
        timeout_seconds,
        cwd: cwd
      )
    end
  end

  @spec ensure_successful_wipe(term()) :: :ok | {:error, term()}
  defp ensure_successful_wipe(%{status: :ok}), do: :ok
  defp ensure_successful_wipe(result), do: {:error, {:pebble_wipe_failed, result}}

  @spec emulator_install_args(String.t(), String.t()) :: [String.t()]
  defp emulator_install_args(emulator_target, package_path) do
    ["install", "--emulator", emulator_target]
    |> maybe_append_emulator_install_throttle()
    |> Kernel.++([package_path])
  end

  @spec maybe_append_emulator_install_throttle([String.t()]) :: [String.t()]
  defp maybe_append_emulator_install_throttle(args) do
    case configured_emulator_install_throttle() do
      nil -> args
      throttle -> args ++ ["--throttle=#{throttle}"]
    end
  end

  @spec configured_emulator_install_throttle() :: String.t() | nil
  defp configured_emulator_install_throttle do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_install_throttle_seconds, 0.004)
    |> case do
      false ->
        nil

      nil ->
        nil

      throttle when is_binary(throttle) ->
        String.trim(throttle)

      throttle when is_number(throttle) and throttle > 0 ->
        :erlang.float_to_binary(throttle / 1, decimals: 3)

      _ ->
        nil
    end
    |> case do
      "" -> nil
      throttle -> throttle
    end
  end

  @spec attach_emulator_logs(term(), term(), term(), term()) :: term()
  defp attach_emulator_logs(result, emulator_target, cwd, opts) do
    logs_seconds = Keyword.get(opts, :logs_snapshot_seconds, 4)

    case capture_emulator_logs_snapshot(emulator_target, cwd, logs_seconds) do
      {:ok, logs_result} ->
        summary = """

        --- emulator logs snapshot (#{logs_seconds}s) ---
        command: #{logs_result.command}
        exit_code: #{logs_result.exit_code}

        #{String.trim(logs_result.output)}
        """

        %{result | output: String.trim(result.output) <> summary}

      {:error, reason} ->
        summary = """

        --- emulator logs snapshot ---
        unavailable: #{inspect(reason)}
        """

        %{result | output: String.trim(result.output) <> summary}
    end
  end

  @spec capture_emulator_logs_snapshot(term(), term(), term()) :: term()
  defp capture_emulator_logs_snapshot(emulator_target, cwd, seconds)
       when is_binary(emulator_target) and is_integer(seconds) and seconds > 0 do
    with {:ok, pebble_bin} <- pebble_bin() do
      timeout_bin = System.find_executable("timeout")

      cond do
        is_nil(timeout_bin) ->
          {:error, :timeout_utility_not_found}

        true ->
          args = [
            "#{seconds}s",
            pebble_bin,
            "logs",
            "--emulator",
            emulator_target,
            "--no-color"
          ]

          env = pebble_command_env(args)

          {output, exit_code} =
            System.cmd(timeout_bin, args, cd: cwd, stderr_to_stdout: true, env: env)

          {:ok,
           %{
             status: if(exit_code == 0, do: :ok, else: :error),
             command: Enum.join([timeout_bin | args], " "),
             output: output,
             exit_code: exit_code,
             cwd: cwd
           }}
      end
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Runs `pebble screenshot` to capture emulator output into a file.
  """
  @spec run_screenshot(project_slug(), String.t(), String.t()) ::
          {:ok, command_result()} | {:error, term()}
  def run_screenshot(_project_slug, output_path, emulator_target) do
    run_pebble_with_timeout(
      ["screenshot", "--emulator", emulator_target, "--no-open", output_path],
      15,
      []
    )
  end

  @doc """
  Returns supported emulator/watch targets for capture and install.
  """
  @spec supported_emulator_targets() :: [String.t()]
  def supported_emulator_targets do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_targets, WatchModels.ordered_ids())
  end

  @doc """
  Returns configured Pebble app template root directory.
  """
  @spec template_app_root_path() :: {:ok, String.t()} | {:error, term()}
  def template_app_root_path do
    template_app_root()
  end

  @spec run_pebble(term(), term()) :: term()
  defp run_pebble(args, opts \\ []) do
    with {:ok, pebble_bin} <- pebble_bin(),
         {:ok, cwd} <- command_cwd(opts) do
      env = pebble_command_env(args, opts)

      {output, exit_code} =
        System.cmd(pebble_bin, args, cd: cwd, stderr_to_stdout: true, env: env)

      {:ok,
       %{
         status: if(exit_code == 0, do: :ok, else: :error),
         command: Enum.join([pebble_bin | args], " "),
         output: output,
         exit_code: exit_code,
         cwd: cwd
       }}
    end
  rescue
    error -> {:error, error}
  end

  @spec run_pebble_with_timeout(term(), term(), term()) :: term()
  defp run_pebble_with_timeout(args, timeout_seconds, opts)
       when is_list(args) and is_integer(timeout_seconds) and timeout_seconds > 0 do
    with {:ok, pebble_bin} <- pebble_bin(),
         {:ok, cwd} <- command_cwd(opts) do
      env = pebble_command_env(args, opts)
      timeout_bin = System.find_executable("timeout")

      if is_binary(timeout_bin) and timeout_bin != "" do
        cmd_args = ["#{timeout_seconds}s", pebble_bin] ++ args

        {output, exit_code} =
          System.cmd(timeout_bin, cmd_args, cd: cwd, stderr_to_stdout: true, env: env)

        {:ok,
         %{
           status: if(exit_code == 0, do: :ok, else: :error),
           command: Enum.join([timeout_bin | cmd_args], " "),
           output: output,
           exit_code: exit_code,
           cwd: cwd
         }}
      else
        run_pebble(args, opts)
      end
    end
  rescue
    error -> {:error, error}
  end

  @spec pebble_command_env([String.t()], keyword()) :: [{String.t(), String.t()}]
  defp pebble_command_env(args, opts \\ []) do
    env = [{"LC_ALL", "C"}] ++ Keyword.get(opts, :env, [])

    if pebble_emulator_command?(args) do
      maybe_prepend_linux_bzip2_compat_path(env)
    else
      env
    end
  end

  @spec pebble_emulator_command?([String.t()]) :: boolean()
  defp pebble_emulator_command?(["wipe" | _]), do: true
  defp pebble_emulator_command?(args), do: Enum.member?(args, "--emulator")

  @spec maybe_prepend_linux_bzip2_compat_path([{String.t(), String.t()}]) :: [
          {String.t(), String.t()}
        ]
  defp maybe_prepend_linux_bzip2_compat_path(env) do
    case ensure_linux_bzip2_compat_dir() do
      {:ok, dir} -> prepend_env_path(env, "LD_LIBRARY_PATH", dir)
      _ -> env
    end
  end

  @spec ensure_linux_bzip2_compat_dir() :: {:ok, String.t()} | {:error, term()} | :ignore
  defp ensure_linux_bzip2_compat_dir do
    cond do
      :os.type() != {:unix, :linux} ->
        :ignore

      Enum.any?(legacy_bzip2_candidates(), &File.exists?/1) ->
        :ignore

      true ->
        with {:ok, source} <- first_existing_path(bzip2_soname_alias_candidates()),
             {:ok, dir} <- pebble_toolchain_compat_dir(),
             :ok <- File.mkdir_p(dir),
             :ok <- ensure_symlink(Path.join(dir, "libbz2.so.1.0"), source) do
          {:ok, dir}
        end
    end
  end

  @spec ensure_symlink(String.t(), String.t()) :: :ok | {:error, term()}
  defp ensure_symlink(link_path, target_path) do
    case File.ln_s(target_path, link_path) do
      :ok ->
        :ok

      {:error, :eexist} ->
        if File.exists?(link_path) do
          :ok
        else
          with :ok <- File.rm(link_path), do: File.ln_s(target_path, link_path)
        end

      error ->
        error
    end
  end

  @spec prepend_env_path([{String.t(), String.t()}], String.t(), String.t()) :: [
          {String.t(), String.t()}
        ]
  defp prepend_env_path(env, key, path) do
    {existing_entries, rest} = Enum.split_with(env, fn {env_key, _value} -> env_key == key end)

    existing =
      case List.last(existing_entries) do
        {_key, value} -> value
        nil -> System.get_env(key)
      end

    value =
      [path, existing]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(":")

    [{key, value} | rest]
  end

  @spec first_existing_path([String.t()]) :: {:ok, String.t()} | {:error, :not_found}
  defp first_existing_path(paths) do
    case Enum.find(paths, &File.exists?/1) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  @spec pebble_toolchain_compat_dir() :: {:ok, String.t()} | {:error, term()}
  defp pebble_toolchain_compat_dir do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:pebble_toolchain_compat_dir)

    cond do
      is_binary(configured) and configured != "" ->
        {:ok, configured}

      cache_home = System.get_env("XDG_CACHE_HOME") ->
        {:ok, Path.join([cache_home, "elm-pebble", "pebble-toolchain-compat"])}

      true ->
        {:ok, Path.join([System.user_home!(), ".cache", "elm-pebble", "pebble-toolchain-compat"])}
    end
  rescue
    error -> {:error, error}
  end

  @spec legacy_bzip2_candidates() :: [String.t()]
  defp legacy_bzip2_candidates do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:legacy_bzip2_candidates)

    if is_list(configured) do
      configured
    else
      [
        "/lib64/libbz2.so.1.0",
        "/usr/lib64/libbz2.so.1.0",
        "/lib/x86_64-linux-gnu/libbz2.so.1.0",
        "/usr/lib/x86_64-linux-gnu/libbz2.so.1.0"
      ]
    end
  end

  @spec bzip2_soname_alias_candidates() :: [String.t()]
  defp bzip2_soname_alias_candidates do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:bzip2_soname_alias_candidates)

    if is_list(configured) do
      configured
    else
      [
        "/lib64/libbz2.so.1",
        "/usr/lib64/libbz2.so.1",
        "/lib/x86_64-linux-gnu/libbz2.so.1",
        "/usr/lib/x86_64-linux-gnu/libbz2.so.1"
      ]
    end
  end

  @spec prepare_project_build_app(term(), term(), term(), term(), term()) :: term()
  defp prepare_project_build_app(project_slug, workspace_root, target_type, project_name, opts) do
    with {:ok, template_root} <- template_app_root(),
         {:ok, compile_project_root} <- compile_project_root(workspace_root),
         {:ok, app_root} <- ensure_build_app_root(workspace_root),
         :ok <- ResourceStore.ensure_generated_workspace(workspace_root),
         resolved_target_type <- infer_package_target_type(compile_project_root, target_type),
         has_phone_companion <- phone_companion_app_path(workspace_root) != nil,
         :ok <- copy_pebble_template(template_root, app_root, has_phone_companion),
         {:ok, media_entries} <- stage_project_resources(workspace_root, app_root),
         {:ok, preferences_schema} <- extract_phone_preferences(workspace_root),
         protocol_elm <- companion_protocol_types_path(workspace_root, has_phone_companion),
         {:ok, app_message_keys} <- companion_protocol_message_keys(protocol_elm),
         :ok <-
           write_package_json(
             app_root,
             project_slug,
             resolved_target_type,
             project_name,
             opts,
             media_entries,
             app_message_keys,
             preferences_schema,
             has_phone_companion
           ),
         :ok <- generate_companion_protocol_elm_internal(protocol_elm),
         :ok <- generate_elmc_sources(compile_project_root, app_root, workspace_root),
         :ok <- generate_companion_protocol(protocol_elm, app_root, compile_project_root),
         :ok <- write_generated_preferences_bridge(workspace_root, preferences_schema),
         :ok <- write_preferences_config(app_root, preferences_schema),
         :ok <- compile_phone_companion(workspace_root, app_root),
         :ok <- write_companion_index(workspace_root, app_root, preferences_schema) do
      {:ok, app_root}
    end
  end

  @doc false
  @spec infer_package_target_type(term(), term()) :: String.t()
  def infer_package_target_type(project_root, fallback) when is_binary(project_root) do
    case main_program_target(project_root) do
      {:ok, target} -> package_target_type_from_main_target(target, fallback)
      _ -> normalize_package_target_type(fallback)
    end
  end

  def infer_package_target_type(_project_root, fallback),
    do: normalize_package_target_type(fallback)

  @spec main_program_target(String.t()) :: {:ok, String.t()} | :error
  defp main_program_target(project_root) do
    with {:ok, project} <- Bridge.load_project(project_root),
         {:ok, ir} <- Lowerer.lower_project(project),
         %{} = main_module <- Enum.find(ir.modules, &(&1.name == "Main")),
         %{} = main_decl <- Enum.find(main_module.declarations, &(&1.name == "main")),
         target when is_binary(target) and target != "" <- expr_target(main_decl.expr) do
      {:ok, target}
    else
      _ -> :error
    end
  end

  @spec expr_target(term()) :: String.t() | nil
  defp expr_target(%{op: :qualified_call, target: target}) when is_binary(target), do: target

  defp expr_target(%{"op" => :qualified_call, "target" => target}) when is_binary(target),
    do: target

  defp expr_target(%{"op" => "qualified_call", "target" => target}) when is_binary(target),
    do: target

  defp expr_target(_), do: nil

  @spec package_target_type_from_main_target(String.t(), term()) :: String.t()
  defp package_target_type_from_main_target(target, fallback) when is_binary(target) do
    case target do
      "Pebble.Platform.watchface" -> "watchface"
      "PebblePlatform.watchface" -> "watchface"
      "Pebble.Platform.application" -> "app"
      "PebblePlatform.application" -> "app"
      _ -> normalize_package_target_type(fallback)
    end
  end

  @spec normalize_package_target_type(term()) :: String.t()
  defp normalize_package_target_type(value) when value in ["watchface", "watchapp", "app"],
    do: value

  defp normalize_package_target_type(_), do: "app"

  @spec normalize_workspace_root(term()) :: term()
  defp normalize_workspace_root(path) when is_binary(path) and path != "" do
    abs = Path.expand(path)
    if File.dir?(abs), do: {:ok, abs}, else: {:error, {:workspace_root_not_found, abs}}
  end

  defp normalize_workspace_root(_), do: {:error, :workspace_root_required}

  @spec compile_project_root(term()) :: term()
  defp compile_project_root(workspace_root) do
    candidates = [
      Path.join(workspace_root, "watch"),
      workspace_root,
      Path.join(workspace_root, "protocol"),
      Path.join(workspace_root, "phone")
    ]

    case Enum.find(candidates, &File.exists?(Path.join(&1, "elm.json"))) do
      nil -> {:error, :compile_project_root_not_found}
      root -> {:ok, root}
    end
  end

  @spec ensure_build_app_root(term()) :: term()
  defp ensure_build_app_root(workspace_root) do
    app_root = Path.join(workspace_root, ".pebble-sdk/app")
    _ = File.rm_rf(app_root)

    case File.mkdir_p(app_root) do
      :ok -> {:ok, app_root}
      {:error, reason} -> {:error, {:build_app_root_failed, reason}}
    end
  end

  @spec copy_pebble_template(term(), term(), boolean()) :: term()
  defp copy_pebble_template(template_root, app_root, has_phone_companion) do
    mappings =
      [
        {Path.join(template_root, "wscript"), Path.join(app_root, "wscript")},
        {Path.join(template_root, "src/c/pebble_app_template.c"),
         Path.join(app_root, "src/c/pebble_app_template.c")}
      ]
      |> then(fn mappings ->
        if has_phone_companion do
          mappings ++
            [
              {Path.join(template_root, "src/pkjs/index.js"),
               Path.join(app_root, "src/pkjs/index.js")}
            ]
        else
          mappings
        end
      end)

    Enum.reduce_while(mappings, :ok, fn {source, target}, _acc ->
      case copy_file(source, target) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec write_package_json(
          term(),
          term(),
          term(),
          term(),
          term(),
          term(),
          term(),
          term(),
          boolean()
        ) ::
          term()
  defp write_package_json(
         app_root,
         project_slug,
         target_type,
         project_name,
         opts,
         media_entries,
         app_message_keys,
         preferences_schema,
         has_phone_companion
       ) do
    target_platforms = target_platforms_for_target_type(target_type, opts)

    package =
      %{
        "name" => project_slug,
        "author" => "elm-pebble-ide",
        "version" => "1.0.0",
        "keywords" => ["pebble-app"],
        "private" => true,
        "dependencies" => %{},
        "pebble" => %{
          "displayName" => truncate_display_name(project_name),
          "uuid" => deterministic_uuid(project_slug),
          "sdkVersion" => "3",
          "targetPlatforms" => target_platforms,
          "watchapp" => %{"watchface" => target_type == "watchface"},
          "resources" => %{"media" => media_entries}
        }
      }
      |> maybe_enable_multijs(has_phone_companion)
      |> maybe_put_message_keys(app_message_keys)
      |> maybe_put_configurable_capability(preferences_schema)

    File.write(Path.join(app_root, "package.json"), Jason.encode!(package, pretty: true))
  end

  @spec package_has_phone_companion?(String.t()) :: boolean()
  defp package_has_phone_companion?(app_root) do
    package_path = Path.join(app_root, "package.json")

    with {:ok, source} <- File.read(package_path),
         {:ok, package} <- Jason.decode(source) do
      get_in(package, ["pebble", "enableMultiJS"]) == true or
        File.exists?(Path.join(app_root, "src/pkjs/index.js"))
    else
      _ -> false
    end
  end

  @spec maybe_enable_multijs(map(), boolean()) :: map()
  defp maybe_enable_multijs(package, false), do: package

  defp maybe_enable_multijs(package, true) do
    put_in(package, ["pebble", "enableMultiJS"], true)
  end

  @spec maybe_put_message_keys(map(), map()) :: map()
  defp maybe_put_message_keys(package, app_message_keys) when app_message_keys == %{}, do: package

  defp maybe_put_message_keys(package, app_message_keys) do
    put_in(package, ["pebble", "messageKeys"], app_message_keys)
  end

  @spec maybe_put_configurable_capability(map(), term()) :: map()
  defp maybe_put_configurable_capability(package, nil), do: package

  defp maybe_put_configurable_capability(package, _preferences_schema) do
    update_in(package, ["pebble"], fn pebble ->
      capabilities =
        pebble
        |> Map.get("capabilities", [])
        |> Kernel.++(["configurable"])
        |> Enum.uniq()

      Map.put(pebble, "capabilities", capabilities)
    end)
  end

  @spec stage_project_resources(term(), term()) :: term()
  defp stage_project_resources(workspace_root, app_root) do
    with {:ok, bitmap_entries} <- stage_bitmap_resources(workspace_root, app_root),
         {:ok, font_entries} <- stage_font_resources(workspace_root, app_root),
         :ok <- write_resource_id_header(app_root, bitmap_entries, font_entries) do
      {:ok, bitmap_entries ++ font_entries}
    end
  end

  @spec write_resource_id_header(term(), term(), term()) :: term()
  defp write_resource_id_header(app_root, bitmap_entries, font_entries) do
    header_path = Path.join(app_root, "src/c/generated/resource_ids.h")

    bitmap_cases =
      bitmap_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return RESOURCE_ID_#{Map.fetch!(entry, "name")};"
      end)

    font_cases =
      font_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return RESOURCE_ID_#{Map.fetch!(entry, "name")};"
      end)

    font_height_cases =
      font_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return #{Map.get(entry, "height", 0)};"
      end)

    source = """
    #ifndef ELM_PEBBLE_RESOURCE_IDS_H
    #define ELM_PEBBLE_RESOURCE_IDS_H

    #include <stdint.h>

    #define ELM_PEBBLE_RESOURCE_ID_MISSING UINT32_MAX

    static inline uint32_t elm_pebble_bitmap_resource_id(int64_t bitmap_id) {
      switch (bitmap_id) {
    #{bitmap_cases}
        default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
      }
    }

    static inline uint32_t elm_pebble_font_resource_id(int64_t font_id) {
      switch (font_id) {
    #{font_cases}
        default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
      }
    }

    static inline int64_t elm_pebble_font_resource_height(int64_t font_id) {
      switch (font_id) {
    #{font_height_cases}
        default: return 0;
      }
    }

    #endif
    """

    with :ok <- File.mkdir_p(Path.dirname(header_path)) do
      File.write(header_path, source)
    end
  end

  @spec stage_bitmap_resources(term(), term()) :: term()
  defp stage_bitmap_resources(workspace_root, app_root) do
    manifest_path = Path.join(workspace_root, "watch/resources/bitmaps.json")
    assets_root = Path.join(workspace_root, "watch/resources/bitmaps")

    case File.read(manifest_path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json),
             entries when is_list(entries) <- Map.get(decoded, "entries", []) do
          media_entries =
            entries
            |> Enum.filter(&is_map/1)
            |> Enum.sort_by(&to_string(Map.get(&1, "ctor", "")))
            |> Enum.map(fn row ->
              ctor = to_string(Map.get(row, "ctor", "Bitmap"))
              filename = to_string(Map.get(row, "filename", ""))
              source_path = Path.join(assets_root, filename)
              package_rel = Path.join("bitmaps", filename)
              target_rel = Path.join("resources", package_rel)
              target_path = Path.join(app_root, target_rel)

              if filename != "" and File.exists?(source_path) do
                :ok = File.mkdir_p(Path.dirname(target_path))
                :ok = File.cp(source_path, target_path)
              end

              %{
                "type" => "bitmap",
                "name" => "BITMAP_" <> macro_name(ctor),
                "file" => package_rel
              }
            end)
            |> Enum.filter(fn row -> String.trim(to_string(Map.get(row, "file", ""))) != "" end)

          {:ok, media_entries}
        else
          _ -> {:ok, []}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stage_font_resources(term(), term()) :: term()
  defp stage_font_resources(workspace_root, app_root) do
    manifest_path = Path.join(workspace_root, "watch/resources/fonts.json")
    assets_root = Path.join(workspace_root, "watch/resources/fonts")

    case File.read(manifest_path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json),
             entries when is_list(entries) <- Map.get(decoded, "entries", []) do
          media_entries =
            entries
            |> Enum.filter(&is_map/1)
            |> Enum.sort_by(&to_string(Map.get(&1, "ctor", "")))
            |> Enum.map(fn row ->
              ctor = to_string(Map.get(row, "ctor", "Font"))
              filename = to_string(Map.get(row, "filename", ""))
              height = row |> Map.get("height", 0) |> normalize_font_height()
              source_path = Path.join(assets_root, filename)
              package_rel = Path.join("fonts", filename)
              target_rel = Path.join("resources", package_rel)
              target_path = Path.join(app_root, target_rel)

              if filename != "" and File.exists?(source_path) do
                :ok = File.mkdir_p(Path.dirname(target_path))
                :ok = File.cp(source_path, target_path)
              end

              %{
                "type" => "font",
                "name" => "FONT_" <> macro_name(ctor) <> "_#{height}",
                "file" => package_rel,
                "height" => height
              }
            end)
            |> Enum.filter(fn row -> String.trim(to_string(Map.get(row, "file", ""))) != "" end)

          {:ok, media_entries}
        else
          _ -> {:ok, []}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec macro_name(term()) :: term()
  defp macro_name(name) do
    name
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.upcase()
  end

  @spec normalize_font_height(term()) :: pos_integer()
  defp normalize_font_height(value) when is_integer(value) and value > 0, do: value

  defp normalize_font_height(value) when is_binary(value) do
    case Integer.parse(value) do
      {height, ""} when height > 0 -> height
      _ -> 24
    end
  end

  defp normalize_font_height(_value), do: 24

  @spec target_platforms_for_target_type(term(), term()) :: term()
  defp target_platforms_for_target_type(_target_type, opts) do
    requested = Keyword.get(opts, :target_platforms)

    case requested do
      targets when is_list(targets) ->
        allowed = MapSet.new(supported_emulator_targets())

        normalized =
          targets
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.filter(&MapSet.member?(allowed, &1))
          |> Enum.uniq()

        if normalized == [], do: supported_emulator_targets(), else: normalized

      _ ->
        supported_emulator_targets()
    end
  end

  @spec generate_elmc_sources(term(), term(), term()) :: term()
  defp generate_elmc_sources(project_root, app_root, _workspace_root) do
    compile_out_dir = Path.join(project_root, ".elmc-build")
    stage_out_dir = Path.join(app_root, "src/c/elmc")

    opts = %{
      out_dir: compile_out_dir,
      entry_module: "Main",
      direct_render_only: true,
      prune_runtime: true,
      prune_native_wrappers: true,
      pebble_int32: true
    }

    with :ok <- reset_generated_dir(compile_out_dir),
         :ok <- reset_generated_dir(stage_out_dir),
         {:ok, _} <- Elmc.compile(project_root, opts),
         :ok <- File.mkdir_p(Path.dirname(stage_out_dir)),
         {:ok, _copied} <- File.cp_r(compile_out_dir, stage_out_dir) do
      :ok
    else
      {:error, reason} -> {:error, {:elmc_compile_failed, reason}}
    end
  end

  defp reset_generated_dir(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end

  @spec companion_protocol_types_path(term(), boolean()) :: String.t() | nil
  defp companion_protocol_types_path(_workspace_root, false), do: nil

  defp companion_protocol_types_path(workspace_root, true) do
    protocol_root_types = Path.join(workspace_root, "protocol/src/Companion/Types.elm")
    watch_root_types = Path.join(workspace_root, "watch/src/Companion/Types.elm")

    cond do
      File.exists?(protocol_root_types) ->
        protocol_root_types

      File.exists?(watch_root_types) ->
        watch_root_types

      true ->
        nil
    end
  end

  @spec companion_protocol_message_keys(term()) :: term()
  defp companion_protocol_message_keys(nil), do: {:ok, %{}}

  defp companion_protocol_message_keys(protocol_elm) do
    case CompanionProtocolGenerator.message_keys(protocol_elm) do
      {:ok, keys} -> {:ok, keys}
      {:error, reason} -> {:error, {:companion_protocol_schema_failed, reason}}
    end
  end

  @spec generate_companion_protocol(term(), term(), term()) :: term()
  defp generate_companion_protocol(nil, _app_root, _compile_project_root), do: :ok

  defp generate_companion_protocol(protocol_elm, app_root, compile_project_root) do
    protocol_h = Path.join(app_root, "src/c/generated/companion_protocol.h")
    protocol_c = Path.join(app_root, "src/c/generated/companion_protocol.c")
    protocol_js = Path.join(app_root, "src/pkjs/companion-protocol.js")

    opts = [runtime_tags: companion_protocol_runtime_tags(compile_project_root)]

    case CompanionProtocolGenerator.generate(
           protocol_elm,
           protocol_h,
           protocol_c,
           protocol_js,
           opts
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, {:companion_protocol_generation_failed, reason}}
    end
  end

  defp companion_protocol_runtime_tags(project_root) when is_binary(project_root) do
    with {:ok, project} <- Bridge.load_project(project_root),
         {:ok, ir} <- Lowerer.lower_project(project) do
      constructor_lookup = unqualified_constructor_runtime_tags(project)

      ir.modules
      |> Enum.find(&(&1.name == "Companion.Types"))
      |> case do
        nil ->
          %{}

        mod ->
          mod.unions
          |> Enum.map(fn {type, union} ->
            tags =
              union
              |> Map.get(:tags, %{})
              |> Map.new(fn {constructor, local_tag} ->
                {constructor, Map.get(constructor_lookup, constructor, local_tag)}
              end)

            {type, tags}
          end)
          |> Map.new()
      end
    else
      _ -> %{}
    end
  end

  defp unqualified_constructor_runtime_tags(project) do
    project.modules
    |> Enum.flat_map(fn frontend_module ->
      frontend_module.declarations
      |> Enum.filter(&(&1.kind == :union))
      |> Enum.flat_map(fn union ->
        union
        |> Map.get(:constructors, [])
        |> Enum.with_index(1)
        |> Enum.map(fn {constructor, index} -> {constructor.name, index} end)
      end)
    end)
    |> Map.new()
  end

  @spec generate_companion_protocol_elm_internal(term()) :: term()
  defp generate_companion_protocol_elm_internal(nil), do: :ok

  defp generate_companion_protocol_elm_internal(protocol_elm) do
    internal_elm = Path.join(Path.dirname(protocol_elm), "Internal.elm")

    case CompanionProtocolGenerator.generate_elm_internal(protocol_elm, internal_elm) do
      :ok -> :ok
      {:error, reason} -> {:error, {:companion_protocol_elm_generation_failed, reason}}
    end
  end

  @spec compile_phone_companion(term(), term()) :: term()
  defp compile_phone_companion(workspace_root, app_root) do
    case phone_companion_app_path(workspace_root) do
      nil ->
        :ok

      phone_app ->
        out_file = Path.join(app_root, "src/pkjs/elm-companion.js")

        with {:ok, elm_bin} <- elm_bin(),
             :ok <- File.mkdir_p(Path.dirname(out_file)) do
          phone_root = Path.expand("../..", phone_app)

          {output, exit_code} =
            System.cmd(
              elm_bin,
              ["make", "src/CompanionApp.elm", "--optimize", "--output", out_file],
              cd: phone_root,
              stderr_to_stdout: true,
              env: [{"LC_ALL", "C"}]
            )

          if exit_code == 0 do
            :ok
          else
            {:error,
             {:phone_companion_elm_make_failed,
              %{
                command: "#{elm_bin} make src/CompanionApp.elm --optimize --output #{out_file}",
                output: output,
                exit_code: exit_code,
                cwd: phone_root
              }}}
          end
        end
    end
  end

  @spec extract_phone_preferences(term()) :: term()
  defp extract_phone_preferences(workspace_root) do
    case phone_companion_project_root(workspace_root) do
      nil -> {:ok, nil}
      phone_root -> PebblePreferences.extract(phone_root)
    end
  end

  @spec write_preferences_config(term(), term()) :: term()
  defp write_preferences_config(_app_root, nil), do: :ok

  defp write_preferences_config(app_root, preferences_schema) do
    config_path = Path.join(app_root, "src/pkjs/generated/preferences.html")

    with :ok <- File.mkdir_p(Path.dirname(config_path)) do
      File.write(config_path, PebblePreferences.render_html(preferences_schema))
    end
  end

  @spec write_generated_preferences_bridge(term(), term()) :: term()
  defp write_generated_preferences_bridge(_workspace_root, nil), do: :ok

  defp write_generated_preferences_bridge(workspace_root, preferences_schema) do
    with phone_root when is_binary(phone_root) <- phone_companion_project_root(workspace_root),
         source when is_binary(source) <-
           PebblePreferences.generated_bridge_source(preferences_schema) do
      path = Path.join(phone_root, PebblePreferences.generated_bridge_rel_path())

      with :ok <- File.mkdir_p(Path.dirname(path)) do
        File.write(path, source)
      end
    else
      nil -> :ok
    end
  end

  @spec phone_companion_app_path(term()) :: String.t() | nil
  defp phone_companion_app_path(workspace_root) do
    path = Path.join([workspace_root, "phone", "src", "CompanionApp.elm"])

    if File.exists?(path) and File.exists?(Path.join(workspace_root, "phone/elm.json")) do
      path
    end
  end

  @spec phone_companion_project_root(term()) :: String.t() | nil
  defp phone_companion_project_root(workspace_root) do
    root = Path.join(workspace_root, "phone")

    if File.exists?(Path.join(root, "elm.json")) do
      root
    end
  end

  @spec write_companion_index(term(), term(), term()) :: term()
  defp write_companion_index(workspace_root, app_root, preferences_schema) do
    case phone_companion_app_path(workspace_root) do
      nil ->
        :ok

      _phone_app ->
        index_path = Path.join(app_root, "src/pkjs/index.js")

        with :ok <- File.mkdir_p(Path.dirname(index_path)) do
          File.write(index_path, elm_companion_index_js(preferences_schema))
        end
    end
  end

  @spec elm_companion_index_js(term()) :: String.t()
  defp elm_companion_index_js(preferences_schema) do
    preferences_url =
      if preferences_schema do
        PebblePreferences.data_url(preferences_schema)
      end

    """
    var pendingIncoming = [];
    var incomingPort = null;
    var protocol = require("./companion-protocol.js");
    var generatedConfigurationUrl = #{Jason.encode!(preferences_url)};
    var configurationStorageKey = "elm-pebble.configuration.response";
    var appMessageKeyNamesById = {};
    var appMessageKeyIdsByName = {};

    function readStoredConfigurationResponse() {
        if (typeof localStorage === "undefined" || !localStorage) {
            return null;
        }

        try {
            var response = localStorage.getItem(configurationStorageKey);
            return typeof response === "string" ? response : null;
        } catch (_error) {
            return null;
        }
    }

    function writeStoredConfigurationResponse(response) {
        if (typeof localStorage === "undefined" || !localStorage || typeof response !== "string") {
            return;
        }

        try {
            localStorage.setItem(configurationStorageKey, response);
        } catch (_error) {
        }
    }

    function companionFlags() {
        return {
            configurationResponse: readStoredConfigurationResponse()
        };
    }

    Object.keys(protocol).forEach(function (key) {
        if (key.indexOf("KEY_") !== 0 || typeof protocol[key] !== "number") {
            return;
        }

        var name = key.substring(4).toLowerCase();
        appMessageKeyNamesById[protocol[key]] = name;
        appMessageKeyIdsByName[name] = protocol[key];
    });

    function appMessageValue(payload, name) {
        if (!payload) {
            return undefined;
        }

        var id = appMessageKeyIdsByName[name];
        if (Object.prototype.hasOwnProperty.call(payload, name)) {
            return payload[name];
        }
        if (Object.prototype.hasOwnProperty.call(payload, String(id))) {
            return payload[String(id)];
        }
        if (Object.prototype.hasOwnProperty.call(payload, id)) {
            return payload[id];
        }
        return undefined;
    }

    function normalizeIncomingAppMessage(payload) {
        if (!payload) {
            return payload;
        }

        var normalized = {};
        Object.keys(payload).forEach(function (key) {
            var name = appMessageKeyNamesById[key] || key;
            normalized[name] = payload[key];
        });

        Object.keys(appMessageKeyIdsByName).forEach(function (name) {
            var value = appMessageValue(payload, name);
            if (typeof value !== "undefined") {
                normalized[name] = value;
            }
        });

        return normalized;
    }

    function normalizeOutgoingAppMessage(payload) {
        if (!payload) {
            return payload;
        }

        var normalized = {};
        Object.keys(payload).forEach(function (key) {
            var id = appMessageKeyIdsByName[key];
            normalized[typeof id === "number" ? id : key] = payload[key];
        });

        return normalized;
    }

    function deliverIncoming(payload) {
        console.log("bridge -> Elm companion", JSON.stringify(payload));
        if (incomingPort) {
            incomingPort.send(payload);
        } else {
            console.log("bridge queued incoming for Elm companion");
            pendingIncoming.push(payload);
        }
    }

    function openConfigurationUrl(url) {
        if (url && typeof Pebble.openURL === "function") {
            console.log("opening companion configuration", url);
            Pebble.openURL(url);
        }
    }

    function handleOutgoing(payload) {
        if (payload && payload.api === "configuration") {
            if (payload.op === "open") {
                console.log("Elm companion requested configuration", JSON.stringify(payload.payload || {}));
                openConfigurationUrl((payload.payload && payload.payload.url) || generatedConfigurationUrl);
            }
            return;
        }

        if (payload && payload.api === "appMessage" && payload.op === "send") {
            console.log("Elm companion sendAppMessage payload", JSON.stringify(payload.payload || {}));
            Pebble.sendAppMessage(normalizeOutgoingAppMessage(payload.payload || {}));
            return;
        }

        console.log("Elm companion sendAppMessage payload", JSON.stringify(payload));
        Pebble.sendAppMessage(normalizeOutgoingAppMessage(payload));
    }

    function installXmlHttpRequestCompatibility() {
        if (typeof XMLHttpRequest === "undefined") {
            return;
        }

        var proto = XMLHttpRequest.prototype;
        if (!proto) {
            return;
        }

        if (typeof proto.getAllResponseHeaders !== "function") {
            proto.getAllResponseHeaders = function () {
                return "";
            };
        }

        if (typeof proto.addEventListener !== "function") {
            proto.addEventListener = function (name, callback) {
                if (typeof callback !== "function") {
                    return;
                }

                var property = "on" + name;
                var previous = this[property];
                this[property] = function (event) {
                    if (
                        name === "load" &&
                        typeof this.responseText !== "undefined" &&
                        (typeof this.response === "undefined" || this.response === null || this.response === "")
                    ) {
                        try {
                            this.response = this.responseText;
                        } catch (_error) {
                        }
                    }
                    if (typeof previous === "function") {
                        previous.call(this, event);
                    }
                    callback.call(this, event);
                };
            };
        }
    }

    installXmlHttpRequestCompatibility();

    Pebble.addEventListener("appmessage", function (event) {
        if (!event || !event.payload) {
            return;
        }

        console.log("watch -> Elm companion", JSON.stringify(event.payload));
        deliverIncoming(normalizeIncomingAppMessage(event.payload));
    });

    if (generatedConfigurationUrl) {
        Pebble.addEventListener("showConfiguration", function () {
            console.log("Pebble showConfiguration event");
            openConfigurationUrl(generatedConfigurationUrl);
        });

        Pebble.addEventListener("webviewclosed", function (event) {
            var response = event && typeof event.response === "string" ? event.response : null;
            console.log("Pebble webviewclosed response", response);
            writeStoredConfigurationResponse(response);

            deliverIncoming({
                event: "configuration.closed",
                payload: {
                    response: response
                }
            });
        });
    }

    var elmModule = require("./elm-companion.js");

    function bootElmCompanion() {
        var elmRoot = elmModule.Elm || (typeof Elm !== "undefined" ? Elm : null);
        var app;

        if (!elmRoot || !elmRoot.CompanionApp) {
            throw new Error("Elm.CompanionApp is not available");
        }

        try {
            app = elmRoot.CompanionApp.init({ flags: companionFlags() });
        } catch (_error) {
            app = elmRoot.CompanionApp.init();
        }

        if (app.ports && app.ports.outgoing) {
            app.ports.outgoing.subscribe(function (payload) {
                handleOutgoing(payload);
            });
        }

        if (app.ports && app.ports.incoming) {
            incomingPort = app.ports.incoming;
            while (pendingIncoming.length > 0) {
                incomingPort.send(pendingIncoming.shift());
            }
        }
    }

    Pebble.addEventListener("ready", function () {
        console.log("PKJS ready; booting Elm companion");
        bootElmCompanion();
    });
    """
  end

  @spec copy_file(term(), term()) :: term()
  defp copy_file(source, target) do
    with :ok <- File.mkdir_p(Path.dirname(target)),
         :ok <- File.cp(source, target) do
      :ok
    end
  end

  @spec truncate_display_name(term()) :: term()
  defp truncate_display_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> case do
      "" -> "elm-pebble"
      value -> String.slice(value, 0, 31)
    end
  end

  @spec deterministic_uuid(term()) :: term()
  defp deterministic_uuid(seed) do
    bytes =
      :crypto.hash(:sha256, seed)
      |> binary_part(0, 16)
      |> :binary.bin_to_list()

    bytes =
      bytes
      |> List.update_at(6, &((&1 &&& 0x0F) ||| 0x40))
      |> List.update_at(8, &((&1 &&& 0x3F) ||| 0x80))

    hex =
      bytes
      |> :binary.list_to_bin()
      |> Base.encode16(case: :lower)

    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end

  @spec command_cwd(term()) :: term()
  defp command_cwd(opts) do
    case Keyword.get(opts, :cwd) do
      cwd when is_binary(cwd) and cwd != "" ->
        if File.dir?(cwd), do: {:ok, cwd}, else: template_app_root()

      _ ->
        template_app_root()
    end
  end

  @spec normalize_publish_app_root(term()) :: term()
  defp normalize_publish_app_root(path) when is_binary(path) and path != "" do
    abs = Path.expand(path)
    if File.dir?(abs), do: {:ok, abs}, else: {:error, {:publish_app_root_not_found, abs}}
  end

  defp normalize_publish_app_root(_), do: {:error, :publish_app_root_required}

  @spec maybe_append_release_notes(term(), term()) :: term()
  defp maybe_append_release_notes(args, notes) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: args, else: args ++ ["--release-notes", trimmed]
  end

  defp maybe_append_release_notes(args, _), do: args

  @spec maybe_append_flag(term(), term(), term()) :: term()
  defp maybe_append_flag(args, true, flag), do: args ++ [flag]
  defp maybe_append_flag(args, _enabled, _flag), do: args

  @spec pebble_bin() :: term()
  defp pebble_bin do
    cond do
      configured = Application.get_env(:ide, Ide.PebbleToolchain, []) |> Keyword.get(:pebble_bin) ->
        {:ok, configured}

      resolved = System.find_executable("pebble") ->
        {:ok, resolved}

      true ->
        {:error, :pebble_cli_not_found}
    end
  end

  @spec elm_bin() :: term()
  defp elm_bin do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:elm_bin)

    env_bin = System.get_env("ELM_BIN")

    [
      configured,
      env_bin,
      System.find_executable("elm"),
      Path.expand("../../../elm_pebble_dev/node_modules/.bin/elm", __DIR__)
    ]
    |> Enum.find_value(fn
      path when is_binary(path) and path != "" ->
        expanded = Path.expand(path)
        if File.exists?(expanded), do: {:ok, expanded}

      _ ->
        nil
    end) || {:error, :elm_compiler_not_found}
  end

  @spec template_app_root() :: term()
  defp template_app_root do
    path =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:template_app_root)

    if is_binary(path) and File.dir?(path) do
      {:ok, path}
    else
      {:error, :template_app_root_not_found}
    end
  end

  @spec configured_emulator_target() :: term()
  defp configured_emulator_target do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_target, "basalt")
  end

  @spec latest_pbw(term()) :: term()
  defp latest_pbw(smoke_root) do
    build_root = Path.join(smoke_root, "build")

    case File.ls(build_root) do
      {:ok, files} ->
        pbws =
          files
          |> Enum.filter(&String.ends_with?(&1, ".pbw"))
          |> Enum.map(&Path.join(build_root, &1))
          |> Enum.sort_by(&mtime_sort/1, :desc)

        case pbws do
          [latest | _] -> {:ok, latest}
          [] -> {:error, :pbw_artifact_not_found}
        end

      {:error, reason} ->
        {:error, {:list_build_dir_failed, reason}}
    end
  end

  @spec mtime_sort(term()) :: term()
  defp mtime_sort(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> {{1970, 1, 1}, {0, 0, 0}}
    end
  end

  @spec normalize_package_path(term()) :: term()
  defp normalize_package_path(path) when is_binary(path) do
    abs = Path.expand(path)

    cond do
      path == "" ->
        {:error, :package_path_required}

      not File.exists?(abs) ->
        {:error, {:package_path_not_found, abs}}

      not String.ends_with?(String.downcase(abs), ".pbw") ->
        {:error, {:package_path_not_pbw, abs}}

      true ->
        {:ok, abs}
    end
  end

  defp normalize_package_path(_), do: {:error, :package_path_required}
end
