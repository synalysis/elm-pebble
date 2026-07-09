defmodule Elmc.Backend.Plan.Fusion.Tuple2CaseTable do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec try_plan(String.t(), map(), map(), keyword()) :: {:ok, FunctionPlan.t()} | :error
  def try_plan(module_name, decl, _decl_map, _opts) do
    name = Map.get(decl, :name, "")

    case Tuple2CaseTable.try_emit(module_name, name, Map.get(decl, :expr)) do
      {:ok, c_body, _callees, :rc_native} ->
        {:ok, fusion_plan(module_name, name, decl, c_body)}

      {:ok, c_body, _callees} ->
        {:ok, fusion_plan(module_name, name, decl, c_body)}

      _ ->
        :error
    end
  end

  defp fusion_plan(module_name, name, decl, c_body) do
    build_fusion_plan(module_name, name, decl, c_body)
  end

  @doc false
  def build_fusion_plan(module_name, name, decl, c_body) do
  %FunctionPlan{
      module: module_name,
      name: name,
      params: Enum.with_index(Map.get(decl, :args, []), fn arg, idx ->
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
end
