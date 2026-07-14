defmodule Elmc.Backend.Wasm.Lower do
  @moduledoc """
  Plan → WASM lowering (web Elm / headless elm/core).
  """

  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Backend.Wasm.Module

  @type module_map :: Module.t()

  @spec lower(FunctionPlan.t()) :: {:ok, module_map()} | {:error, term()}
  def lower(%FunctionPlan{} = plan) do
    {:ok, Module.build([plan])}
  end

  @spec lower_many([FunctionPlan.t()]) :: {:ok, module_map()}
  def lower_many(plans) when is_list(plans) do
    {:ok, Module.build(plans)}
  end

  @spec render_wat(module_map()) :: binary()
  def render_wat(module_map), do: Module.render_wat(module_map)
end
