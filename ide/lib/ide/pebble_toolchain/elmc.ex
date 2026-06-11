defmodule Ide.PebbleToolchain.Elmc do
  @moduledoc false

  alias Elmc.Runtime.Generator, as: RuntimeGenerator
  alias Ide.PebbleToolchain.Types

  @type elmc_compile_opts :: Types.elmc_compile_opts()
  @type elmc_compile_result :: Types.elmc_compile_result()
  @type toolchain_error :: Types.toolchain_error()

  @spec generate_sources(String.t(), String.t(), String.t()) ::
          :ok | {:error, toolchain_error()}
  def generate_sources(project_root, app_root, _workspace_root) do
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
         {:ok, _} <- compile_project(project_root, opts),
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

  @spec compile_project(String.t(), elmc_compile_opts()) ::
          {:ok, elmc_compile_result()} | {:error, toolchain_error()}
  defp compile_project(project_root, opts) do
    with {:ok, result} <- Elmc.compile(project_root, opts),
         :ok <- Elmc.CLI.validate_compile_result(result) do
      {:ok, result}
    else
      {:error, warnings} when is_list(warnings) ->
        {:error, {:elmc_compile_failed, %{kind: :compile_diagnostics, warnings: warnings}}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception in ArgumentError ->
      if direct_render_only_view_error?(exception, opts) do
        compile_project_with_generic_renderer(project_root, opts)
      else
        {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
      end

    exception ->
      {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:compiler_exception, kind, reason}}
  end

  @spec compile_project_with_generic_renderer(String.t(), elmc_compile_opts()) ::
          {:ok, elmc_compile_result()} | {:error, toolchain_error()}
  defp compile_project_with_generic_renderer(project_root, opts) do
    fallback_opts = Map.put(opts, :direct_render_only, false)

    with :ok <- reset_generated_dir(opts[:out_dir]),
         {:ok, result} <- Elmc.compile(project_root, fallback_opts),
         :ok <- Elmc.CLI.validate_compile_result(result) do
      {:ok, result}
    else
      {:error, warnings} when is_list(warnings) ->
        {:error, {:elmc_compile_failed, %{kind: :compile_diagnostics, warnings: warnings}}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception ->
      {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:compiler_exception, kind, reason}}
  end

  @spec direct_render_only_view_error?(%ArgumentError{}, elmc_compile_opts()) :: boolean()
  defp direct_render_only_view_error?(%ArgumentError{} = exception, opts) do
    opts[:direct_render_only] == true and
      String.contains?(
        Exception.message(exception),
        "direct_render_only requires"
      )
  end

  defp reset_generated_dir(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end
end
