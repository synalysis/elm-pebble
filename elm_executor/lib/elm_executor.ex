defmodule ElmExecutor do
  @moduledoc """
  Public API for the Elm semantic executor.
  """

  alias ElmExecutor.Backend.ElixirCodegen
  alias ElmEx.CoreIR
  alias ElmEx.DiagnosticFormatter
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.DeadCode
  alias ElmEx.IR.Lowerer

  @type compile_options :: %{
          optional(:entry_module) => String.t(),
          optional(:out_dir) => String.t(),
          optional(:strip_dead_code) => boolean(),
          optional(:strict_core_ir) => boolean(),
          optional(:mode) => :library | :ide_runtime
        }

  @spec check(String.t()) :: {:ok, map()} | {:error, map()}
  def check(project_dir) when is_binary(project_dir) do
    Bridge.load_project(project_dir)
  end

  @spec compile(String.t(), compile_options()) :: {:ok, map()} | {:error, map()}
  def compile(project_dir, opts \\ %{}) when is_binary(project_dir) and is_map(opts) do
    entry_module = opts[:entry_module] || "Main"
    out_dir = opts[:out_dir] || "build_executor"
    mode = opts[:mode] || :library
    strict_core_ir = Map.get(opts, :strict_core_ir, true)

    with {:ok, project} <- Bridge.load_project(project_dir),
         {:ok, ir0} <- Lowerer.lower_project(project),
         ir <- maybe_strip_dead_code(ir0, entry_module, opts[:strip_dead_code]),
         {:ok, core_ir} <- CoreIR.from_ir(ir, strict?: strict_core_ir),
         :ok <- ElixirCodegen.write_project(core_ir, out_dir, entry_module: entry_module, mode: mode) do
      {:ok,
       %{
         project: project,
         ir: ir,
         core_ir: core_ir,
         compiler: "elm_executor",
         out_dir: out_dir,
         mode: mode,
         entry_module: entry_module
       }}
    else
      {:error, %{diagnostics: diagnostics} = error} when is_list(diagnostics) ->
        {:error, Map.put(error, :diagnostics_rendered, DiagnosticFormatter.format_warnings(diagnostics))}

      {:error, _} = err ->
        err
    end
  end

  @spec maybe_strip_dead_code(term(), term(), term()) :: term()
  defp maybe_strip_dead_code(ir, _entry_module, false), do: ir
  defp maybe_strip_dead_code(ir, entry_module, _), do: DeadCode.strip(ir, entry_module)
end
