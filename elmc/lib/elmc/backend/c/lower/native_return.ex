defmodule Elmc.Backend.C.Lower.NativeReturn do
  @moduledoc false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type scalar_kind :: :native_int | :native_bool

  @value_return_forbidden_ops MapSet.new([
                                :call_runtime,
                                :call_closure,
                                :make_closure,
                                :retain,
                                :release,
                                :transfer,
                                :record_get,
                                :record_update,
                                :const_static_list,
                                :const_immortal_string,
                                :render_cmd,
                                :render_text_cmd,
                                :pebble_cmd,
                                :pebble_sub,
                                :switch_ctor_tag,
                                :union_tag,
                                :load_local,
                                :boxed_binop,
                                :string_concat,
                                :forward_ref_set,
                                :catch_begin,
                                :catch_end
                              ])

  @spec annotate(FunctionPlan.t(), map()) :: FunctionPlan.t()
  def annotate(%FunctionPlan{} = plan, decl) do
    case scalar_return_kind(decl) do
      nil ->
        plan

      kind ->
        # Bootstrap the cache before analyzing recursive call_fn sites in the same function.
        _ = cache_kind(plan, plan.module, plan.name, kind)
        ret_reg = ret_source_reg(plan)

        if is_integer(ret_reg) and native_return_reg?(plan, ret_reg, kind) do
          plan =
            plan
            |> Map.put(:native_scalar_return, kind)
            |> maybe_mark_value_return()

          if Map.get(plan, :native_scalar_value_return) do
            cache_value_return(plan.module, plan.name)
          else
            uncache_value_return(plan.module, plan.name)
          end

          plan
        else
          uncache_kind(plan.module, plan.name)
          uncache_value_return(plan.module, plan.name)
          plan
        end
    end
  end

  @spec cached_kind({String.t(), String.t()}) :: scalar_kind | nil
  def cached_kind({module, name}) do
    Process.get(:elmc_plan_native_returns, %{})
    |> Map.get({module, name})
  end

  @spec value_return?({String.t(), String.t()}) :: boolean()
  def value_return?({module, name}) do
    MapSet.member?(Process.get(:elmc_plan_native_value_returns, MapSet.new()), {module, name})
  end

  @spec c_out_type(scalar_kind()) :: String.t()
  def c_out_type(:native_int), do: "elmc_int_t *out"
  def c_out_type(:native_bool), do: "bool *out"

  @spec c_value_type(scalar_kind()) :: String.t()
  def c_value_type(:native_int), do: "elmc_int_t"
  def c_value_type(:native_bool), do: "bool"

  @spec ret_reg_allows_native?(FunctionPlan.t(), non_neg_integer(), scalar_kind()) :: boolean()
  def ret_reg_allows_native?(%FunctionPlan{} = plan, reg, kind) when is_integer(reg) do
    native_return_reg?(plan, reg, kind)
  end

  def ret_reg_allows_native?(_, _, _), do: false

  defp maybe_mark_value_return(%FunctionPlan{} = plan) do
    if native_scalar_value_return?(plan) do
      Map.put(plan, :native_scalar_value_return, true)
    else
      Map.delete(plan, :native_scalar_value_return)
    end
  end

  @spec native_scalar_value_return?(FunctionPlan.t()) :: boolean()
  def native_scalar_value_return?(%FunctionPlan{native_scalar_return: kind} = plan)
      when kind in [:native_int, :native_bool] do
    CLowerFunction.plan_emit_owned_slot_count(plan) == 0 and plan_instrs_value_pure?(plan)
  end

  def native_scalar_value_return?(_), do: false

  defp plan_instrs_value_pure?(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.all?(&value_pure_instr?/1)
  end

  defp value_pure_instr?(%{op: :call_fn, args: %{module: mod, name: name}}) do
    value_return?({mod, name})
  end

  defp value_pure_instr?(%{op: op}) do
    not MapSet.member?(@value_return_forbidden_ops, op)
  end

  @spec cache_scalar_return(String.t(), String.t(), scalar_kind()) :: :ok
  def cache_scalar_return(module, name, kind) when kind in [:native_int, :native_bool] do
    cache_kind(nil, module, name, kind)
    :ok
  end

  @spec cache_scalar_value_return(String.t(), String.t()) :: :ok
  def cache_scalar_value_return(module, name) do
    cache_value_return(module, name)
    :ok
  end

  defp uncache_kind(module, name) do
    cache = Process.get(:elmc_plan_native_returns, %{})
    Process.put(:elmc_plan_native_returns, Map.delete(cache, {module, name}))
    :ok
  end

  defp cache_kind(_plan, module, name, kind) do
    cache = Process.get(:elmc_plan_native_returns, %{})
    Process.put(:elmc_plan_native_returns, Map.put(cache, {module, name}, kind))
    kind
  end

  defp cache_value_return(module, name) do
    set = Process.get(:elmc_plan_native_value_returns, MapSet.new())
    Process.put(:elmc_plan_native_value_returns, MapSet.put(set, {module, name}))
    :ok
  end

  defp uncache_value_return(module, name) do
    set = Process.get(:elmc_plan_native_value_returns, MapSet.new())
    Process.put(:elmc_plan_native_value_returns, MapSet.delete(set, {module, name}))
    :ok
  end

  defp scalar_return_kind(%{type: type}) when is_binary(type) do
    case Host.function_return_type(type) do
      "Int" -> :native_int
      "Bool" -> :native_bool
      _ -> nil
    end
  end

  defp scalar_return_kind(_), do: nil

  defp ret_source_reg(%FunctionPlan{blocks: blocks}) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        publish_source_reg(blocks)

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        reg

      _ ->
        nil
    end
  end

  defp publish_source_reg(blocks) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.find_value(fn
      %{op: :publish, dest: :fn_out, args: %{source: reg}} when is_integer(reg) -> reg
      _ -> nil
    end)
  end

  defp native_return_reg?(plan, reg, :native_int) do
    native_int_value_reg?(plan, reg) and native_int_return_uses_only?(plan, reg)
  end

  defp native_return_reg?(plan, reg, :native_bool) do
    native_bool_value_reg?(plan, reg) and native_bool_return_uses_only?(plan, reg)
  end

  defp native_int_value_reg?(plan, reg), do: native_int_value_reg?(plan, reg, MapSet.new())

  defp native_int_value_reg?(plan, reg, visited) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      false
    else
      visited = MapSet.put(visited, reg)

      case CLowerFunction.all_defining_instrs(plan, reg) do
        [%{op: :phi, args: %{native_int_phi: true}} | _] ->
          true

        [%{op: op} | _] when op in [:const_int, :const_c_expr, :record_get_int, :int_arith] ->
          true

        [%{op: :call_fn, args: %{module: mod, name: name}} | _] ->
          value_return?({mod, name}) or cached_kind({mod, name}) == :native_int

        [%{op: :phi, args: %{then: then_r, else: else_r}}] ->
          native_int_value_reg?(plan, then_r, visited) and native_int_value_reg?(plan, else_r, visited)

        _ ->
          false
      end
    end
  end

  defp native_int_value_reg?(_, _, _), do: false

  defp native_bool_value_reg?(plan, reg) do
    case CLowerFunction.all_defining_instrs(plan, reg) do
      [%{op: op} | _]
      when op in [:compare, :bool_and, :test_maybe_nothing, :test_list_empty, :test_ctor_tag, :test_bool] ->
        true

      [%{op: :phi, args: %{truthy_native: true}}] ->
        true

      [%{op: :phi, args: %{then: then_r, else: else_r}}] ->
        native_bool_value_reg?(plan, then_r) and native_bool_value_reg?(plan, else_r)

      _ ->
        false
    end
  end

  defp native_int_return_uses_only?(plan, reg) do
    plan
    |> CLowerFunction.plan_use_refs(reg, Process.get(:elmc_program_decls, %{}), MapSet.new())
    |> Enum.map(fn {kind, _} -> kind end)
    |> Enum.uniq()
    |> Enum.all?(&(&1 in [:native_int_call, :native_operand, :publish_fn_out]))
  end

  defp native_bool_return_uses_only?(plan, reg) do
    plan
    |> CLowerFunction.plan_use_refs(reg, Process.get(:elmc_program_decls, %{}), MapSet.new())
    |> Enum.map(fn {kind, _} -> kind end)
    |> Enum.uniq()
    |> Enum.all?(&(&1 in [:native_operand, :publish_fn_out]))
  end
end
