defmodule Elmc.Backend.Plan.Fusion.Tuple2CaseTable do
  @moduledoc false

  alias Elmc.Backend.Plan.Fusion.Helper
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @doc false
  @spec build_fusion_plan(String.t(), String.t(), map(), String.t()) :: FunctionPlan.t()
  def build_fusion_plan(module_name, name, decl, c_body) do
    Helper.build_fusion_plan(module_name, name, decl, c_body)
  end
end
