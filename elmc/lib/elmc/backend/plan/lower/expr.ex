defmodule Elmc.Backend.Plan.Lower.Expr do
  @moduledoc """
  Lower Elm IR expressions to verified `%FunctionPlan{}` fragments.
  """

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.{Arith, Call, Case, Cmd, Compare, Constructor, If, IntCall, Lambda, List, Record, StdlibCall, Tuple, UnionCtor}
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types

  @literal_ops [:int_literal, :c_int_expr, :bool_literal, :string_literal, :cmd_none, :sub_none, :float_literal]

  @spec compile(map() | nil, Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out | :branch_out | nil, Builder.t()} | :unsupported
  def compile(nil, _ctx, b), do: {:ok, nil, b}

  def compile(%{op: op} = expr, ctx, b) when op in @literal_ops do
    compile_literal(expr, ctx, b)
  end

  def compile(%{op: :var, name: name}, ctx, b) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [base, field] when field != "" ->
        compile(%{op: :field_access, arg: base, field: field}, ctx, b)

      _ ->
        compile_root_var(name, ctx, b)
    end
  end

  defp compile_root_var(name, ctx, b) when is_binary(name) do
    case Context.local_reg(ctx, name) do
      reg when is_integer(reg) ->
        {:ok, reg, b}

      _ ->
        case param_index(ctx, name) do
          idx when is_integer(idx) ->
            Builder.get_or_load_param(b, idx, name) |> then(fn {reg, b1} -> {:ok, reg, b1} end)

          _ ->
            case Builder.emit_load_local(b, name) do
              {nil, _} ->
                case Call.compile_top_level_ref(name, ctx, b) do
                  {:ok, reg, b1} -> {:ok, reg, b1}
                  :unsupported -> :unsupported
                end

              {reg, b1} ->
                {:ok, reg, b1}
            end
        end
    end
  end

  def compile(%{op: :call} = expr, ctx, b) do
    case IntCall.compile(expr, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        case Lambda.compile_partial(expr, ctx, b) do
          {:ok, _, _} = ok ->
            ok

          :unsupported ->
            Call.compile_call(expr, ctx, b)
        end
    end
  end

  def compile(%{op: :qualified_call} = expr, ctx, b) do
    case expr do
      %{target: "Maybe.withDefault", args: args} ->
        StdlibCall.compile_maybe_with_default(args, ctx, b)

      %{target: target, args: [low, high, value]}
      when target in ["Basics.clamp", "clamp"] ->
        compile_ternary_runtime(target, low, high, value, :basics_clamp, ctx, b)

      %{target: target, args: [arg]} when target in ["String.fromInt", "String.toInt", "String.toFloat", "Basics.floor", "String.isEmpty"] ->
        compile_string_unary(target, arg, ctx, b)

      %{target: target, args: [left, right]} when target == "String.left" ->
        compile_string_binary(left, right, ctx, b)

      %{target: target, args: [left, right]} ->
        case IntCall.compile(%{op: :call, name: target, args: [left, right]}, ctx, b) do
          {:ok, _, _} = ok -> ok
          :unsupported -> Call.compile_call(expr, ctx, b)
        end

      _ ->
        Call.compile_call(expr, ctx, b)
    end
  end

  def compile(%{op: :runtime_call} = expr, ctx, b) do
    compile_runtime_call(expr, ctx, b)
  end

  def compile(%{op: :pipe_chain} = expr, ctx, b) do
    expr
    |> ElmEx.IR.PipeChain.desugar()
    |> compile(ctx, b)
  end

  def compile(%{op: :let_in} = expr, ctx, b) do
    compile_let(expr, ctx, b)
  end

  def compile(%{op: :lambda} = expr, ctx, b), do: Lambda.compile(expr, ctx, b)

  def compile(%{op: op} = expr, ctx, b)
      when op in [:tuple_first_expr, :tuple_second_expr, :tuple_first, :tuple_second],
      do: Tuple.compile(expr, ctx, b)

  def compile(%{op: :if} = expr, ctx, b), do: If.compile(expr, ctx, b)
  def compile(%{op: :case} = expr, ctx, b), do: Case.compile(expr, ctx, b)
  def compile(%{op: :pebble_cmd} = expr, ctx, b), do: Cmd.compile(expr, ctx, b)

  def compile(%{op: :render_cmd} = expr, ctx, b),
    do: Elmc.Backend.Plan.Lower.Platform.Pebble.compile_render_cmd(expr, ctx, b)

  def compile(%{op: :render_text_cmd} = expr, ctx, b),
    do: Elmc.Backend.Plan.Lower.Platform.Pebble.compile_render_text_cmd(expr, ctx, b)

  def compile(%{op: :pebble_sub} = expr, ctx, b),
    do: Elmc.Backend.Plan.Lower.Platform.Pebble.compile_sub(expr, ctx, b)
  def compile(%{op: :compare} = expr, ctx, b), do: Compare.compile(expr, ctx, b)
  def compile(%{op: :constructor_call} = expr, ctx, b),
    do: Constructor.compile(expr, ctx, b)

  def compile(%{op: :partial_constructor, target: target, tag: tag, args: []}, ctx, b)
      when is_binary(target) and is_integer(tag) do
    Builder.emit_const_int(b, tag, union_ctor: UnionCtor.qualify(target, ctx))
    |> then(fn {reg, b1} -> {:ok, reg, b1} end)
  end

  def compile(%{op: :partial_constructor, target: target, args: []}, ctx, b)
      when is_binary(target) do
    Constructor.compile(%{target: target, args: []}, ctx, b)
  end

  def compile(%{op: :msg_tag_expr, name: name}, _ctx, b) when is_binary(name) do
    macro = "ELMC_PEBBLE_MSG_#{Elmc.Backend.Pebble.Util.macro_name(name)}"
    {reg, b1} = Builder.emit_const_c_expr(b, macro)
    {:ok, reg, b1}
  end

  def compile(%{op: :record_update} = expr, ctx, b), do: Record.compile_update(expr, ctx, b)

  def compile(%{op: op} = expr, ctx, b) when op in [:add_const, :sub_const, :add_vars],
    do: Arith.compile(expr, ctx, b)

  def compile(%{op: :tuple2, left: left, right: right}, ctx, b) do
    case Constructor.compile_payload_tuple2(left, right, ctx, b) do
      {:ok, reg, b1} ->
        {:ok, reg, b1}

      :unsupported ->
        compile_tuple2_pair(left, right, ctx, b)
    end
  end

  def compile(%{op: :tuple2} = expr, ctx, b) do
    operand_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, [a, b_reg], b1} <- compile_args(Map.get(expr, :args, []), operand_ctx, b) do
      compile_runtime_builtin(:tuple2, [a, b_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :record_literal} = expr, ctx, b) do
    fields =
      expr
      |> Map.get(:fields, [])
      |> Record.canonicalize_literal_fields(ctx)

    with {:ok, field_regs, b1} <- compile_field_values(fields, ctx, b) do
      field_names = Enum.map(fields, fn f -> Map.get(f, :name) || Map.get(f, :field) end)
      extra = %{shape: Map.get(expr, :type), field_names: field_names}

      id =
        if int_record_literal_fields?(fields) or int_record_shape?(field_names) do
          :record_new_values_ints
        else
          :record_new
        end

      compile_runtime_builtin(id, field_regs, ctx, b1, extra)
    else
      _ -> :unsupported
    end
  end

  def compile(%{op: :list_literal, items: items}, ctx, b) do
    List.compile_literal(items, ctx, b)
  end

  def compile(%{op: :field_access, arg: %{op: :record_literal, fields: fields}, field: field}, ctx, b)
      when is_binary(field) do
    case Enum.find(fields, fn f -> Map.get(f, :name) == field end) do
      %{expr: expr} -> compile(expr, ctx, b)
      _ -> :unsupported
    end
  end

  def compile(%{op: :field_access, arg: arg, field: field}, ctx, b) when is_binary(field) do
    with {:ok, base, b1} <- resolve_field_base(arg, ctx, b) do
      compile_record_get(base, field, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile(_, _, _), do: :unsupported

  @spec compile_args([map()], Context.t(), Builder.t()) ::
          {:ok, [Types.reg()], Builder.t()} | :unsupported
  def compile_args(args, ctx, b) when is_list(args) do
    # Call operands must not target branch_out / fn_out — only the callee result may.
    operand_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(args, {:ok, [], b}, fn arg, {:ok, acc, b_acc} ->
      case compile(arg, operand_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp compile_literal(%{op: :int_literal, union_ctor: ctor} = expr, ctx, b) when is_binary(ctor) do
    Constructor.compile(
      %{target: UnionCtor.qualify(ctor, ctx), args: [], value: Map.get(expr, :value)},
      ctx,
      b
    )
  end

  defp compile_literal(%{op: :float_literal, value: value}, ctx, b) when is_number(value) do
    compile_runtime_builtin(:new_float, [], ctx, b, %{literal: value})
  end

  defp compile_literal(%{op: :int_literal, value: value}, ctx, b) do
    if ctx.rc_required and Context.function_tail?(ctx) do
      compile_runtime_builtin(:new_int, [], ctx, b, %{literal: value})
    else
      Builder.emit_const_int(b, value) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
  end

  defp compile_literal(%{op: :bool_literal, value: value}, ctx, b) do
    int_val = if value, do: 1, else: 0
    compile_runtime_builtin(:new_bool, [int_val], ctx, b, %{literal: int_val})
  end

  defp compile_literal(%{op: :sub_none}, ctx, b) do
    Elmc.Backend.Plan.Lower.Platform.Pebble.compile_sub(
      %{mask: %{op: :int_literal, value: 0}, params: []},
      ctx,
      b
    )
  end

  defp compile_literal(%{op: :cmd_none}, ctx, b) do
    kind =
      Elmc.Backend.CCodegen.SpecialValues.Helpers.command_kind_expr(:none)

    Cmd.compile(%{op: :pebble_cmd, kind: kind, params: []}, ctx, b)
  end

  defp compile_literal(%{op: :string_literal, value: value}, _ctx, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :const_immortal_string, %{
        dest: reg,
        args: %{value: value},
        effects: Types.owned_effects(reg)
      })

    {:ok, reg, b2}
  end

  defp compile_literal(%{op: :c_int_expr, value: value}, _ctx, b) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> Builder.emit_const_int(b, n) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
      _ -> Builder.emit_const_c_expr(b, value) |> then(fn {reg, b1} -> {:ok, reg, b1} end)
    end
  end

  defp compile_literal(_, _, _), do: :unsupported

  defp param_index(ctx, name) when is_binary(name) do
    ctx.params
    |> Enum.find_index(&(&1 == name))
  end

  defp resolve_field_base(arg, ctx, b) when is_binary(arg),
    do: compile(%{op: :var, name: arg}, ctx, b)

  defp resolve_field_base(arg, ctx, b) when is_map(arg), do: compile(arg, ctx, b)
  defp resolve_field_base(_, _, _), do: :unsupported

  defp compile_record_get(base, field, ctx, b) when is_integer(base) do
    {reg, b1} = Builder.fresh_reg(b)
    field_index = Record.field_index_for(field, ctx)
    int_field? = Record.int_field?(field)

    op = if int_field?, do: :record_get_int, else: :record_get

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: reg,
        args: %{base: base, field: field, field_index: field_index},
        effects: %{produces: {:owned, reg}, consumes: [], borrows: [base], fallible: false}
      })

    {:ok, reg, b2}
  end

  defp compile_let(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, ctx, b) do
    if letrec_lambda?(name, value_expr) do
      compile_letrec_lambda(name, value_expr, in_expr, ctx, b)
    else
      compile_let_simple(name, value_expr, in_expr, ctx, b)
    end
  end

  defp compile_let_simple(name, value_expr, in_expr, ctx, b) do
    value_expr = maybe_packed_text_options_expr(value_expr)
    value_ctx = Context.for_branch_arm(ctx)

    case compile(value_expr, value_ctx, b) do
      {:ok, reg, b1} when is_integer(reg) ->
        ctx1 = Context.put_local(ctx, name, reg)
        b2 = Builder.bind_local(b1, name, reg)
        compile(in_expr, ctx1, b2)

      _ ->
        :unsupported
    end
  end

  defp maybe_packed_text_options_expr(value_expr) do
    alias Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions

    if TextOptions.packable_value?(value_expr) do
      case TextOptions.packed_expr(value_expr) do
        {:ok, %{op: :direct_native_if} = packed} ->
          %{
            op: :if,
            cond: Map.fetch!(packed, :cond),
            then_expr: Map.fetch!(packed, :then_expr),
            else_expr: Map.fetch!(packed, :else_expr)
          }

        {:ok, packed} ->
          packed

        _ ->
          value_expr
      end
    else
      value_expr
    end
  end

  defp compile_letrec_lambda(name, %{op: :lambda} = value_expr, in_expr, ctx, b) do
    {ref, b1} = Builder.declare_letrec(b, name)

    ctx1 =
      ctx
      |> Context.put_letrec_ref(name, ref)
      |> Map.put(:letrec_self, name)

    with {:ok, closure_reg, b2} <- compile(value_expr, ctx1, b1),
         {_, b3} <-
           Builder.emit(b2, :forward_ref_set, %{
             dest: nil,
             args: %{ref: ref, value: closure_reg},
             effects: Types.empty_effects()
           }),
         ctx2 = Context.put_local(ctx1, name, closure_reg),
         b4 = Builder.bind_local(b3, name, closure_reg),
         {:ok, reg, b5} <- compile(in_expr, ctx2, b4) do
      {:ok, reg, b5}
    else
      _ -> :unsupported
    end
  end

  defp letrec_lambda?(name, %{op: :lambda, body: body}) when is_binary(name) do
    name in Elmc.Backend.CCodegen.VarAnalysis.used_vars(body)
  end

  defp letrec_lambda?(_, _), do: false

  defp compile_string_unary("String.fromInt", arg, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:string_from_int, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_string_unary("String.toInt", arg, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:string_to_int, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_string_unary("String.toFloat", arg, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:string_to_float, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_string_unary("Basics.floor", arg, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:basics_floor, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_string_unary("String.isEmpty", arg, ctx, b) do
    with {:ok, arg_reg, b1} <- compile(arg, ctx, b) do
      compile_runtime_builtin(:string_is_empty, [arg_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_string_binary(left, right, ctx, b) do
    with {:ok, [left_reg, right_reg], b1} <- compile_args([left, right], ctx, b) do
      compile_runtime_builtin(:string_left, [left_reg, right_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_ternary_runtime(_target, low, high, value, id, ctx, b) do
    with {:ok, [low_reg, high_reg, value_reg], b1} <- compile_args([low, high, value], ctx, b) do
      compile_runtime_builtin(id, [low_reg, high_reg, value_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_field_values(fields, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(fields, {:ok, [], b}, fn field, {:ok, acc, b_acc} ->
      expr = Map.get(field, :expr) || Map.get(field, :value)

      case compile(expr, operand_ctx, b_acc) do
        {:ok, reg, b1} -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp int_record_literal_fields?(fields) when is_list(fields) do
    fields != [] and Enum.all?(fields, &int_record_field_expr?/1)
  end

  defp int_record_shape?(field_names) when is_list(field_names) do
    field_names != [] and Enum.all?(field_names, &Record.int_field?/1)
  end

  defp int_record_field_expr?(field) do
    int_record_expr?(Map.get(field, :expr) || Map.get(field, :value))
  end

  defp int_record_expr?(%{op: :int_literal, value: value}) when is_integer(value), do: true

  defp int_record_expr?(%{op: :var, name: name}) when is_binary(name), do: true

  defp int_record_expr?(%{op: :qualified_call, target: target, args: args}) when is_list(args) do
    int_call_target?(target) and Enum.all?(args, &int_record_expr?/1)
  end

  defp int_record_expr?(%{op: :call, name: name, args: args}) when is_list(args) do
    name in ["max", "min", "modBy", "remainderBy", "__idiv__", "__mul__", "__add__", "__sub__"] and
      Enum.all?(args, &int_record_expr?/1)
  end

  defp int_record_expr?(%{op: op})
       when op in [
              :add_const,
              :sub_const,
              :add_vars,
              :sub_vars,
              :mul_vars,
              :idiv_vars,
              :min_vars,
              :max_vars,
              :mod_vars,
              :rem_vars,
              :record_get_int
            ],
       do: true

  defp int_record_expr?(%{op: :field_access, arg: arg, field: field})
       when is_binary(field) and is_map(arg),
       do: int_record_expr?(arg)

  defp int_record_expr?(_), do: false

  defp int_call_target?(target) when is_binary(target) do
    target in [
      "Basics.max",
      "Basics.min",
      "Basics.modBy",
      "Basics.remainderBy",
      "Basics.abs",
      "Basics.negate"
    ] or
      String.ends_with?(target, ".max") or
      String.ends_with?(target, ".min") or
      String.ends_with?(target, ".modBy")
  end

  defp compile_runtime_call(%{function: "elmc_list_repeat", args: args}, ctx, b) do
    case fold_list_repeat_literals(args, ctx, b) do
      {:ok, reg, b1} ->
        {:ok, reg, b1}

      :error ->
        compile_runtime_call_default(%{function: "elmc_list_repeat", args: args}, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListCursor.try_compile_map(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported ->
        case Elmc.Backend.Plan.Lower.ListRecord.try_compile_map(expr, ctx, b) do
          {:ok, reg, b1} -> {:ok, reg, b1}
          :unsupported -> compile_runtime_call_default(expr, ctx, b)
        end
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_filter_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.FilterMapIdentity.try_compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_filter"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListRecord.try_compile_filter(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(%{function: "elmc_list_find_first", args: [pred, list]}, ctx, b) do
    case Elmc.Backend.Plan.Lower.ListRecord.try_compile_filter(
           %{function: "elmc_list_filter", args: [pred, list]},
           ctx,
           b
         ) do
      {:ok, filtered_reg, b1} ->
        compile_runtime_builtin(:list_head, [filtered_reg], ctx, b1)

      :unsupported ->
        compile_runtime_call_default(
          %{function: "elmc_list_find_first", args: [pred, list]},
          ctx,
          b
        )
    end
  end

  defp compile_runtime_call(%{function: "elmc_maybe_map"} = expr, ctx, b) do
    case Elmc.Backend.Plan.Lower.MaybeMap.try_compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, b1}
      :unsupported -> compile_runtime_call_default(expr, ctx, b)
    end
  end

  defp compile_runtime_call(expr, ctx, b), do: compile_runtime_call_default(expr, ctx, b)

  defp compile_runtime_call_default(%{function: "elmc_list_find_first", args: args}, ctx, b) do
    with {:ok, [pred_reg, list_reg], b1} <- compile_call_args(args, ctx, b),
         {:ok, filtered_reg, b2} <-
           compile_runtime_builtin(:list_filter, [pred_reg, list_reg], ctx, b1),
         {:ok, head_reg, b3} <- compile_runtime_builtin(:list_head, [filtered_reg], ctx, b2) do
      {:ok, head_reg, b3}
    else
      _ -> :unsupported
    end
  end

  defp compile_runtime_call_default(%{args: args} = expr, ctx, b) do
    callee = Map.get(expr, :function) || Map.get(expr, :callee)

    with callee when is_binary(callee) <- callee,
         id when not is_nil(id) <- RuntimeBuiltins.from_c_symbol(callee),
         {:ok, arg_regs, b1} <- compile_call_args(args, ctx, b) do
      compile_runtime_builtin(id, arg_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_runtime_call_default(_, _, _), do: :unsupported

  defp compile_call_args(args, ctx, b) when is_list(args) do
    compile_args(args, ctx, b)
  end

  defp compile_call_args(_, _, _), do: {:ok, [], nil}

  defp fold_list_repeat_literals([%{op: :int_literal, value: count}, %{op: :int_literal, value: item}], ctx, b)
       when is_integer(count) and count >= 4 and is_integer(item) do
    values = for _ <- 1..count, do: item
    compile_const_static_list({:int_array, values}, ctx, b)
  end

  defp fold_list_repeat_literals(_, _, _), do: :error

  @doc false
  def compile_const_static_list(spec, ctx, b) do
    {dest, b1} = dest_for_builtin(ctx, b)
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1
    {args, effects} = static_list_instr(spec, dest)

    {_, b3} =
      Builder.emit(b2, :const_static_list, %{
        dest: dest,
        args: args,
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3
    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  defp static_list_instr({:int_array, values}, dest) do
    {%{kind: :int_array, values: values}, Types.fallible_effects(dest)}
  end

  defp static_list_instr({:float_array, values}, dest) do
    {%{kind: :float_array, values: values}, Types.fallible_effects(dest)}
  end

  defp static_list_instr({:tuple2_int_array, pairs}, dest) do
    {%{kind: :tuple2_int_array, pairs: pairs}, Types.fallible_effects(dest)}
  end

  defp static_list_instr({:values, regs}, dest) when is_list(regs) do
    {%{kind: :values, regs: regs}, Types.fallible_effects(dest, [], regs)}
  end

  defp static_list_instr({:record_array, regs}, dest) when is_list(regs) do
    {%{kind: :record_array, regs: regs}, Types.fallible_effects(dest, [], regs)}
  end

  @doc false
  def compile_runtime_builtin(id, arg_regs, ctx, b, extra \\ %{}) do
    if id in [:union_payload, :maybe_just_payload] do
      compile_borrow_view_builtin(id, arg_regs, ctx, b, extra)
    else
      compile_runtime_builtin_core(id, arg_regs, ctx, b, extra)
    end
  end

  defp compile_borrow_view_builtin(id, arg_regs, _ctx, b, extra) do
    {borrow_dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: borrow_dest,
        args: Map.merge(%{builtin: id, args: arg_regs}, extra),
        effects: %{
          produces: nil,
          consumes: [],
          borrows: arg_regs,
          fallible: false
        }
      })

    {owned, b3} = Builder.copy_reg_owned(b2, borrow_dest, consume_source: true)
    {:ok, owned, b3}
  end

  defp compile_runtime_builtin_core(id, arg_regs, ctx, b, extra) do
    {dest, b1} = dest_for_builtin(ctx, b)
    fallible? = RuntimeBuiltins.fallible?(id)
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, fallible?)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

    {arg_regs, b2a} =
      cond do
        id in [:record_new, :record_new_take, :record_new_values_ints] ->
          Builder.dup_named_locals_for_consume(b2, arg_regs)

        id in [:tuple2, :tuple2_take] ->
          Builder.dup_regs_for_owned_consume(b2, arg_regs)

        true ->
          {arg_regs, b2}
      end

    {borrows, consumes} =
      cond do
        id in [:record_new, :record_new_take, :record_new_values_ints] -> {[], arg_regs}
        id in [:cmd_batch, :sub_batch] -> {[], arg_regs}
        id == :debug_to_string -> {[], arg_regs}
        id == :tuple2_ints -> {arg_regs, []}
        id in [:result_and_then, :result_map, :result_map_error, :maybe_and_then] ->
          case arg_regs do
            args when length(args) >= 1 ->
              {prefix, [last]} = Enum.split(args, -1)
              {borrows, prefix_consumes} = Builder.partition_call_args(b2a, prefix)
              {borrows, prefix_consumes ++ [last]}

            _ ->
              Builder.partition_call_args(b2a, arg_regs)
          end

        true ->
          Builder.partition_call_args(b2a, arg_regs)
      end

    effects =
      if is_integer(dest) do
        if fallible? do
          Types.fallible_effects(dest, borrows, consumes)
        else
          %{produces: {:owned, dest}, consumes: consumes, borrows: borrows, fallible: false}
        end
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: fallible?}
      end

    {_, b3} =
      Builder.emit(b2a, :call_runtime, %{
        dest: dest,
        args: Map.merge(%{builtin: id, args: arg_regs}, extra),
        effects: effects
      })

    b4 =
      cond do
        wrap_catch? -> Builder.catch_end(b3)
        true -> b3
      end

    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  defp dest_for_builtin(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end

  defp compile_tuple2_pair(left, right, ctx, b) do
    operand_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    with {:ok, l, b1} <- compile(left, operand_ctx, b),
         {:ok, r, b2} <- compile(right, operand_ctx, b1) do
      if tuple2_ints_eligible?(left, right) do
        compile_runtime_builtin(:tuple2_ints, [l, r], ctx, b2)
      else
        compile_runtime_builtin(:tuple2, [l, r], ctx, b2)
      end
    else
      _ -> :unsupported
    end
  end

  defp tuple2_ints_eligible?(left, right) do
    native_int_operand_expr?(left) and native_int_operand_expr?(right)
  end

  defp native_int_operand_expr?(%{op: op}) when op in [:int_literal, :c_int_expr, :msg_tag_expr],
    do: true

  defp native_int_operand_expr?(%{op: :field_access}), do: true
  defp native_int_operand_expr?(%{op: :var}), do: true
  defp native_int_operand_expr?(%{op: op}) when op in [:add_const, :sub_const, :add_vars], do: true

  defp native_int_operand_expr?(%{op: :constructor_call, args: []}), do: true

  defp native_int_operand_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}),
    do: native_int_operand_expr?(then_expr) and native_int_operand_expr?(else_expr)

  defp native_int_operand_expr?(_), do: false
end
