defmodule Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter do
  @moduledoc """
  Adapter for elm_executor-backed runtime execution contract.
  """

  @behaviour Ide.Debugger.RuntimeExecutor

  @type execution_input :: Ide.Debugger.RuntimeExecutor.execution_input()
  @type execution_result :: Ide.Debugger.RuntimeExecutor.execution_result()

  @impl true
  @spec execute(execution_input()) :: {:ok, execution_result()} | {:error, term()}
  def execute(input) when is_map(input) do
    request = Map.put(input, :debugger_contract, "elm_executor.runtime_executor.v1")

    case execute_via_compiled_module_or_runtime(request) do
      {:ok, payload} when is_map(payload) ->
        {:ok,
         %{
           model_patch: map_field(payload, :model_patch),
           view_tree: map_or_nil_field(payload, :view_tree),
           view_output: list_field(payload, :view_output),
           runtime: map_field(payload, :runtime),
           protocol_events: list_field(payload, :protocol_events),
           followup_messages: list_field(payload, :followup_messages)
         }}

      {:error, _} = err ->
        err

      other ->
        {:error, {:invalid_elm_executor_result, other}}
    end
  end

  def execute(_), do: {:error, :invalid_execution_input}

  @spec execute_via_compiled_module_or_runtime(term()) :: term()
  defp execute_via_compiled_module_or_runtime(request) do
    case compiled_runtime_module() do
      {:ok, module} -> module.debugger_execute(request)
      :none -> execute_runtime_with_optional_core_ir(request)
      {:error, _} -> execute_runtime_with_optional_core_ir(request)
    end
  end

  @spec execute_runtime_with_optional_core_ir(term()) :: term()
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

  @spec compiled_runtime_module() :: term()
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

  @spec map_field(term(), term()) :: term()
  defp map_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: %{}
  end

  @spec map_or_nil_field(term(), term()) :: term()
  defp map_or_nil_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: nil
  end

  @spec list_field(term(), term()) :: term()
  defp list_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_list(value), do: value, else: []
  end
end
