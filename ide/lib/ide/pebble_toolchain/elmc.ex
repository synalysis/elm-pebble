defmodule Ide.PebbleToolchain.Elmc do
  @moduledoc false

  alias Elmc.Runtime.Generator, as: RuntimeGenerator
  alias Ide.PebbleToolchain.Types

  @type elmc_compile_opts :: Types.elmc_compile_opts()
  @type elmc_compile_result :: Types.elmc_compile_result()
  @type toolchain_error :: Types.toolchain_error()

  @spec watch_compile_opts(String.t(), [String.t()]) :: Types.watch_compile_opts()
  def watch_compile_opts(out_dir, target_platforms)
      when is_binary(out_dir) and is_list(target_platforms) do
    %{
      out_dir: out_dir,
      entry_module: "Main",
      direct_render_only: direct_render_only?(target_platforms),
      prune_direct_generic: prune_direct_generic?(target_platforms),
      prune_runtime: true,
      prune_native_wrappers: true,
      pebble_int32: true,
      strip_dead_code: true
    }
  end

  @spec target_platforms_for_project_dir(String.t()) :: [String.t()] | nil
  def target_platforms_for_project_dir(project_dir) when is_binary(project_dir) do
    with {:ok, config_dir} <- pebble_config_dir(project_dir),
         {:ok, %{"release_defaults" => defaults}} when is_map(defaults) <-
           read_project_json(config_dir),
         platforms when is_list(platforms) <- Map.get(defaults, "target_platforms"),
         normalized when normalized != [] <- normalize_target_platforms(platforms) do
      normalized
    else
      _ -> nil
    end
  end

  @spec compile_for_project_dir(String.t(), String.t()) :: Elmc.CLI.project_run()
  def compile_for_project_dir(project_dir, out_dir) when is_binary(project_dir) and is_binary(out_dir) do
    elmc_opts =
      case target_platforms_for_project_dir(project_dir) do
        nil -> %{out_dir: out_dir, strip_dead_code: true}
        target_platforms -> watch_compile_opts(out_dir, target_platforms)
      end

    Elmc.CLI.compile_project(project_dir, out_dir, elmc_opts: elmc_opts)
  end

  @spec generate_sources(String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, toolchain_error()}
  def generate_sources(project_root, app_root, _workspace_root, opts \\ []) do
    compile_out_dir = Path.join(project_root, ".elmc-build")
    stage_out_dir = Path.join(app_root, "src/c/elmc")
    target_platforms = Keyword.get(opts, :target_platforms, [])

    compile_opts = watch_compile_opts(compile_out_dir, target_platforms)

    with :ok <- reset_generated_dir(compile_out_dir),
         :ok <- reset_generated_dir(stage_out_dir),
         {:ok, _} <- Elmc.CLI.compile_with_opts(project_root, compile_opts),
         :ok <- File.mkdir_p(Path.dirname(stage_out_dir)),
         {:ok, _copied} <- File.cp_r(compile_out_dir, stage_out_dir) do
      :ok
    else
      {:error, reason} -> {:error, {:elmc_compile_failed, reason}}
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
    case Elmc.CLI.compile_with_opts(project_root, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:elmc_compile_failed, reason}}
    end
  end

  defp direct_render_only?(_target_platforms), do: true

  # Multi-platform PBWs include aplite (streaming view) and newer watches (direct scene).
  # Prune direct-scene generic bodies from the shared compile so aplite stays within flash.
  defp prune_direct_generic?(target_platforms) when is_list(target_platforms) do
    Enum.member?(target_platforms, "aplite") and length(target_platforms) > 1
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

  defp normalize_target_platforms(platforms) when is_list(platforms) do
    platforms
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
