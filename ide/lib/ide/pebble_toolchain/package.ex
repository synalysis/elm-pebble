defmodule Ide.PebbleToolchain.Package do
  @moduledoc """
  Boundary for Pebble SDK and emulator command execution.
  """
  alias Ide.Compiler
  alias Ide.ProjectCapabilities
  alias Ide.PebbleToolchain.{Build, Command, Prepare, Types}

  @forbidden_build_warning_snippets [
    "warning: 'ELMC_PROCESS_SLOTS' defined but not used",
    "warning: 'ELMC_NEXT_PROCESS_ID' defined but not used"
  ]

  @type project_slug :: Types.project_slug()
  @type opts :: Types.opts()
  @type wire_input :: Types.wire_input()
  @type command_result :: Types.command_result()
  @type package_result :: Types.package_result()
  @type pebble_opts :: Types.pebble_opts()
  @type toolchain_error :: Types.toolchain_error()
  @type pebble_package :: Types.pebble_package()
  @type pebble_media_entry :: Types.pebble_media_entry()
  @type elmc_compile_opts :: Types.elmc_compile_opts()
  @type elmc_compile_result :: Types.elmc_compile_result()
  @type emulator_control_params :: Types.emulator_control_params()
  @type core_ir_expr :: Types.core_ir_expr()

  @callback build(project_slug(), opts()) :: {:ok, command_result()} | {:error, toolchain_error()}
  @callback package(project_slug(), opts()) ::
              {:ok, package_result()} | {:error, toolchain_error()}
  @callback publish(project_slug(), opts()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback run_emulator(project_slug(), opts()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback stop_emulator(project_slug(), opts()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback run_emulator_control(project_slug(), String.t(), emulator_control_params()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback run_screenshot(project_slug(), String.t(), String.t()) ::
              {:ok, command_result()} | {:error, toolchain_error()}

  @doc """
  Builds a project-specific PBW artifact and returns the package path.
  """
  @spec package(project_slug(), opts()) :: {:ok, package_result()} | {:error, toolchain_error()}
  def package(project_slug, opts) do
    workspace_root = Keyword.get(opts, :workspace_root)
    target_type = Keyword.get(opts, :target_type, "app")
    project_name = Keyword.get(opts, :project_name, project_slug)

    with {:ok, workspace_root} <- Prepare.normalize_workspace_root(workspace_root),
         :ok <-
           Compiler.check_workspace(project_slug,
             workspace_root: workspace_root,
             source_roots: Keyword.get(opts, :source_roots)
           ),
         {:ok, app_root, resolved_target_type} <-
           Prepare.prepare_project_build_app(
             project_slug,
             workspace_root,
             target_type,
             project_name,
             opts
           ),
         {:ok, build_result} <-
           Build.build(
             project_slug,
             opts
             |> Keyword.put(:app_root, app_root)
             |> Keyword.put(:target_type, resolved_target_type)
           ),
         :ok <- ensure_successful_build(build_result),
         :ok <- ensure_no_forbidden_build_warnings(build_result),
         {:ok, artifact_path} <- latest_pbw(app_root),
         {:ok, artifact_path} <- Ide.Emulator.PBW.prune_empty_media_resources(artifact_path),
         {:ok, artifact_path} <- Ide.Emulator.PBW.prune_development_artifacts(artifact_path) do
      has_phone_companion = Prepare.package_has_phone_companion?(app_root)

      {:ok,
       %{
         status: build_result.status,
         artifact_path: artifact_path,
         build_result: build_result,
         app_root: app_root,
         has_phone_companion: has_phone_companion,
         has_companion_preferences:
           has_phone_companion and ProjectCapabilities.companion_preferences?(workspace_root)
       }}
    end
  end

  @doc """
  Runs `pebble publish` for a prepared Pebble app directory.
  """
  @spec publish(project_slug(), opts()) :: {:ok, command_result()} | {:error, toolchain_error()}
  def publish(_project_slug, opts) do
    with {:ok, app_root} <- normalize_publish_app_root(Keyword.get(opts, :app_root)) do
      release_notes = Keyword.get(opts, :release_notes, "")
      description = Keyword.get(opts, :description, "")
      version = Keyword.get(opts, :version, "")
      screenshots = Keyword.get(opts, :screenshots, [])
      is_published = Keyword.get(opts, :is_published, false)
      all_platforms = Keyword.get(opts, :all_platforms, false)
      include_gifs = Keyword.get(opts, :gif_all_platforms, false)
      firebase_token = Keyword.get(opts, :firebase_id_token)

      args =
        ["publish", "--non-interactive"]
        |> maybe_append_release_notes(release_notes)
        |> maybe_append_version(version)
        |> maybe_append_description(description)
        |> maybe_append_screenshots(screenshots)
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

      Command.run_pebble(args, cwd: app_root, env: env)
    end
  end

  @spec ensure_successful_build(command_result()) :: :ok | {:error, toolchain_error()}
  defp ensure_successful_build(%{status: :ok}), do: :ok
  defp ensure_successful_build(result), do: {:error, {:pebble_build_failed, result}}

  @spec ensure_no_forbidden_build_warnings(command_result()) :: :ok | {:error, toolchain_error()}
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
  Returns configured Pebble app template root directory.
  """
  @spec template_app_root_path() :: {:ok, String.t()} | {:error, toolchain_error()}
  def template_app_root_path do
    Command.template_app_root()
  end

  @spec infer_package_target_type(String.t(), String.t()) :: String.t()
  def infer_package_target_type(project_root, fallback),
    do: Prepare.infer_package_target_type(project_root, fallback)

  @doc """
  Returns the stable Pebble app UUID for a project slug (same value written to `package.json`).
  """
  @spec deterministic_app_uuid(String.t()) :: String.t()
  def deterministic_app_uuid(slug) when is_binary(slug) do
    Prepare.deterministic_uuid(slug)
  end

  @spec normalize_publish_app_root(String.t() | nil) ::
          {:ok, String.t()} | {:error, toolchain_error()}
  defp normalize_publish_app_root(path) when is_binary(path) and path != "" do
    abs = Path.expand(path)
    if File.dir?(abs), do: {:ok, abs}, else: {:error, {:publish_app_root_not_found, abs}}
  end

  defp normalize_publish_app_root(_), do: {:error, :publish_app_root_required}

  @spec maybe_append_release_notes([String.t()], String.t()) :: [String.t()]
  defp maybe_append_release_notes(args, notes) when is_binary(notes) do
    trimmed = String.trim(notes)
    if trimmed == "", do: args, else: args ++ ["--release-notes", trimmed]
  end

  defp maybe_append_release_notes(args, _), do: args

  @spec maybe_append_version([String.t()], String.t()) :: [String.t()]
  defp maybe_append_version(args, version) when is_binary(version) do
    trimmed = String.trim(version)
    if trimmed == "", do: args, else: args ++ ["--version", trimmed]
  end

  defp maybe_append_version(args, _), do: args

  @spec maybe_append_description([String.t()], String.t()) :: [String.t()]
  defp maybe_append_description(args, description) when is_binary(description) do
    trimmed = String.trim(description)
    if trimmed == "", do: args, else: args ++ ["--description", trimmed]
  end

  defp maybe_append_description(args, _), do: args

  @spec maybe_append_screenshots([String.t()], [String.t()]) :: [String.t()]
  defp maybe_append_screenshots(args, screenshots) when is_list(screenshots) do
    paths =
      screenshots
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if paths == [], do: args, else: args ++ ["--screenshots" | paths]
  end

  defp maybe_append_screenshots(args, _), do: args

  @spec maybe_append_flag([String.t()], boolean(), String.t()) :: [String.t()]
  defp maybe_append_flag(args, enabled?, flag) do
    if enabled?, do: args ++ [flag], else: args
  end

  @spec latest_pbw(String.t()) :: {:ok, String.t()} | {:error, toolchain_error()}
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

  @spec mtime_sort(String.t()) ::
          {{integer(), integer(), integer()}, {integer(), integer(), integer()}}
  defp mtime_sort(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> {{1970, 1, 1}, {0, 0, 0}}
    end
  end
end
