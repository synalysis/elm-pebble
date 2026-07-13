defmodule Elmc.Backend.Plan.Fusion.CEmit do
  @moduledoc false

  alias Elmc.Backend.Plan.Fusion.Registry
  alias Elmc.Backend.Plan.Fusion.Helper
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Backend.CCodegen.Tuple2CaseTable

  @type emit_provider :: {module(), 3 | 4}

  @spec providers() :: [emit_provider()]
  def providers, do: Registry.providers()

  @spec try_plan(String.t(), Types.function_decl(), Types.function_decl_map(), keyword(), emit_provider()) ::
          {:ok, FunctionPlan.t()} | :error
  def try_plan(module_name, decl, decl_map, _opts, {emit_mod, emit_arity}) do
    name = Map.get(decl, :name, "")
    expr = fusion_expr(Map.get(decl, :expr))

    case apply(emit_mod, :try_emit, emit_args(emit_arity, module_name, name, expr, decl_map)) do
      {:ok, c_body, _callees, :rc_native} ->
        kinds = Registry.infer_native_tag_fusion_arg_kinds(c_body, decl)

        kinds =
          case kinds do
            kinds when is_list(kinds) ->
              kinds
              |> Enum.with_index()
              |> Enum.map(fn {kind, idx} ->
                if kind == :native_int and boxed_direct_plan_param?(decl, idx) do
                  :boxed_int_tag
                else
                  kind
                end
              end)

            other ->
              other
          end

        if kinds do
          Registry.register_rc_native_arg_kinds(module_name, name, kinds)
        end

        plan =
          module_name
          |> Helper.build_fusion_plan(name, decl, c_body)
          |> Helper.maybe_put_fusion_arg_kinds(kinds)
          |> attach_fusion_bytecode(emit_mod, module_name, name, expr, decl_map)

        {:ok, plan}

      {:ok, c_body, _callees} ->
        plan =
          module_name
          |> Helper.build_fusion_plan(name, decl, c_body)
          |> attach_fusion_bytecode(emit_mod, module_name, name, expr, decl_map)

        {:ok, plan}

      _ ->
        :error
    end
  end

  defp emit_args(3, module_name, name, expr, _decl_map), do: [module_name, name, expr]
  defp emit_args(4, module_name, name, expr, decl_map), do: [module_name, name, expr, decl_map]

  defp fusion_expr(%{op: :pipe_chain} = expr), do: ElmEx.IR.PipeChain.desugar(expr)
  defp fusion_expr(expr), do: expr

  defp boxed_direct_plan_param?(decl, index) do
    case Enum.at(Map.get(decl, :args, []), index) do
      arg when is_binary(arg) ->
        case Map.get(decl, :type) do
          type when is_binary(type) ->
            type
            |> Elmc.Backend.CCodegen.Host.function_arg_types()
            |> Enum.at(index)
            |> then(fn
              nil -> true
              arg_type -> Elmc.Backend.CCodegen.Host.normalize_type_name(arg_type) not in ["Int", "Bool"]
            end)

          _ ->
            true
        end

      _ ->
        false
    end
  end

  defp attach_fusion_bytecode(plan, emit_mod, module_name, name, expr, decl_map) do
    cond do
      emit_mod == Tuple2CaseTable ->
        case Tuple2CaseTable.extract_table(expr) do
          {:ok, data} -> %{plan | fusion_kind: :tuple2_case_table, fusion_data: data}
          :error -> plan
        end

      function_exported?(emit_mod, :extract_fusion_data, 4) ->
        case apply(emit_mod, :extract_fusion_data, [module_name, name, expr, decl_map]) do
          {:ok, kind, data} -> %{plan | fusion_kind: kind, fusion_data: data}
          :error -> plan
        end

      true ->
        plan
    end
  end
end
