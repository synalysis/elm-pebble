defmodule Elmc.Backend.Plan.Fusion.ListMapStaticIndexAt do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ListMapStaticIndexAt
  alias Elmc.Backend.Plan.Fusion.Tuple2CaseTable

  @spec try_plan(String.t(), map(), map(), keyword()) :: {:ok, Elmc.Backend.Plan.Types.FunctionPlan.t()} | :error
  def try_plan(module_name, decl, decl_map, _opts) do
    name = Map.get(decl, :name, "")

    case ListMapStaticIndexAt.try_emit(module_name, name, Map.get(decl, :expr), decl_map) do
      {:ok, c_body, _callees, :rc_native} ->
        {:ok, Tuple2CaseTable.build_fusion_plan(module_name, name, decl, c_body)}

      {:ok, c_body, _callees} ->
        {:ok, Tuple2CaseTable.build_fusion_plan(module_name, name, decl, c_body)}

      _ ->
        :error
    end
  end
end
