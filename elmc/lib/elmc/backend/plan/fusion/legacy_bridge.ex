defmodule Elmc.Backend.Plan.Fusion.LegacyBridge do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.Plan.Fusion.Tuple2CaseTable
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec try_plan(String.t(), map(), map(), keyword()) :: {:ok, FunctionPlan.t()} | :error
  def try_plan(module_name, decl, decl_map, _opts) do
    name = Map.get(decl, :name, "")
    expr = Map.get(decl, :expr)

    case Fusion.try_emit(module_name, name, expr, decl_map) do
      {:ok, c_body, _callees, :rc_native} ->
        kinds = Fusion.infer_native_tag_fusion_arg_kinds(c_body, decl)

        if kinds do
          Fusion.register_rc_native_arg_kinds(module_name, name, kinds)
        end

        plan =
          Tuple2CaseTable.build_fusion_plan(module_name, name, decl, c_body)
          |> maybe_put_fusion_arg_kinds(kinds)

        {:ok, plan}

      {:ok, c_body, _callees} ->
        {:ok, Tuple2CaseTable.build_fusion_plan(module_name, name, decl, c_body)}

      _ ->
        :error
    end
  end

  defp maybe_put_fusion_arg_kinds(plan, kinds) when is_list(kinds),
    do: Map.put(plan, :fusion_arg_kinds, kinds)

  defp maybe_put_fusion_arg_kinds(plan, _), do: plan
end
