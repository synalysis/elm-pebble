defmodule Ide.PebbleToolchain.Elmc do
  @moduledoc false

  require Logger

  alias Elmc.CLI
  alias Elmc.Runtime.Generator, as: RuntimeGenerator
  alias Ide.Compiler
  alias Ide.PebbleToolchain.Types

  @compile_stamp_file ".elmc_compile_stamp.json"
  @codegen_stamp_keys ~w(entry_module strip_dead_code pebble_int32 prune_runtime prune_native_wrappers prune_direct_generic direct_render_only codegen_profile plan_ir_mode plan_ir_strict prod emit_bytecode)a

  @type elmc_compile_opts :: Types.elmc_compile_opts()
  @type elmc_compile_result :: Types.elmc_compile_result()
  @type toolchain_error :: Types.toolchain_error()

  @ide_default_codegen_profile :size

  @spec watch_compile_opts(String.t(), [String.t()], Types.elmc_extra_opts()) ::
          Types.watch_compile_opts()
  def watch_compile_opts(out_dir, target_platforms, extra \\ %{})
      when is_binary(out_dir) and is_list(target_platforms) and is_map(extra) do
    profile = codegen_profile_from_extra(extra)
    prod = Map.get(extra, :prod, true)
    debug_usage_policy = Map.get(extra, :debug_usage_policy, :error)
    plan_ir_mode = Map.get(extra, :plan_ir_mode, :primary)
    plan_ir_strict = Map.get(extra, :plan_ir_strict, true)

    %{
      out_dir: out_dir,
      entry_module: "Main",
      direct_render_only: direct_render_only?(target_platforms),
      prune_direct_generic: prune_direct_generic?(target_platforms),
      prune_runtime: true,
      prune_native_wrappers: true,
      pebble_int32: true,
      strip_dead_code: true,
      prod: prod,
      plan_ir_mode: plan_ir_mode,
      plan_ir_strict: plan_ir_strict,
      debug_usage_policy: debug_usage_policy,
      codegen_profile: profile
    }
    |> Map.merge(extra)
  end

  @spec optimize_for_size?(String.t()) :: boolean()
  def optimize_for_size?(project_dir) when is_binary(project_dir) do
    codegen_profile_for_project_dir(project_dir) == :size
  end

  @spec codegen_profile_for_project_dir(String.t(), Types.elmc_extra_opts()) :: :default | :balanced | :size
  def codegen_profile_for_project_dir(project_dir, extra_opts \\ %{}) when is_binary(project_dir) do
    resolve_codegen_profile(extra_opts, project_dir)
  end

  @spec target_platforms_for_project_dir(String.t()) :: [String.t()] | nil
  def target_platforms_for_project_dir(project_dir) when is_binary(project_dir) do
    with {:ok, config_dir} <- pebble_config_dir(project_dir),
         {:ok, %{"release_defaults" => defaults}} when is_map(defaults) <-
           read_project_json(config_dir),
         platforms when is_list(platforms) <- Map.get(defaults, "target_platforms"),
         normalized when normalized != [] <- normalize_stamp_platforms(platforms) do
      normalized
    else
      _ -> nil
    end
  end

  @doc false
  @spec watch_target_platforms(String.t(), [String.t()]) :: [String.t()]
  def watch_target_platforms(project_dir, fallback \\ []) when is_binary(project_dir) do
    case target_platforms_for_project_dir(project_dir) do
      platforms when is_list(platforms) and platforms != [] -> platforms
      _ -> normalize_stamp_platforms(fallback)
    end
  end

  @doc false
  @spec normalize_stamp_platforms([String.t()]) :: [String.t()]
  def normalize_stamp_platforms(platforms) when is_list(platforms) do
    platforms
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec compile_for_project_dir(String.t(), String.t(), Types.elmc_extra_opts()) ::
          Elmc.CLI.project_run()
  def compile_for_project_dir(project_dir, out_dir, extra_opts \\ %{})
      when is_binary(project_dir) and is_binary(out_dir) and is_map(extra_opts) do
    target_platforms = watch_target_platforms(project_dir, Map.get(extra_opts, :target_platforms, []))

    elmc_opts =
      extra_opts
      |> Map.put_new(:codegen_profile, codegen_profile_for_project_dir(project_dir, extra_opts))
      |> then(&watch_compile_opts(out_dir, target_platforms, &1))

    Elmc.CLI.compile_project(project_dir, out_dir, elmc_opts: elmc_opts)
    |> tap(fn result ->
      # `compile_project/3` returns a CLI `project_run` map (`%{status: :ok, ...}`),
      # not `{:ok, _}`. Without a stamp, PBW packaging cannot reuse `.elmc-build` and
      # recompiles watch a second time on every Build.
      if compile_project_succeeded?(result) do
        :ok = write_compile_stamp(project_dir, out_dir, elmc_opts, target_platforms)
      end
    end)
  end

  @doc false
  @spec compile_project_succeeded?(term()) :: boolean()
  def compile_project_succeeded?({:ok, _}), do: true
  def compile_project_succeeded?(%{status: :ok}), do: true
  def compile_project_succeeded?(_), do: false

  @spec generate_sources(String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, toolchain_error()}
  def generate_sources(project_root, app_root, _workspace_root, opts \\ []) do
    compile_out_dir = Path.join(project_root, ".elmc-build")
    stage_out_dir = Path.join(app_root, "src/c/elmc")
    target_platforms = watch_target_platforms(project_root, Keyword.get(opts, :target_platforms, []))

    compile_extra = %{
      prod: Keyword.get(opts, :prod, true),
      debug_usage_policy: Keyword.get(opts, :debug_usage_policy, :error),
      plan_ir_mode: Keyword.get(opts, :plan_ir_mode, :primary),
      plan_ir_strict: Keyword.get(opts, :plan_ir_strict, true),
      codegen_profile: codegen_profile_for_project_dir(project_root, %{})
    }

    compile_opts = watch_compile_opts(compile_out_dir, target_platforms, compile_extra)

    with :ok <- reset_generated_dir(stage_out_dir),
         :ok <-
           ensure_staged_elmc_sources(
             project_root,
             compile_out_dir,
             stage_out_dir,
             compile_opts,
             target_platforms,
             opts
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ensure_staged_elmc_sources(String.t(), String.t(), String.t(), Types.watch_compile_opts(), [
          String.t()
        ], keyword()) :: :ok | {:error, term()}
  defp ensure_staged_elmc_sources(
         project_root,
         compile_out_dir,
         stage_out_dir,
         compile_opts,
         target_platforms,
         opts
       ) do
    cond do
      reuse_cached_compile?(project_root, compile_out_dir, compile_opts, target_platforms) ->
        Logger.debug(
          "[elmc] reusing cached compile tree for #{project_root} (stamp match)"
        )

        copy_compile_tree!(compile_out_dir, stage_out_dir)

      reuse_fresh_build?(project_root, compile_out_dir, opts) ->
        Logger.info(
          "[elmc] reusing fresh .elmc-build from #{project_root} for PBW packaging (revision match)"
        )

        copy_compile_tree!(compile_out_dir, stage_out_dir)

      true ->
        with :ok <- reset_generated_dir(compile_out_dir),
             {:ok, _} <- map_compile_failure(compile_project_artifacts(project_root, compile_opts)),
             :ok <- write_compile_stamp(project_root, compile_out_dir, compile_opts, target_platforms),
             :ok <- copy_compile_tree!(compile_out_dir, stage_out_dir) do
          :ok
        end
    end
  end

  @spec reuse_fresh_build?(String.t(), String.t(), keyword()) :: boolean()
  defp reuse_fresh_build?(project_root, compile_out_dir, opts) when is_binary(project_root) do
    Keyword.get(opts, :reuse_elmc_build, false) and
      File.regular?(Path.join(compile_out_dir, "c/elmc_generated.c")) and
      revision_stamp_matches?(project_root, compile_out_dir)
  end

  @spec revision_stamp_matches?(String.t(), String.t()) :: boolean()
  defp revision_stamp_matches?(project_root, compile_out_dir) do
    case File.read(compile_stamp_path(compile_out_dir)) do
      {:ok, body} ->
        with {:ok, %{"revision" => revision}} <- Jason.decode(body),
             true <- is_binary(revision) do
          revision == Compiler.compile_source_revision(project_root)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  @spec reuse_cached_compile?(String.t(), String.t(), map(), [String.t()]) :: boolean()
  defp reuse_cached_compile?(project_root, compile_out_dir, compile_opts, target_platforms) do
    generated_c = Path.join(compile_out_dir, "c/elmc_generated.c")
    stamp_path = compile_stamp_path(compile_out_dir)

    File.regular?(generated_c) and stamp_path |> File.read() |> stamp_matches?(project_root, compile_opts, target_platforms)
  end

  @spec compile_stamp_path(String.t()) :: String.t()
  defp compile_stamp_path(out_dir), do: Path.join(out_dir, @compile_stamp_file)

  @doc false
  @spec write_compile_stamp(String.t(), String.t(), map(), [String.t()]) :: :ok
  def write_compile_stamp(project_root, out_dir, compile_opts, target_platforms) do
    payload = compile_stamp_payload(project_root, compile_opts, target_platforms)
    File.mkdir_p!(out_dir)
    File.write!(compile_stamp_path(out_dir), payload)
  end

  @spec compile_stamp_payload(String.t(), map(), [String.t()]) :: String.t()
  defp compile_stamp_payload(project_root, compile_opts, target_platforms) do
    Jason.encode!(%{
      revision: Compiler.compile_source_revision(project_root),
      target_platforms: normalize_stamp_platforms(target_platforms),
      codegen: codegen_stamp(compile_opts)
    })
  end

  @spec codegen_stamp(map()) :: map()
  defp codegen_stamp(compile_opts) when is_map(compile_opts) do
    compile_opts
    |> Map.take(@codegen_stamp_keys)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  @spec stamp_matches?({:ok, String.t()} | {:error, term()}, String.t(), map(), [String.t()]) :: boolean()
  defp stamp_matches?({:ok, body}, project_root, compile_opts, target_platforms) do
    expected = compile_stamp_payload(project_root, compile_opts, target_platforms)
    body == expected
  end

  defp stamp_matches?({:error, _}, _project_root, _compile_opts, _target_platforms), do: false

  @spec copy_compile_tree!(String.t(), String.t()) :: :ok
  defp copy_compile_tree!(compile_out_dir, stage_out_dir) do
    File.mkdir_p!(Path.dirname(stage_out_dir))

    case File.cp_r(compile_out_dir, stage_out_dir) do
      {:ok, _} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end

  # Companion protocol C is generated after elmc runtime pruning, so symbols such as
  # elmc_list_from_int_array are not seen on the first pass. Re-prune staged runtime
  # against all watch-side C sources (generated Elm + companion protocol).
  @spec reprune_staged_runtime(String.t()) :: :ok | {:error, toolchain_error()}
  def reprune_staged_runtime(app_root) when is_binary(app_root) do
    runtime_dir = Path.join(app_root, "src/c/elmc/runtime")
    prune_from_dir = Path.join(app_root, "src/c")

    case RuntimeGenerator.write_runtime(runtime_dir,
           prune_from_dir: prune_from_dir,
           pebble_int32: true
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, {:runtime_reprune_failed, reason}}
    end
  end

  @spec compile_watch_project(String.t(), elmc_compile_opts()) ::
          {:ok, elmc_compile_result()} | {:error, toolchain_error()}
  def compile_watch_project(project_root, opts) do
    map_compile_failure(compile_project_with_opts(project_root, opts))
  end

  @spec compile_project_with_opts(String.t(), elmc_compile_opts()) ::
          {:ok, elmc_compile_result()} | {:error, Types.elmc_failure_reason()}
  def compile_project_with_opts(project_root, opts) when is_binary(project_root) and is_map(opts) do
    compile_with_rescue(&compile_project_with_opts/2, &CLI.compile_with_opts_impl/2, project_root, opts)
  end

  @spec compile_project_artifacts(String.t(), elmc_compile_opts()) ::
          {:ok, elmc_compile_result()} | {:error, Types.elmc_failure_reason()}
  def compile_project_artifacts(project_root, opts) when is_binary(project_root) and is_map(opts) do
    compile_with_rescue(
      &compile_project_artifacts/2,
      &CLI.compile_artifacts_with_opts_impl/2,
      project_root,
      opts
    )
  end

  @type compile_runner ::
          (String.t(), elmc_compile_opts() ->
             {:ok, elmc_compile_result()} | {:error, Types.elmc_failure_reason()})

  @spec compile_with_rescue(
          compile_runner(),
          compile_runner(),
          String.t(),
          elmc_compile_opts()
        ) :: {:ok, elmc_compile_result()} | {:error, Types.elmc_failure_reason()}
  defp compile_with_rescue(retry_fun, runner, project_root, opts)
       when is_function(retry_fun, 2) and is_function(runner, 2) and is_binary(project_root) and
              is_map(opts) do
    runner.(project_root, opts)
  rescue
    exception in ArgumentError ->
      if direct_render_only_view_error?(exception, opts) do
        retry_fun.(project_root, Map.put(opts, :direct_render_only, false))
      else
        {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
      end

    exception ->
      {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:compiler_exception, kind, reason}}
  end

  @spec map_compile_failure(
          {:ok, elmc_compile_result()} | {:error, Types.elmc_failure_reason()}
        ) :: {:ok, elmc_compile_result()} | {:error, toolchain_error()}
  defp map_compile_failure({:ok, _} = ok), do: ok
  defp map_compile_failure({:error, reason}), do: {:error, {:elmc_compile_failed, reason}}

  defp direct_render_only_view_error?(%ArgumentError{} = exception, opts) do
    Map.get(opts, :direct_render_only) == true and
      String.contains?(
        Exception.message(exception),
        "direct_render_only requires"
      )
  end

  # Color watches share direct-scene rendering; aplite needs the streaming/boxed path.
  defp direct_render_only?(target_platforms) when is_list(target_platforms) do
    target_platforms != [] and not Enum.member?(target_platforms, "aplite")
  end

  # Aplite uses streamed direct-scene commands (`view_commands_append`); generic
  # `Main.view` / drawCell closures are dead weight once direct emit is available.
  defp prune_direct_generic?(target_platforms) when is_list(target_platforms) do
    Enum.member?(target_platforms, "aplite")
  end

  defp reset_generated_dir(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end

  defp pebble_config_dir(project_dir) do
    cond do
      File.regular?(Path.join(project_dir, "elm-pebble.project.json")) ->
        {:ok, project_dir}

      File.regular?(Path.join(Path.dirname(project_dir), "elm-pebble.project.json")) ->
        {:ok, Path.dirname(project_dir)}

      true ->
        :error
    end
  end

  defp read_project_json(config_dir) do
    config_dir
    |> Path.join("elm-pebble.project.json")
    |> File.read()
    |> case do
      {:ok, body} -> Jason.decode(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp codegen_profile_from_extra(extra) when is_map(extra) do
    resolve_codegen_profile(extra, nil)
  end

  defp resolve_codegen_profile(extra, project_dir) when is_map(extra) do
    cond do
      profile = Map.get(extra, :codegen_profile) ->
        normalize_codegen_profile(profile)

      Map.get(extra, :optimize_for_size) == false ->
        :balanced

      Map.get(extra, :optimize_for_size) == true ->
        :size

      is_binary(project_dir) and release_optimize_for_size_disabled?(project_dir) ->
        :balanced

      true ->
        @ide_default_codegen_profile
    end
  end

  defp normalize_codegen_profile(profile) when profile in [:default, :balanced, :size], do: profile
  defp normalize_codegen_profile("default"), do: :default
  defp normalize_codegen_profile("balanced"), do: :balanced
  defp normalize_codegen_profile("size"), do: :size
  defp normalize_codegen_profile(_), do: @ide_default_codegen_profile

  defp release_optimize_for_size_disabled?(project_dir) when is_binary(project_dir) do
    with {:ok, config_dir} <- pebble_config_dir(project_dir),
         {:ok, %{"release_defaults" => defaults}} when is_map(defaults) <-
           read_project_json(config_dir) do
      release_flag_false?(defaults, "optimize_for_size")
    else
      _ -> false
    end
  end

  defp release_flag_false?(defaults, key) when is_map(defaults) and is_binary(key) do
    Map.get(defaults, key) == false or Map.get(defaults, key) == "false"
  end
end
