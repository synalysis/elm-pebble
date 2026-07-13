defmodule Elmc.Backend.Plan.Fusion.Helper do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec build_fusion_plan(String.t(), String.t(), Types.function_decl(), String.t()) :: FunctionPlan.t()
  def build_fusion_plan(module_name, name, decl, c_body) when is_binary(c_body) do
    %FunctionPlan{
      module: module_name,
      name: name,
      params:
        Enum.with_index(Map.get(decl, :args, []), fn arg, idx ->
          %Elmc.Backend.Plan.Types.Param{name: arg, type: nil, index: idx}
        end),
      return_type: Map.get(decl, :type),
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: String.trim(c_body)
    }
  end

  @spec maybe_put_fusion_arg_kinds(FunctionPlan.t(), [atom()] | nil) :: FunctionPlan.t()
  def maybe_put_fusion_arg_kinds(plan, kinds) when is_list(kinds),
    do: Map.put(plan, :fusion_arg_kinds, kinds)

  def maybe_put_fusion_arg_kinds(plan, _), do: plan

  @spec attach_bytecode_fusion(FunctionPlan.t(), atom(), Types.fusion_data()) :: FunctionPlan.t()
  def attach_bytecode_fusion(plan, kind, data \\ %{}) when is_atom(kind) and is_map(data) do
    %{plan | fusion_kind: kind, fusion_data: data}
  end
end
