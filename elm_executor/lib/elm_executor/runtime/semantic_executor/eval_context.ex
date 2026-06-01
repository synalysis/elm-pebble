defmodule ElmExecutor.Runtime.SemanticExecutor.EvalContext do
  @moduledoc false

  @contract_keys [:debugger_contract, "debugger_contract", :elm_introspect, "elm_introspect"]

  @spec contract(map()) :: map() | nil
  def contract(eval_context) when is_map(eval_context) do
    Enum.find_value(@contract_keys, fn key ->
      case Map.get(eval_context, key) do
        %{} = contract -> contract
        _ -> nil
      end
    end)
  end

  @spec put_contract(map(), map() | nil) :: map()
  def put_contract(eval_context, nil) when is_map(eval_context) do
    Map.drop(eval_context, @contract_keys)
  end

  def put_contract(eval_context, contract) when is_map(eval_context) and is_map(contract) do
    eval_context
    |> Map.put(:debugger_contract, contract)
    |> Map.put(:elm_introspect, contract)
  end
end
