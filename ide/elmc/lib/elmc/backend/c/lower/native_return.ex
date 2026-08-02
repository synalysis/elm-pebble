defmodule Elmc.Backend.C.Lower.NativeReturn do
  @moduledoc false
  alias Elmc.Types, as: Types

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type scalar_kind :: :native_int | :native_bool | :native_int_pair | :native_list_int_pair

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

  # Wasm lower passes a lightweight `%{type: "Int" | "Bool"}` probe; C lower
  # passes a full IR declaration. Both only need `:type` for scalar_return_kind/1.
  @type annotate_decl ::
          Types.function_decl()
          | %{optional(:type) => String.t() | nil, optional(atom()) => term()}

  @spec annotate(FunctionPlan.t(), annotate_decl()) :: FunctionPlan.t()
  def annotate(%FunctionPlan{} = plan, decl) do
    case scalar_return_kind(decl) do
      nil ->
        plan

      kind ->
        decl_map = Process.get(:elmc_program_decls, %{})

        # NativeReturn must not advertise `elmc_int_t *out` when the public emit
        # path still uses boxed `ElmcValue **out` (e.g. Color→Int case helpers).
        # Otherwise call sites write `&plan_native_int_N` into a boxed-out callee.
        if NativeFunctionCall.return_kind(decl, plan.module, decl_map) != kind do
          uncache_kind(plan.module, plan.name)
          uncache_value_return(plan.module, plan.name)
          plan
        else
          # Bootstrap the cache before analyzing recursive call_fn sites in the same function.
          _ = cache_kind(plan, plan.module, plan.name, kind)

          case annotate_kind(plan, kind) do
            {:ok, plan} ->
              plan = maybe_mark_value_return(plan)

              if Map.get(plan, :native_scalar_value_return) do
                cache_value_return(plan.module, plan.name)
              else
                uncache_value_return(plan.module, plan.name)
              end

              plan

            :error ->
              uncache_kind(plan.module, plan.name)
              uncache_value_return(plan.module, plan.name)
              plan
          end
        end
    end
  end

  defp annotate_kind(plan, :native_int_pair) do
    case pair_ret_operands(plan) do
      {a, b} when is_integer(a) and is_integer(b) ->
        if native_int_value_reg?(plan, a) and native_int_value_reg?(plan, b) do
          {:ok,
           plan
           |> Map.put(:native_scalar_return, :native_int_pair)
           |> Map.put(:native_pair_ret, {a, b})}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp annotate_kind(plan, :native_list_int_pair) do
    case list_int_pair_return_shape(plan) do
      {:ok, arms, pair_regs} when arms != [] ->
        if Enum.all?(arms, fn {list, int} ->
             list_int_pair_list_operand?(plan, list) and list_int_pair_int_operand?(plan, int)
           end) do
          {:ok,
           plan
           |> Map.put(:native_scalar_return, :native_list_int_pair)
           |> Map.put(:native_list_int_pair_arms, arms)
           |> Map.put(:native_list_int_pair_pair_regs, pair_regs)}
        else
          :error
        end

      # Tail call / return of another dual-out `(List Int, Int)` callee: emit
      # `out_list`/`out_int` and let the call write them directly (no heap pack).
      :passthrough ->
        {:ok,
         plan
         |> Map.put(:native_scalar_return, :native_list_int_pair)
         |> Map.put(:native_list_int_pair_arms, [])
         |> Map.put(:native_list_int_pair_pair_regs, MapSet.new())}

      _ ->
        :error
    end
  end

  defp annotate_kind(plan, kind) when kind in [:native_int, :native_bool] do
    ret_reg = ret_source_reg(plan)

    if is_integer(ret_reg) and native_return_reg?(plan, ret_reg, kind) do
      {:ok, Map.put(plan, :native_scalar_return, kind)}
    else
      :error
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
  def c_out_type(:native_int_pair), do: "elmc_int_t *out0, elmc_int_t *out1"
  def c_out_type(:native_list_int_pair), do: "ElmcValue **out_list, elmc_int_t *out_int"

  @spec c_value_type(scalar_kind()) :: String.t()
  def c_value_type(:native_int), do: "elmc_int_t"
  def c_value_type(:native_bool), do: "bool"
  def c_value_type(:native_int_pair), do: "elmc_int_t"
  def c_value_type(:native_list_int_pair), do: "ElmcValue *"

  @spec ret_reg_allows_native?(FunctionPlan.t(), non_neg_integer(), scalar_kind()) :: boolean()
  def ret_reg_allows_native?(%FunctionPlan{} = plan, reg, kind)
      when is_integer(reg) and kind in [:native_int, :native_bool] do
    native_return_reg?(plan, reg, kind)
  end

  def ret_reg_allows_native?(_, _, _), do: false

  @spec pair_ret_operands(FunctionPlan.t()) ::
          {non_neg_integer(), non_neg_integer()} | nil
  def pair_ret_operands(%FunctionPlan{} = plan) do
    case Map.get(plan, :native_pair_ret) do
      {a, b} when is_integer(a) and is_integer(b) ->
        {a, b}

      _ ->
        find_pair_ret_operands(plan)
    end
  end

  defp find_pair_ret_operands(%FunctionPlan{blocks: blocks} = plan) do
    instrs = Enum.flat_map(blocks, & &1.instrs)

    # Prefer an explicit publish source, else a direct `:fn_out` tuple2(_ints).
    case ret_source_reg(plan) do
      reg when is_integer(reg) ->
        pair_operands_from_instrs(instrs, reg) || pair_operands_fn_out(instrs)

      _ ->
        pair_operands_fn_out(instrs)
    end
  end

  defp pair_operands_fn_out(instrs) do
    Enum.find_value(instrs, fn
      %{op: :call_runtime, dest: dest, args: %{builtin: builtin, args: [a, b]}}
      when dest in [:fn_out, :branch_out] and builtin in [:tuple2_ints, :tuple2] and
             is_integer(a) and is_integer(b) ->
        {a, b}

      _ ->
        nil
    end)
  end

  defp pair_operands_from_instrs(instrs, reg) do
    Enum.find_value(instrs, fn
      %{op: :call_runtime, dest: ^reg, args: %{builtin: builtin, args: [a, b]}}
      when builtin in [:tuple2_ints, :tuple2] and is_integer(a) and is_integer(b) ->
        {a, b}

      _ ->
        nil
    end)
  end

  defp maybe_mark_value_return(%FunctionPlan{} = plan) do
    # Keep the struct key present — Map.delete would drop it and later
    # `%{plan | native_scalar_value_return: …}` updates KeyError (wasm lambda annotate).
    Map.put(plan, :native_scalar_value_return, native_scalar_value_return?(plan))
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
  def cache_scalar_return(module, name, kind)
      when kind in [:native_int, :native_bool, :native_int_pair, :native_list_int_pair] do
    cache_kind(nil, module, name, kind)
    :ok
  end

  @doc """
  Drop a cached scalar-return kind when the emitted public ABI uses
  `ElmcValue **out` instead of `elmc_int_t *out` / `bool *out`.
  """
  @spec uncache_scalar_return(String.t(), String.t()) :: :ok
  def uncache_scalar_return(module, name)
      when is_binary(module) and is_binary(name) do
    uncache_kind(module, name)
    uncache_value_return(module, name)
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
      "Int" ->
        :native_int

      "Bool" ->
        :native_bool

      ret ->
        cond do
          NativeInt.int_tuple2_type?(ret) -> :native_int_pair
          NativeInt.list_int_tuple2_type?(ret) -> :native_list_int_pair
          true -> nil
        end
    end
  end

  defp scalar_return_kind(_), do: nil

  @spec list_int_pair_return_shape(FunctionPlan.t()) ::
          {:ok, [{non_neg_integer(), non_neg_integer()}], MapSet.t(non_neg_integer())}
          | :passthrough
          | :error
  defp list_int_pair_return_shape(%FunctionPlan{blocks: blocks} = plan) do
    instrs = Enum.flat_map(blocks, & &1.instrs)

    case ret_source_reg(plan) do
      reg when is_integer(reg) ->
        case list_int_pair_arms_from_reg(plan, instrs, reg) do
          {:ok, _, _} = ok -> ok
          :error -> list_int_pair_passthrough_from_reg(plan, reg)
        end

      _ ->
        case pair_operands_fn_out(instrs) do
          {a, b} -> {:ok, [{a, b}], MapSet.new()}
          _ -> list_int_pair_fn_out_passthrough(instrs)
        end
    end
  end

  defp list_int_pair_arms_from_reg(plan, instrs, reg) do
    case CLowerFunction.all_defining_instrs(plan, reg) do
      [%{op: :call_runtime, args: %{builtin: builtin, args: [a, b]}} | _]
      when builtin in [:tuple2, :tuple2_ints, :tuple2_take] and is_integer(a) and is_integer(b) ->
        {:ok, [{a, b}], MapSet.new([reg])}

      [%{op: :phi, args: %{then: then_r, else: else_r}} | _] ->
        with {:ok, then_arms, then_regs} <- list_int_pair_arms_from_reg(plan, instrs, then_r),
             {:ok, else_arms, else_regs} <- list_int_pair_arms_from_reg(plan, instrs, else_r) do
          {:ok, then_arms ++ else_arms,
           then_regs |> MapSet.union(else_regs) |> MapSet.put(reg)}
        else
          _ -> :error
        end

      _ ->
        case pair_operands_from_instrs(instrs, reg) do
          {a, b} -> {:ok, [{a, b}], MapSet.new([reg])}
          _ -> :error
        end
    end
  end

  defp list_int_pair_passthrough_from_reg(plan, reg) when is_integer(reg) do
    case CLowerFunction.all_defining_instrs(plan, reg) do
      [%{op: :call_fn, args: %{module: mod, name: name}} | _] ->
        if cached_kind({mod, name}) == :native_list_int_pair, do: :passthrough, else: :error

      _ ->
        :error
    end
  end

  defp list_int_pair_fn_out_passthrough(instrs) when is_list(instrs) do
    Enum.find_value(instrs, fn
      %{op: :call_fn, dest: dest, args: %{module: mod, name: name}}
      when dest in [:fn_out, :branch_out] ->
        if cached_kind({mod, name}) == :native_list_int_pair, do: :passthrough, else: nil

      _ ->
        nil
    end)
    |> case do
      :passthrough -> :passthrough
      _ -> :error
    end
  end

  defp list_int_pair_list_operand?(plan, reg) when is_integer(reg) do
    # List component is a boxed ElmcValue* (not a native int chain).
    not native_int_value_reg?(plan, reg) and CLowerFunction.all_defining_instrs(plan, reg) != []
  end

  defp list_int_pair_list_operand?(_, _), do: false

  defp list_int_pair_int_operand?(plan, reg) when is_integer(reg) do
    native_int_value_reg?(plan, reg) or peelable_boxed_int_reg?(plan, reg, MapSet.new())
  end

  defp list_int_pair_int_operand?(_, _), do: false

  defp peelable_boxed_int_reg?(plan, reg, visited) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      false
    else
      visited = MapSet.put(visited, reg)

      case CLowerFunction.all_defining_instrs(plan, reg) do
        [%{op: :call_runtime, args: %{builtin: :new_int}} | _] ->
          true

        [%{op: :call_runtime, args: %{builtin: :retain, args: [src]}} | _] when is_integer(src) ->
          native_int_value_reg?(plan, src) or peelable_boxed_int_reg?(plan, src, visited)

        [%{op: :transfer, args: %{source: src}} | _] when is_integer(src) ->
          native_int_value_reg?(plan, src) or peelable_boxed_int_reg?(plan, src, visited)

        [%{op: :load_param, args: %{index: idx}} | _] when is_integer(idx) ->
          native_int_param?(plan, idx)

        _ ->
          false
      end
    end
  end

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

        [%{op: :load_param, args: %{index: idx}} | _] when is_integer(idx) ->
          native_int_param?(plan, idx)

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

  defp native_int_param?(%FunctionPlan{module: module, name: name}, idx) when is_integer(idx) do
    decl_map = Process.get(:elmc_program_decls, %{})

    case Map.get(decl_map, {module, name}) do
      %{type: type} when is_binary(type) ->
        # Signature Int is enough for dual-out pair operands: C lower peels boxed
        # Int params via `elmc_int_value` / native-int slots. Body-safe arg_kinds
        # may still be `:boxed` when the param also escapes into a heap pair.
        case Enum.at(Host.function_arg_types(type), idx) |> Host.signature_param_kind() do
          :native_int -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp native_bool_value_reg?(plan, reg) do
    case CLowerFunction.all_defining_instrs(plan, reg) do
      [%{op: op} | _]
      when op in [
             :compare,
             :bool_and,
             :test_maybe_nothing,
             :test_list_empty,
             :test_list_length_gte,
             :test_ctor_tag,
             :test_bool
           ] ->
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
