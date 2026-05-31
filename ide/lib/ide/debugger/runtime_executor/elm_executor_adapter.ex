defmodule Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter do
  @moduledoc """
  Adapter for elm_executor-backed runtime execution contract.

  Requires versioned Core IR on every request.
  """

  @behaviour Ide.Debugger.RuntimeExecutor

  alias ElmEx.CoreIR
  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Types

  @type execution_input :: Ide.Debugger.RuntimeExecutor.execution_input()
  @type execution_result :: Ide.Debugger.RuntimeExecutor.execution_result()

  @type executor_result :: {:ok, ExecutorTypes.executor_wire_result()} | {:error, Types.execution_error()}
  @type compiled_module_result :: {:ok, module()} | :none | {:error, Types.execution_error()}

  @impl true
  @spec execute(execution_input()) :: {:ok, execution_result()} | {:error, Types.execution_error()}
  def execute(input) when is_map(input) do
    with :ok <- require_core_ir(input),
         request <- Map.put(input, :debugger_contract, "elm_executor.runtime_executor.v1"),
         {:ok, payload} <- execute_via_compiled_module_or_runtime(request),
         :ok <- validate_runtime_model(payload) do
      {:ok, ResultNormalizer.normalize(payload)}
    else
      {:error, {:core_ir_execution_failed, _} = err} -> {:error, err}
      {:error, reason} -> {:error, {:core_ir_execution_failed, reason}}
    end
  end

  def execute(_), do: {:error, {:core_ir_execution_failed, :invalid_execution_input}}

  @spec require_core_ir(map()) :: :ok | {:error, Types.execution_error()}
  defp require_core_ir(input) do
    core_ir = Map.get(input, :elm_executor_core_ir) || Map.get(input, "elm_executor_core_ir")

    cond do
      match?(%CoreIR{version: "elm_ex.core_ir.v1"}, core_ir) ->
        :ok

      is_map(core_ir) and Map.get(core_ir, "version") == "elm_ex.core_ir.v1" ->
        :ok

      is_map(core_ir) and Map.get(core_ir, :version) == "elm_ex.core_ir.v1" ->
        :ok

      true ->
        {:error, {:core_ir_execution_failed, :missing_core_ir}}
    end
  end

  @spec validate_runtime_model(map()) :: :ok | {:error, Types.execution_error()}
  defp validate_runtime_model(payload) when is_map(payload) do
    patch = Map.get(payload, :model_patch) || Map.get(payload, "model_patch") || %{}

    if is_map(Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model)) do
      :ok
    else
      {:error, {:core_ir_execution_failed, :missing_runtime_model}}
    end
  end

  @spec execute_via_compiled_module_or_runtime(map()) :: executor_result()
  defp execute_via_compiled_module_or_runtime(request) do
    case compiled_runtime_module() do
      {:ok, module} -> module.debugger_execute(request)
      :none -> execute_runtime(request)
      {:error, reason} -> execute_runtime(request) |> or_passthrough_error(reason)
    end
  end

  defp or_passthrough_error({:error, _} = err, _reason), do: err
  defp or_passthrough_error(other, _reason), do: other

  @spec execute_runtime(map()) :: executor_result()
  defp execute_runtime(request) when is_map(request) do
    core_ir = Map.get(request, :elm_executor_core_ir) || Map.get(request, "elm_executor_core_ir")

    metadata =
      Map.get(request, :elm_executor_metadata) || Map.get(request, "elm_executor_metadata") || %{}

    ElmExecutor.Runtime.Executor.execute(request, core_ir, metadata)
  end

  @spec compiled_runtime_module() :: compiled_module_result()
  defp compiled_runtime_module do
    opts = Application.get_env(:ide, __MODULE__, [])
    out_dir = Keyword.get(opts, :compiled_out_dir)
    entry_module = Keyword.get(opts, :compiled_entry_module, "Main")

    cond do
      is_binary(out_dir) and out_dir != "" ->
        ElmExecutor.Runtime.Loader.load_from_dir(out_dir, entry_module)

      true ->
        :none
    end
  end
end
