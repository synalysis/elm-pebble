defmodule Elmx.Runtime.Executor.Subscriptions do
  @moduledoc false

  alias Elmx.Runtime.Executor.Model
  alias Elmx.Runtime.Subscriptions.ActiveSet
  alias Elmx.Types

  @spec evaluate(module(), Types.runtime_model()) :: [Types.wire_cmd()]
  def evaluate(module, runtime_model) when is_atom(module) and is_map(runtime_model) do
    if function_exported?(module, :subscriptions, 1) do
      elm_model = Model.runtime_model_from_elm(runtime_model)

      module
      |> apply(:subscriptions, [elm_model])
      |> ActiveSet.from_value()
    else
      []
    end
  end

  def evaluate(_module, _runtime_model), do: []
end
