defmodule Elmc.Backend.Wasm.Lower.Instr do
  @moduledoc false

  import Bitwise

  alias Elmc.Backend.Bytecode.FnTable
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Backend.Wasm.ClosureRegistry
  alias Elmc.Backend.Wasm.Lower.Frame
  alias Elmc.Backend.Wasm.RuntimeImports
  alias Elmc.Backend.Wasm.Slots
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @rc_success 0

  @type emit_opts :: [
          rc_required: boolean(),
          fn_table: FnTable.t(),
          catch_id: non_neg_integer(),
          slots: Slots.t()
        ]

  @spec emit(Types.t(), Slots.t(), emit_opts()) :: [binary()]
  def emit(%Types{} = instr, slots, opts) do
    emit_impl(instr, slots, opts) |> normalize_lines()
  end

  defp emit_impl(%Types{} = instr, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    fn_table = Keyword.fetch!(opts, :fn_table)

    case instr.op do
      op when op in [:catch_begin, :catch_end, :release] ->
        []

      :publish ->
        emit_publish(instr, slots, opts)

      :load_param ->
        emit_load_param(instr, slots)

      :load_local ->
        emit_load_local(instr, slots, opts)

      :const_int ->
        emit_const_int(instr, slots)

      :const_immortal_string ->
        emit_const_string(instr, slots, rc?)

      :const_static_list ->
        emit_const_static_list(instr, slots, rc?)

      :const_c_expr ->
        emit_const_c_expr(instr, slots)

      :int_arith ->
        emit_int_arith(instr, slots)

      :compare ->
        emit_compare(instr, slots)

      :boxed_binop ->
        emit_boxed_binop(instr, slots, rc?, opts)

      :call_runtime ->
        emit_call_runtime(instr, slots, rc?, opts)

      :call_fn ->
        emit_call_fn(instr, slots, fn_table, rc?, opts)

      :call_closure ->
        emit_call_closure(instr, slots, rc?, opts)

      :make_closure ->
        emit_make_closure(instr, slots, rc?, opts)

      :record_get ->
        emit_record_get(instr, slots, rc?)

      :record_get_int ->
        emit_record_get(instr, slots, rc?)

      :record_update ->
        emit_record_update(instr, slots, rc?)

      :tuple_proj ->
        emit_tuple_proj(instr, slots, rc?)

      :phi ->
        emit_phi(instr, slots)

      :switch_ctor_tag ->
        emit_switch_ctor_tag(instr, slots)

      :test_maybe_nothing ->
        emit_test_maybe_nothing(instr, slots, rc?)

      :test_list_empty ->
        emit_test_list_empty(instr, slots, rc?)

      :test_ctor_tag ->
        emit_test_ctor_tag(instr, slots, rc?)

      :test_bool ->
        emit_test_bool(instr, slots)

      :test_string_literal ->
        emit_test_string_literal(instr, slots, rc?)

      :bool_and ->
        emit_bool_and(instr, slots)

      :boxed_tag_peel ->
        emit_boxed_tag_peel(instr, slots, rc?)

      :forward_ref_set ->
        emit_forward_ref_set(instr, slots, rc?)

      :forward_ref_load ->
        emit_forward_ref_load(instr, slots, rc?)

      :forward_ref_capture ->
        emit_forward_ref_capture(instr, slots, rc?)

      :forward_ref_load_captured ->
        emit_forward_ref_load_captured(instr, slots, rc?)

      :pebble_cmd ->
        emit_unsupported_platform(instr, slots)

      :render_cmd ->
        emit_unsupported_platform(instr, slots)

      :render_text_cmd ->
        emit_unsupported_platform(instr, slots)

      :pebble_sub ->
        emit_unsupported_platform(instr, slots)

      :list_cursor_map ->
        emit_list_cursor_map(instr, slots, rc?)

      :html_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :browser_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :json_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :bytes_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :dom_sub ->
        emit_web_platform_op(instr, slots, rc?)

      op ->
        emit_comment("unlowered plan op #{op}", instr, slots)
    end
  end

  defp normalize_lines(lines) when is_list(lines),
    do: Enum.flat_map(lines, &normalize_lines/1)

  defp normalize_lines(bin) when is_binary(bin), do: [bin]

  @spec emit_terminator(Types.Block.terminator(), Slots.t(), emit_opts()) :: [binary()]
  def emit_terminator(terminator, slots, opts) do
    emit_terminator_impl(terminator, slots, opts) |> normalize_lines()
  end

  defp emit_terminator_impl(terminator, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)

    case terminator do
      {:br, target_id} ->
        br(target_id, opts)

      {:br_if, then_id, else_id, cond_reg} ->
        cond = Slots.reg_name(slots, cond_reg)

        [
          WasmTypes.line(
            WasmTypes.sexpr("if", [
              " ",
              bool_cond_wat(cond),
              " (then ",
              br(then_id),
              ") (else ",
              br(else_id),
              ")"
            ])
          )
        ]

      {:switch_tag, subject, arms, default_id} ->
        emit_switch_tag(subject, arms, default_id, slots, rc?)

      {:ret, reg} ->
        emit_ret(reg, slots, rc?)

      :none ->
        []

      _ ->
        emit_ret(0, slots, rc?)
    end
  end

  defp emit_publish(%{args: %{source: reg}}, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    emit_runtime_call(:new_int, [int_operand_wat(reg, slots)], :fn_out, slots, rc?, opts)
  end

  defp emit_publish(%{dest: :fn_out}, _slots, _opts), do: []

  defp emit_load_param(%{dest: dest_reg, args: %{index: index}}, slots) do
    param = WasmTypes.ident("param#{index}")
    set_reg(dest_reg, WasmTypes.sexpr("local.get", [param]), slots)
  end

  defp emit_load_local(%{dest: dest_reg, args: %{source: source}}, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)

    if dest_reg in [:fn_out, :branch_out] and rc? do
      emit_runtime_call(:new_int, [int_operand_wat(source, slots)], dest_reg, slots, rc?, opts)
    else
      src = Slots.reg_name(slots, source)
      set_reg(dest_reg, WasmTypes.sexpr("local.get", [src]), slots)
    end
  end

  defp emit_const_int(%{dest: dest_reg, args: %{value: value}}, slots) do
    set_reg(dest_reg, int_const(value), slots)
  end

  defp emit_const_c_expr(%{dest: dest_reg, args: %{value: value}}, slots) do
    case resolve_c_expr_int(value) do
      {:ok, n} -> emit_const_int(%{dest: dest_reg, args: %{value: n}}, slots)
      :error -> emit_comment("const_c_expr #{inspect(value)}", %{dest: dest_reg}, slots)
    end
  end

  defp emit_const_string(%{dest: dest_reg, args: %{value: value}}, slots, rc?) do
    emit_runtime_call(:new_immortal_string, [literal_string_arg(value)], dest_reg, slots, rc?)
  end

  defp emit_const_static_list(%{dest: dest_reg, args: args}, slots, rc?) do
    case Map.get(args, :kind) do
      :int_array ->
        values = Map.get(args, :values, [])

        store_lines =
          values
          |> Enum.with_index()
          |> Enum.map(fn {value, index} ->
            WasmTypes.line(
              WasmTypes.sexpr("i32.store", [
                " offset=#{Slots.int_array_scratch_offset() + index * 4}",
                " ",
                WasmTypes.sexpr("i32.const", [0]),
                " ",
                int_const(value)
              ])
            )
          end)

        call_lines =
          emit_runtime_call(
            :list_from_int_array,
            [int_const(Slots.int_array_scratch_offset()), int_const(length(values))],
            dest_reg,
            slots,
            rc?
          )

        store_lines ++ call_lines

      kind when kind in [:values, :record_array] ->
        regs = Map.fetch!(args, :regs)
        emit_const_static_list_from_regs(regs, dest_reg, slots, rc?)

      _ ->
        emit_runtime_call(:list_nil, [], dest_reg, slots, rc?)
    end
  end

  defp emit_const_static_list_from_regs(regs, dest_reg, slots, rc?) when is_list(regs) do
    count = length(regs)
    scratch = Slots.int_array_scratch_offset()

    store_lines =
      regs
      |> Enum.with_index()
      |> Enum.flat_map(fn {reg, idx} ->
        prior = Enum.take(regs, idx)
        offset = scratch + idx * 4

        if reg in prior do
          temp_offset = scratch + count * 4 + idx * 4
          reg_expr = WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])

          [
            WasmTypes.line(
              WasmTypes.sexpr("call", [
                WasmTypes.import_ident("runtime.retain"),
                " ",
                int_const(temp_offset),
                " ",
                reg_expr
              ])
            ),
            WasmTypes.line(
              WasmTypes.sexpr("i32.store", [
                " offset=#{offset}",
                " ",
                WasmTypes.sexpr("i32.const", [0]),
                " ",
                WasmTypes.i32_load_offset(temp_offset)
              ])
            )
          ]
        else
          [
            WasmTypes.line(
              WasmTypes.sexpr("i32.store", [
                " offset=#{offset}",
                " ",
                WasmTypes.sexpr("i32.const", [0]),
                " ",
                WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])
              ])
            )
          ]
        end
      end)

    call_lines =
      emit_runtime_call(
        :list_from_values,
        [int_const(scratch), int_const(count)],
        dest_reg,
        slots,
        rc?
      )

    store_lines ++ call_lines
  end

  defp emit_int_arith(%{dest: dest_reg, args: args}, slots) do
    kind = Map.fetch!(args, :kind)
    lhs = Map.fetch!(args, :lhs)

    expr =
      case kind do
        :add_const ->
          binop("i32.add", int_operand_wat(lhs, slots), int_const(Map.fetch!(args, :value)))

        :sub_const ->
          binop("i32.sub", int_operand_wat(lhs, slots), int_const(Map.fetch!(args, :value)))

        :add_vars ->
          binop("i32.add", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :sub_vars ->
          binop("i32.sub", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :mul_vars ->
          binop("i32.mul", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :idiv_vars ->
          binop("i32.div_s", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :mod_vars ->
          binop("i32.rem_s", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :rem_vars ->
          binop("i32.rem_s", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :min_vars ->
          binop("i32.min_s", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        :max_vars ->
          binop("i32.max_s", int_operand_wat(lhs, slots), int_operand_wat(Map.fetch!(args, :rhs), slots))

        _ ->
          int_const(0)
      end

    set_reg(dest_reg, expr, slots)
  end

  defp int_operand_wat(reg, slots) do
    WasmTypes.sexpr("call", [
      WasmTypes.import_ident("runtime.as_int"),
      " ",
      WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])
    ])
  end

  defp emit_compare(%{dest: dest_reg, args: args}, slots) do
    left = Slots.reg_name(slots, Map.fetch!(args, :left))
    right = Slots.reg_name(slots, Map.fetch!(args, :right))
    kind = Map.fetch!(args, :kind)
    mode = Map.get(args, :mode, :pointer)

    case {mode, kind} do
      {:string, :eq} ->
        emit_runtime_call(
          :string_equals,
          [left, right],
          dest_reg,
          slots,
          false
        )

      {:string, :neq} ->
        emit_runtime_call(
          :string_equals,
          [left, right],
          dest_reg,
          slots,
          false
        ) ++
          emit_runtime_call(
            :basics_not,
            [Slots.reg_name(slots, dest_reg)],
            dest_reg,
            slots,
            false
          )

      _ ->
        pred =
          case kind do
            :eq -> "i32.eq"
            :neq -> "i32.ne"
            :gt -> "i32.gt_s"
            :gte -> "i32.ge_s"
            :lt -> "i32.lt_s"
            :lte -> "i32.le_s"
            _ -> "i32.eq"
          end

        [set_reg(dest_reg, binop(pred, left, right), slots)]
    end
  end

  defp emit_boxed_binop(%{dest: dest_reg, args: %{op: op, lhs: lhs, rhs: rhs}}, slots, rc?, opts) do
    cond do
      op == :fdiv ->
        emit_fdiv_binop(lhs, rhs, dest_reg, slots, rc?, opts)

      native_int_binop_operands?(lhs, rhs, opts) ->
        [emit_native_int_binop(op, lhs, rhs, dest_reg, slots)]

      true ->
        emit_comment("boxed_binop dynamic #{op}", %{dest: dest_reg}, slots)
    end
  end

  defp emit_fdiv_binop(lhs, rhs, dest_reg, slots, rc?, opts) do
    {left, prep_left} = boxed_runtime_arg_wat(lhs, slots, opts)
    {right, prep_right} = boxed_runtime_arg_wat(rhs, slots, opts)

    bits_lhs = call_import("runtime.as_float", [left])
    bits_rhs = call_import("runtime.as_float", [right])
    bits = call_import("runtime.float_div_bits", [bits_lhs, bits_rhs])

    prep_left ++ prep_right ++ emit_runtime_call(:new_float, [bits], dest_reg, slots, rc?, opts)
  end

  defp emit_native_int_binop(op, lhs, rhs, dest_reg, slots) do
    left = int_operand_wat(lhs, slots)
    right = int_operand_wat(rhs, slots)

    expr =
      case op do
        :add -> binop("i32.add", left, right)
        :sub -> binop("i32.sub", left, right)
        :mul -> binop("i32.mul", left, right)
        :idiv -> binop("i32.div_s", left, right)
        _ -> int_const(0)
      end

    set_reg(dest_reg, expr, slots)
  end

  defp native_int_binop_operands?(lhs, rhs, opts) when is_integer(lhs) and is_integer(rhs) do
    native_int_reg?(opts, lhs) and native_int_reg?(opts, rhs)
  end

  defp native_int_binop_operands?(_, _, _), do: false

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :new_float, literal: value}}, slots, rc?, opts)
       when is_number(value) do
    emit_runtime_call(:new_float, [float32_bits_const(value)], dest_reg, slots, rc?, opts)
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :list_from_values, args: args}}, slots, rc?, _opts) do
    emit_const_static_list_from_regs(args || [], dest_reg, slots, rc?)
  end

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :retain, view_peel: :maybe_just_payload, view_peel_args: peel_args}},
         slots,
         rc?,
         opts
       ) do
    {reg_exprs, prep} = build_runtime_call_args(:maybe_just_payload, peel_args || [], slots, opts)
    prep ++ emit_runtime_call(:maybe_just_payload, reg_exprs, dest_reg, slots, rc?, opts)
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: id, args: args} = args_map}, slots, rc?, opts) do
    {reg_exprs, prep} = build_runtime_call_args(id, args || [], slots, opts)
    literal = Map.get(args_map, :literal)
    c_expr = Map.get(args_map, :c_expr)

    extra =
      cond do
        id == :new_float and is_number(literal) -> [float32_bits_const(literal)]
        literal != nil and is_integer(literal) -> [int_const(literal)]
        c_expr != nil -> [int_const(resolve_c_expr_int(c_expr) |> elem_or(0))]
        true -> []
      end

    prep ++ emit_runtime_call(id, reg_exprs ++ extra, dest_reg, slots, rc?, opts)
  end

  defp emit_call_fn(%{dest: dest_reg, args: %{module: mod, name: name, args: args}}, slots, fn_table, rc?, _opts) do
    _idx = FnTable.index(fn_table, {mod, name})
    track_wasm_callee!(mod, name, args || [])
    callee = WasmTypes.fn_ident(mod, name)
    arg_regs = Enum.map(args || [], &Slots.reg_name(slots, &1))

    call =
      WasmTypes.sexpr("call", [
        callee | Enum.map(arg_regs, fn reg -> " " <> WasmTypes.sexpr("local.get", [reg]) end)
      ])

    {pop_value, pop_rc} =
      if dest_reg in [:fn_out, :branch_out] do
        {slots.fn_out_local, slots.rc_local}
      else
        {dest_slot(dest_reg, slots), slots.rc_local}
      end

    call_lines = [
      WasmTypes.line(call),
      WasmTypes.line(WasmTypes.sexpr("local.set", [pop_value])),
      WasmTypes.line(WasmTypes.sexpr("local.set", [pop_rc]))
    ]

    lines =
      if rc? do
        call_lines ++ check_rc_local(slots)
      else
        call_lines
      end

    if dest_reg in [:fn_out, :branch_out] do
      lines
    else
      dest = dest_slot(dest_reg, slots)

      case Slots.sync_owned_slot(slots, dest_reg, dest) do
        [] -> lines
        sync_lines -> lines ++ sync_lines
      end
    end
  end

  defp check_rc_local(slots) do
    [
      WasmTypes.line(
        WasmTypes.sexpr("br_if", [
          " ",
          Frame.catch_begin_label(0),
          " ",
          WasmTypes.sexpr("i32.ne", [
            " ",
            WasmTypes.sexpr("local.get", [slots.rc_local]),
            " ",
            WasmTypes.sexpr("i32.const", [@rc_success])
          ])
        ])
      )
    ]
  end

  defp emit_call_closure(%{dest: dest_reg, args: %{callee: callee, args: args}}, slots, rc?, _opts) do
    call_args = args || []

    emit_runtime_call(
      :call_closure,
      [int_const(length(call_args)), Slots.reg_name(slots, callee) | Enum.map(call_args, &Slots.reg_name(slots, &1))],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_make_closure(%{dest: dest_reg, args: %{index: idx, arity: arity, captures: caps}}, slots, rc?, opts) do
    caps = List.wrap(caps)
    parent = Keyword.fetch!(opts, :parent_plan)
    registry = Process.get(:elmc_wasm_closure_registry)
    global_idx = ClosureRegistry.global_index(registry, parent, idx)

    {capture_exprs, prep} =
      Enum.map_reduce(caps, [], fn reg, acc_prep ->
        {expr, prep_add} = boxed_runtime_arg_wat(reg, slots, opts)
        {expr, acc_prep ++ prep_add}
      end)

    prep ++
      emit_runtime_call(
        :make_closure,
        [int_const(global_idx), int_const(arity) | capture_exprs],
        dest_reg,
        slots,
        rc?,
        opts
      )
  end

  defp emit_record_get(%{dest: dest_reg, args: args}, slots, rc?) do
    emit_runtime_call(
      :record_get,
      [Slots.reg_name(slots, Map.fetch!(args, :base)), int_const(field_index(args))],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_record_update(%{dest: dest_reg, args: args}, slots, rc?) do
    emit_runtime_call(
      :record_update,
      [
        Slots.reg_name(slots, Map.fetch!(args, :base)),
        Slots.reg_name(slots, Map.fetch!(args, :value)),
        int_const(field_index(args))
      ],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_tuple_proj(%{dest: dest_reg, args: %{base: base, which: which}}, slots, rc?) do
    idx = if which == :second, do: 1, else: 0

    emit_runtime_call(
      :tuple_proj,
      [Slots.reg_name(slots, base), int_const(idx)],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_phi(%{dest: dest_reg, args: args}, slots) do
    cond_reg = Map.get(args, :cond)
    dest = Slots.reg_name(slots, dest_reg)

    cond_wat =
      case cond_reg do
        cond when is_integer(cond) or cond in [:fn_out, :branch_out] ->
          bool_cond_wat(Slots.reg_name(slots, cond))

        _ ->
          WasmTypes.sexpr("i32.const", [0])
      end

    {then_expr, else_expr} = phi_arm_exprs(args, slots)

    WasmTypes.line(
      WasmTypes.sexpr("if", [
        " ",
        cond_wat,
        " (then ",
        WasmTypes.sexpr("local.set", [dest, " ", then_expr]),
        ") (else ",
        WasmTypes.sexpr("local.set", [dest, " ", else_expr]),
        ")"
      ])
    )
  end

  defp phi_arm_exprs(%{native_int_phi: true} = args, _slots) do
    {
      phi_shape_wat(Map.get(args, :then_shape)),
      phi_shape_wat(Map.get(args, :else_shape))
    }
  end

  defp phi_arm_exprs(args, slots) do
    then_reg = Map.get(args, :then, 0)
    else_reg = Map.get(args, :else, 0)

    then_expr =
      if is_integer(then_reg) do
        WasmTypes.sexpr("local.get", [Slots.reg_name(slots, then_reg)])
      else
        WasmTypes.sexpr("i32.const", [0])
      end

    else_expr =
      if is_integer(else_reg) do
        WasmTypes.sexpr("local.get", [Slots.reg_name(slots, else_reg)])
      else
        WasmTypes.sexpr("i32.const", [0])
      end

    {then_expr, else_expr}
  end

  defp phi_shape_wat({:const_int, value}), do: int_const(value)
  defp phi_shape_wat({:new_int, value}) when is_integer(value), do: int_const(value)
  defp phi_shape_wat(_), do: WasmTypes.sexpr("i32.const", [0])

  defp emit_switch_ctor_tag(%{dest: dest_reg, args: args}, slots) do
    subject = Slots.reg_name(slots, Map.fetch!(args, :subject))
    default = Map.get(args, :default)
    dest = dest_slot(dest_reg, slots)

    default_expr =
      if is_integer(default) do
        Slots.reg_name(slots, default)
      else
        int_const(0)
      end

    WasmTypes.line(
      WasmTypes.sexpr("local.set", [
        dest,
        " ",
        WasmTypes.sexpr("call", [
          WasmTypes.import_ident("runtime.switch_ctor_tag"),
          " ",
          WasmTypes.sexpr("local.get", [subject]),
          " ",
          default_expr
        ])
      ])
    )
  end

  defp emit_test_maybe_nothing(%{dest: dest_reg, args: %{reg: reg}}, slots, rc?) do
    emit_runtime_call(:maybe_is_nothing, [Slots.reg_name(slots, reg)], dest_reg, slots, rc?)
  end

  defp emit_test_list_empty(%{dest: dest_reg, args: %{reg: reg}}, slots, rc?) do
    emit_runtime_call(:list_is_empty, [Slots.reg_name(slots, reg)], dest_reg, slots, rc?)
  end

  defp emit_test_ctor_tag(%{dest: dest_reg, args: %{subject: subject, tag: tag}}, slots, rc?) do
    emit_runtime_call(
      :union_tag_matches,
      [Slots.reg_name(slots, subject), int_const(tag)],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_test_bool(%{dest: dest_reg, args: %{subject: subject, want_true: want_true}}, slots) do
    flag = if want_true, do: 1, else: 0

    set_reg(
      dest_reg,
      binop("i32.eq", bool_cond_wat(Slots.reg_name(slots, subject)), int_const(flag)),
      slots
    )
  end

  defp emit_test_string_literal(%{dest: dest_reg, args: %{subject: subject, literal: literal}}, slots, rc?) do
    emit_runtime_call(
      :string_equals_literal,
      [Slots.reg_name(slots, subject), literal_string_arg(literal)],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_bool_and(%{dest: dest_reg, args: %{left: left, right: right}}, slots) do
    set_reg(
      dest_reg,
      binop(
        "i32.and",
        bool_cond_wat(Slots.reg_name(slots, left)),
        bool_cond_wat(Slots.reg_name(slots, right))
      ),
      slots
    )
  end

  defp emit_boxed_tag_peel(%{dest: dest_reg, args: %{reg: reg}}, slots, rc?) do
    emit_runtime_call(:boxed_tag_peel, [Slots.reg_name(slots, reg)], dest_reg, slots, rc?)
  end

  defp emit_forward_ref_set(%{args: %{ref: ref, value: value}}, slots, rc?) do
    emit_runtime_call(:forward_ref_set, [ref_name(ref), Slots.reg_name(slots, value)], nil, slots, rc?)
  end

  defp emit_forward_ref_load(%{dest: dest_reg, args: %{ref: ref}}, slots, rc?) do
    emit_runtime_call(:forward_ref_load, [ref_name(ref)], dest_reg, slots, rc?)
  end

  defp emit_forward_ref_capture(%{dest: dest_reg, args: %{ref: ref}}, slots, rc?) do
    emit_runtime_call(:forward_ref_capture, [ref_name(ref)], dest_reg, slots, rc?)
  end

  defp emit_forward_ref_load_captured(%{dest: dest_reg, args: %{ref: ref}}, slots, rc?) do
    emit_runtime_call(:forward_ref_load_captured, [ref_name(ref)], dest_reg, slots, rc?)
  end

  defp emit_list_cursor_map(%{dest: dest_reg, args: args}, slots, rc?) do
    emit_runtime_call(
      :list_cursor_map,
      [
        Slots.reg_name(slots, Map.fetch!(args, :list)),
        int_const(Map.fetch!(args, :lambda_idx))
      ],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_unsupported_platform(%{dest: dest_reg, op: op}, slots) do
    emit_comment("unsupported platform op #{op}", %{dest: dest_reg}, slots)
  end

  defp emit_ret(reg, slots, rc?) do
    cond do
      reg == :fn_out ->
        []

      rc? ->
        emit_runtime_call(:new_int, [int_operand_wat(reg, slots)], :fn_out, slots, rc?)

      true ->
        [
          WasmTypes.line(
            WasmTypes.sexpr("local.set", [
              slots.fn_out_local,
              " ",
              WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])
            ])
          )
        ]
    end
  end

  defp emit_switch_tag(subject, arms, default_id, slots, _rc?) do
    subj = Slots.reg_name(slots, subject)

    arms_wat =
      Enum.map(arms, fn
        {tag, block_id, _} -> "#{tag} => #{br_label(block_id)}"
        {tag, block_id} -> "#{tag} => #{br_label(block_id)}"
      end)

    WasmTypes.line(
      WasmTypes.sexpr("br_table", [
        " ",
        WasmTypes.sexpr("local.get", [subj]),
        " ",
        br_label(default_id),
        " ",
        Enum.join(arms_wat, " ")
      ])
    )
  end

  defp format_call_arg(expr) when is_binary(expr) do
    if String.starts_with?(expr, "$") do
      " " <> WasmTypes.sexpr("local.get", [expr])
    else
      " " <> expr
    end
  end

  defp format_call_arg(expr), do: " " <> to_string(expr)

  defp emit_runtime_call(id, arg_exprs, dest_reg, slots, rc?, _opts \\ []) do
    import_name = RuntimeImports.import_name(id)
    import_sym = WasmTypes.import_ident(import_name)
    dest_local = dest_local_name(dest_reg, slots)
    mem_offset = Slots.pointer_mem_offset(slots, dest_reg) || 0

    args =
      [int_const(mem_offset) | pad_runtime_call_args(import_name, arg_exprs)]
      |> Enum.map(&format_call_arg/1)

    call = WasmTypes.sexpr("call", [import_sym | args])

    load_result =
      if dest_local != nil and dest_reg != nil and mem_offset > 0 do
        load =
          WasmTypes.line(
            WasmTypes.sexpr("local.set", [
              dest_local,
              " ",
              WasmTypes.i32_load_offset(mem_offset)
            ])
          )

        [load | Slots.sync_owned_slot(slots, dest_reg, dest_local)]
      else
        nil
      end

    call_lines =
      if rc? and RuntimeBuiltins.fallible?(id) do
        check_rc(call)
      else
        [WasmTypes.line(call)]
      end

    if load_result, do: call_lines ++ load_result, else: call_lines
  end

  defp dest_local_name(nil, _slots), do: nil
  defp dest_local_name(dest_reg, slots), do: dest_slot(dest_reg, slots)

  defp check_rc(call_expr) do
    [
      WasmTypes.line(
        WasmTypes.sexpr("local.set", ["$rc", " ", call_expr])
      ),
      WasmTypes.line(
        WasmTypes.sexpr("br_if", [
          " ",
          Frame.catch_begin_label(0),
          " ",
          WasmTypes.sexpr("i32.ne", [
            " ",
            WasmTypes.sexpr("local.get", ["$rc"]),
            " ",
            WasmTypes.sexpr("i32.const", [@rc_success])
          ])
        ])
      )
    ]
  end

  defp dest_slot(:fn_out, slots), do: slots.fn_out_local
  defp dest_slot(:branch_out, slots), do: slots.fn_out_local
  defp dest_slot(dest_reg, slots) when is_integer(dest_reg), do: Slots.reg_name(slots, dest_reg)

  defp set_reg(dest_reg, expr, slots) do
    dest = dest_slot(dest_reg, slots)

    WasmTypes.line(WasmTypes.sexpr("local.set", [dest, " ", expr]))
  end

  defp emit_comment(msg, %{dest: dest_reg}, slots) when is_integer(dest_reg) do
    set_reg(dest_reg, int_const(0), slots)
    |> then(fn _ -> [WasmTypes.line(";; #{msg}")] end)
  end

  defp emit_comment(msg, _, _), do: [WasmTypes.line(";; #{msg}")]

  defp emit_web_platform_op(%{op: op, dest: dest_reg, args: args}, slots, rc?)
       when op in [:html_cmd, :dom_sub, :browser_cmd, :json_cmd, :bytes_cmd] do
    kind = Map.get(args, :kind)
    params = Map.get(args, :params, []) |> List.wrap()

    kind_int =
      case kind do
        %{op: :int_literal, value: value} when is_integer(value) ->
          int_const(value)

        %{c_expr: expr} when is_binary(expr) ->
          resolve_c_expr_int(expr) |> elem_or(0) |> int_const()

        n when is_integer(n) ->
          int_const(n)

        _ ->
          int_const(0)
      end

    import_name =
      case op do
        :html_cmd -> "runtime.html_cmd"
        :dom_sub -> "runtime.dom_sub"
        :browser_cmd -> "runtime.browser_cmd"
        :json_cmd -> "runtime.json_cmd"
        :bytes_cmd -> "runtime.bytes_cmd"
      end

    emit_import_call(import_name, [kind_int | Enum.map(params, &Slots.reg_name(slots, &1))], dest_reg, slots, rc?)
  end

  defp emit_import_call(import_name, arg_exprs, dest_reg, slots, rc?) when is_binary(import_name) do
    import_sym = WasmTypes.import_ident(import_name)
    dest_local = dest_local_name(dest_reg, slots)
    mem_offset = Slots.pointer_mem_offset(slots, dest_reg) || 0

    args =
      [int_const(mem_offset) | pad_runtime_call_args(import_name, arg_exprs)]
      |> Enum.map(&format_call_arg/1)

    call = WasmTypes.sexpr("call", [import_sym | args])

    load_result =
      if dest_local != nil and dest_reg != nil and mem_offset > 0 do
        load =
          WasmTypes.line(
            WasmTypes.sexpr("local.set", [
              dest_local,
              " ",
              WasmTypes.i32_load_offset(mem_offset)
            ])
          )

        [load | Slots.sync_owned_slot(slots, dest_reg, dest_local)]
      else
        nil
      end

    call_lines =
      if rc? do
        check_rc(call)
      else
        [WasmTypes.line(call)]
      end

    if load_result, do: call_lines ++ load_result, else: call_lines
  end

  defp br(target_id, _opts \\ []) do
    WasmTypes.sexpr("br", [" ", br_label(target_id)])
  end

  @doc false
  def br_label(id), do: "$block_#{id}"

  defp binop(op, left, right) do
    WasmTypes.sexpr(op, [" ", format_operand(left), " ", format_operand(right)])
  end

  defp format_operand("$" <> _ = name), do: WasmTypes.sexpr("local.get", [name])
  defp format_operand(expr) when is_binary(expr), do: expr

  defp int_const(n) when is_integer(n) do
    # Elm Int is a 32-bit signed integer. Emit constants wrapped to i32.
    WasmTypes.sexpr("i32.const", [wrap_i32(n)])
  end

  defp int_const(_n), do: WasmTypes.sexpr("i32.const", [0])

  defp wrap_i32(n) when is_integer(n) do
    unsigned = Integer.mod(n, bsl(1, 32))

    if unsigned >= bsl(1, 31) do
      unsigned - bsl(1, 32)
    else
      unsigned
    end
  end

  defp bool_cond_wat(reg_name) do
    WasmTypes.sexpr("call", [
      WasmTypes.import_ident("runtime.as_bool"),
      " ",
      WasmTypes.sexpr("local.get", [reg_name])
    ])
  end

  defp call_import(name, args) do
    padded = pad_direct_import_args(name, args)

    WasmTypes.sexpr("call", [
      WasmTypes.import_ident(name) | Enum.map(padded, &format_call_arg/1)
    ])
  end

  defp pad_runtime_call_args(import_name, arg_exprs) when is_binary(import_name) and is_list(arg_exprs) do
    case Map.get(Process.get(:elmc_wasm_import_arities, %{}), import_name) do
      expected when is_integer(expected) ->
        have = 1 + length(arg_exprs)

        if expected > have do
          arg_exprs ++ Enum.map(1..(expected - have)//1, fn _ -> int_const(0) end)
        else
          arg_exprs
        end

      _ ->
        arg_exprs
    end
  end

  defp pad_direct_import_args(import_name, args) when is_binary(import_name) and is_list(args) do
    case Map.get(Process.get(:elmc_wasm_import_arities, %{}), import_name) do
      expected when is_integer(expected) and expected > length(args) ->
        args ++ Enum.map(1..(expected - length(args))//1, fn _ -> int_const(0) end)

      _ ->
        args
    end
  end

  defp field_index(args) do
    raw =
      cond do
        Map.has_key?(args, :field_index) -> Map.fetch!(args, :field_index)
        Map.has_key?(args, :index) -> Map.fetch!(args, :index)
        true -> 0
      end

    normalize_field_index(raw)
  end

  defp normalize_field_index(n) when is_integer(n), do: n

  defp normalize_field_index(s) when is_binary(s) do
    s
    |> String.trim()
    |> String.split("/*", parts: 2)
    |> hd()
    |> String.trim()
    |> then(fn trimmed ->
      case Integer.parse(trimmed) do
        {n, _} -> n
        :error -> 0
      end
    end)
  end

  defp normalize_field_index(_), do: 0

  defp ref_name(ref) when is_binary(ref), do: int_const(forward_ref_id(ref))
  defp ref_name(ref) when is_atom(ref), do: int_const(forward_ref_id(Atom.to_string(ref)))

  defp forward_ref_id(ref) when is_binary(ref) do
    cache = Process.get(:elmc_wasm_forward_ref_ids, %{})

    case Map.fetch(cache, ref) do
      {:ok, id} ->
        id

      :error ->
        id = map_size(cache)
        Process.put(:elmc_wasm_forward_ref_ids, Map.put(cache, ref, id))
        id
    end
  end

  defp literal_string_arg(value) when is_binary(value), do: int_const(:erlang.phash2(value, 1_000_000))

  defp resolve_c_expr_int(value) when is_integer(value), do: {:ok, value}

  defp resolve_c_expr_int(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp resolve_c_expr_int(_), do: :error

  defp elem_or({:ok, n}, _), do: n
  defp elem_or(:error, default), do: default

  defp build_runtime_call_args(id, args, slots, opts) do
    args
    |> Enum.with_index()
    |> Enum.map_reduce([], fn {reg, index}, prep ->
      {expr, prep_add} =
        cond do
          RuntimeBuiltins.native_int_arg?(id, index) ->
            {int_operand_wat(reg, slots), []}

          true ->
            boxed_runtime_arg_wat(reg, slots, opts)
        end

      {expr, prep ++ prep_add}
    end)
    |> then(fn {exprs, prep} -> {exprs, prep} end)
  end

  defp boxed_runtime_arg_wat(reg, slots, _opts) when reg in [:fn_out, :branch_out] do
    {Slots.reg_name(slots, reg), []}
  end

  defp boxed_runtime_arg_wat(reg, slots, opts) when is_integer(reg) do
    if Map.has_key?(slots.slot_map, reg) do
      {Slots.reg_name(slots, reg), []}
    else
      case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
        %{op: :const_int, args: %{value: value}} when is_integer(value) ->
          box_const_int_arg(value, reg, slots)

        %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
          box_const_int_arg(value, reg, slots)

        %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
          case resolve_c_expr_int(expr) do
            {:ok, value} -> box_const_int_arg(value, reg, slots)
            :error -> {Slots.reg_name(slots, reg), []}
          end

        _ ->
          if native_int_reg?(opts, reg) do
            box_native_int_arg(reg, slots)
          else
            {Slots.reg_name(slots, reg), []}
          end
      end
    end
  end

  defp box_const_int_arg(value, reg, slots) do
    offset = Map.fetch!(slots.reg_mem, reg)
    prep = box_const_int_prep(value, offset)
    {boxed_handle_at_offset(offset), prep}
  end

  defp box_native_int_arg(reg, slots) do
    offset = Map.fetch!(slots.reg_mem, reg)
    prep = box_native_int_prep(reg, slots, offset)
    {boxed_handle_at_offset(offset), prep}
  end

  defp box_const_int_prep(value, offset) do
    [
      WasmTypes.line(
        WasmTypes.sexpr("call", [
          WasmTypes.import_ident("runtime.new_int"),
          " ",
          int_const(offset),
          " ",
          int_const(value)
        ])
      )
    ]
  end

  defp box_native_int_prep(reg, slots, offset) do
    [
      WasmTypes.line(
        WasmTypes.sexpr("call", [
          WasmTypes.import_ident("runtime.new_int"),
          " ",
          int_const(offset),
          " ",
          int_operand_wat(reg, slots)
        ])
      )
    ]
  end

  defp boxed_handle_at_offset(offset) do
    WasmTypes.i32_load_offset(offset)
  end

  defp native_int_reg?(opts, reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :const_int} ->
        true

      %{op: :int_arith} ->
        true

      %{op: :compare} ->
        true

      %{op: :phi, args: %{native_int_phi: true}} ->
        true

      %{op: :record_get_int} ->
        true

      %{op: :call_runtime, args: %{builtin: :new_int, literal: _}} ->
        true

      %{op: :call_runtime, args: %{builtin: :new_int, c_expr: _}} ->
        true

      %{op: :load_param, args: %{index: index}} ->
        param_kinds = Keyword.get(opts, :param_kinds, [])
        Enum.at(param_kinds, index, :boxed) == :native_int

      _ ->
        false
    end
  end

  defp defining_plan_instr(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.find(fn %{dest: dest} -> dest == reg end)
  end

  defp defining_plan_instr(_, _), do: nil

  defp float32_bits_const(value) when is_integer(value), do: float32_bits_const(value * 1.0)

  defp float32_bits_const(value) when is_float(value) do
    <<bits::unsigned-integer-32>> = <<value::float-32>>
    int_const(bits)
  end

  defp track_wasm_callee!(mod, name, args) when is_binary(mod) and is_binary(name) do
    {mod, name} = normalize_wasm_callee(mod, name)
    arity = length(args)
    key = {mod, name}

    cache =
      Process.get(:elmc_wasm_emitted_calls, %{})
      |> Map.update(key, arity, &Kernel.max(&1, arity))

    Process.put(:elmc_wasm_emitted_calls, cache)
  end

  defp track_wasm_callee!(_, _, _), do: :ok

  defp normalize_wasm_callee(mod, name) do
    if String.contains?(name, ".") do
      Elmc.Backend.Plan.Lower.Call.parse_target("#{mod}.#{name}", %{module: mod}, %{})
    else
      {mod, name}
    end
  end
end
