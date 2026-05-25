defmodule Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter do
  @moduledoc """
  Adapter for elm_executor-backed runtime execution contract.
  """

  @behaviour Ide.Debugger.RuntimeExecutor

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
    request = Map.put(input, :debugger_contract, "elm_executor.runtime_executor.v1")

    case execute_via_compiled_module_or_runtime(request) do
      {:ok, payload} when is_map(payload) ->
        {:ok, ResultNormalizer.normalize(payload)}

      {:error, _} = err ->
        err

      other ->
        {:error, {:invalid_elm_executor_result, other}}
    end
  end

  def execute(_), do: {:error, :invalid_execution_input}

  @spec execute_via_compiled_module_or_runtime(map()) :: executor_result() | map()
  defp execute_via_compiled_module_or_runtime(request) do
    case compiled_runtime_module() do
      {:ok, module} -> module.debugger_execute(request)
      :none -> execute_runtime_with_optional_core_ir(request)
      {:error, _} -> execute_runtime_with_optional_core_ir(request)
    end
  end

  @spec execute_runtime_with_optional_core_ir(map()) :: executor_result() | map()
  defp execute_runtime_with_optional_core_ir(request) when is_map(request) do
    core_ir = Map.get(request, :elm_executor_core_ir) || Map.get(request, "elm_executor_core_ir")

    metadata =
      Map.get(request, :elm_executor_metadata) || Map.get(request, "elm_executor_metadata") || %{}

    if is_map(core_ir) and is_map(metadata) do
      ElmExecutor.Runtime.Executor.execute(request, core_ir, metadata)
    else
      ElmExecutor.Runtime.Executor.execute(request)
    end
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
