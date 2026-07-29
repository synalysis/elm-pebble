defmodule Elmc.Backend.Wasm.Lower.Instr do
  @moduledoc false
  alias Elmc.Types, as: Types


  import Bitwise

  alias Elmc.Backend.Bytecode.FnTable
  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
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
    lines = emit_impl(instr, slots, opts) |> normalize_lines()

    nulls =
      if Keyword.get(opts, :rc_required, true) do
        emit_null_consumed_slots(instr, slots, opts)
      else
        []
      end

    lines ++ nulls
  end

  @spec publish_fn_out(Slots.t(), non_neg_integer(), emit_opts()) :: [binary()]
  def publish_fn_out(slots, reg, opts) when is_integer(reg) do
    rc? = Keyword.get(opts, :rc_required, true)
    native? = Keyword.get(opts, :native_scalar_out) in [:native_int, :native_bool]
    box? =
      native? or raw_native_int_fn_out_reg?(opts, reg) or
        raw_scalar_int_operand?(opts, reg, MapSet.new())

    cond do
      box? ->
        builtin =
          case Keyword.get(opts, :native_scalar_out) do
            :native_bool -> :new_bool
            _ -> :new_int
          end

        emit_runtime_call(builtin, [int_operand_wat(reg, slots, opts)], :fn_out, slots, rc?, opts)

      rc? ->
        Slots.publish_reg_to_fn_out(slots, reg)

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

  defp raw_native_int_fn_out_reg?(opts, reg, visited \\ MapSet.new()) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      false
    else
      case Keyword.get(opts, :parent_plan) do
        %FunctionPlan{} = plan ->
          visited = MapSet.put(visited, reg)

          instrs = CLowerFunction.all_defining_instrs(plan, reg)

          # Every definition must be a raw scalar. `Enum.any?` wrongly treated
          # multi-block regs (const_int Ok arm + tuple_proj Err arm) as raw,
          # so publish boxed the Err handle id as an Int (probeFail → 2).
          instrs != [] and
            Enum.all?(instrs, fn
              %{op: op}
              when op in [
                     :const_int,
                     :compare,
                     :bool_and,
                     :bool_or,
                     :int_arith,
                     :test_maybe_nothing,
                     :test_list_empty,
                     :test_list_length_gte,
                     :test_ctor_tag,
                     :test_bool
                   ] ->
                true

              %{op: :phi, args: args} ->
                then_r = Map.fetch!(args, :then)
                else_r = Map.fetch!(args, :else)

                raw_native_int_fn_out_reg?(opts, then_r, visited) and
                  raw_native_int_fn_out_reg?(opts, else_r, visited)

              _ ->
                false
            end)

        _ ->
          false
      end
    end
  end

  defp emit_impl(%Types{} = instr, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    fn_table = Keyword.fetch!(opts, :fn_table)

    case instr.op do
      op when op in [:catch_begin, :catch_end] ->
        []

      :release ->
        emit_release(instr, slots, opts)

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
        emit_int_arith(instr, slots, rc?, opts)

      :compare ->
        emit_compare(instr, slots, opts)

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
        emit_record_update(instr, slots, rc?, opts)

      :tuple_proj ->
        emit_tuple_proj(instr, slots, rc?)

      :phi ->
        emit_phi(instr, slots, opts)

      :switch_ctor_tag ->
        emit_switch_ctor_tag(instr, slots)

      :test_maybe_nothing ->
        emit_test_maybe_nothing(instr, slots, rc?)

      :test_list_empty ->
        emit_test_list_empty(instr, slots, rc?)

      :test_list_length_gte ->
        emit_test_list_length_gte(instr, slots, rc?)

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
        emit_list_cursor_map(instr, slots, rc?, opts)

      :html_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :browser_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :json_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :bytes_cmd ->
        emit_web_platform_op(instr, slots, rc?)

      :parser_cmd ->
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
        emit_ret(reg, slots, rc?, opts)

      :none ->
        []

      _ ->
        emit_ret(0, slots, rc?, opts)
    end
  end

  defp emit_publish(%{args: %{source: reg}}, slots, opts) when is_integer(reg) do
    publish_fn_out(slots, reg, opts)
  end

  defp emit_publish(%{dest: :fn_out}, _slots, _opts), do: []

  defp emit_load_param(%{dest: dest_reg, args: %{index: index}}, slots) do
    param = WasmTypes.ident("param#{index}")
    set_reg(dest_reg, WasmTypes.sexpr("local.get", [param]), slots)
  end

  defp emit_load_local(%{dest: dest_reg, args: %{source: source}}, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)

    cond do
      dest_reg in [:fn_out, :branch_out] and rc? ->
        publish_fn_out(slots, source, opts)

      rc? and is_integer(dest_reg) ->
        # Match Builder.copy_reg_owned: owned local scratch must retain.
        emit_runtime_call(:retain, [Slots.reg_name(slots, source)], dest_reg, slots, false)

      true ->
        src = Slots.reg_name(slots, source)
        [set_reg(dest_reg, WasmTypes.sexpr("local.get", [src]), slots)]
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

  defp emit_int_arith(%{dest: dest_reg, args: args}, slots, rc?, opts) do
    kind = Map.fetch!(args, :kind)
    lhs = Map.fetch!(args, :lhs)
    rhs = Map.get(args, :rhs)
    native_dest? = MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg)

    cond do
      # Int arithmetic must stay on the i32/new_int path. A prior float fallback
      # for non-native regs broke Int countdown loops (TriangularMesh.gridFaceIndices):
      # `uIndex0 - 1` became f32.sub and never reached a stable Int zero.
      kind in [:min_vars, :max_vars] and not native_int_binop_operands?(lhs, rhs, opts, MapSet.new()) ->
        builtin = if kind == :min_vars, do: :basics_min, else: :basics_max

        emit_runtime_call(
          builtin,
          [Slots.reg_name(slots, lhs), Slots.reg_name(slots, rhs)],
          dest_reg,
          slots,
          rc?,
          opts
        )

      # Boxed Float-ish operands (Quantity unwrap via tuple_proj, new_float, etc.).
      # Plan sometimes emits int_arith for `f + n` in projectionMatrix; as_int
      # truncates and `-(f+n)/(f-n)` explodes. Do NOT float-promote arbitrary
      # boxed Ints — that hung TriangularMesh-style countdowns.
      kind in [:add_vars, :sub_vars, :mul_vars] and is_integer(lhs) and is_integer(rhs) and
          (floatish_reg?(opts, lhs, MapSet.new()) or floatish_reg?(opts, rhs, MapSet.new())) ->
        op =
          case kind do
            :add_vars -> :add
            :sub_vars -> :sub
            :mul_vars -> :mul
          end

        emit_float_binop(op, lhs, rhs, dest_reg, slots, rc?, opts)

      true ->
        expr =
          case kind do
            :add_const ->
              binop("i32.add", int_operand_wat(lhs, slots, opts), int_const(Map.fetch!(args, :value)))

            :sub_const ->
              binop("i32.sub", int_operand_wat(lhs, slots, opts), int_const(Map.fetch!(args, :value)))

            :add_vars ->
              binop("i32.add", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))

            :sub_vars ->
              binop("i32.sub", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))

            :mul_vars ->
              binop("i32.mul", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))

            :idiv_vars ->
              binop("i32.div_s", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))

            # Plan stores lhs = modulus (modBy/remainderBy first arg), rhs = value.
            # Match C elm_mod_by_c_expr / rem: value % base (not base % value).
            :mod_vars ->
              binop("i32.rem_s", int_operand_wat(rhs, slots, opts), int_operand_wat(lhs, slots, opts))

            :rem_vars ->
              binop("i32.rem_s", int_operand_wat(rhs, slots, opts), int_operand_wat(lhs, slots, opts))

            :min_vars ->
              l = int_operand_wat(lhs, slots, opts)
              r = int_operand_wat(rhs, slots, opts)
              # No i32.min_s in WASM; select on i32.le_s (same as C ternary).
              WasmTypes.sexpr("select", [" ", l, " ", r, " ", binop("i32.le_s", l, r)])

            :max_vars ->
              l = int_operand_wat(lhs, slots, opts)
              r = int_operand_wat(rhs, slots, opts)
              WasmTypes.sexpr("select", [" ", l, " ", r, " ", binop("i32.ge_s", l, r)])

            _ ->
              int_const(0)
          end

        if native_dest? do
          [set_reg(dest_reg, expr, slots)]
        else
          emit_runtime_call(:new_int, [expr], dest_reg, slots, rc?, opts)
        end
    end
  end

  defp int_operand_wat(reg, slots, opts) do
    reg_expr = WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])

    if raw_scalar_int_operand?(opts, reg, MapSet.new()) do
      reg_expr
    else
      WasmTypes.sexpr("call", [
        WasmTypes.import_ident("runtime.as_int"),
        " ",
        reg_expr
      ])
    end
  end

  defp emit_compare(%{dest: dest_reg, args: args}, slots, opts) do
    left_reg = Map.fetch!(args, :left)
    right_reg = Map.fetch!(args, :right)
    left = Slots.reg_name(slots, left_reg)
    right = Slots.reg_name(slots, right_reg)
    kind = Map.fetch!(args, :kind)
    mode = effective_compare_mode(args, opts)

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

      {:list_int, :eq} ->
        emit_runtime_call(:list_equal_int, [left, right], dest_reg, slots, false)

      {:list_int, :neq} ->
        emit_runtime_call(:list_equal_int, [left, right], dest_reg, slots, false) ++
          emit_runtime_call(
            :basics_not,
            [Slots.reg_name(slots, dest_reg)],
            dest_reg,
            slots,
            false
          )

      {:int_boxed, _} ->
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

        left_wat = int_operand_wat(left_reg, slots, opts)
        right_wat = int_operand_wat(right_reg, slots, opts)
        [set_reg(dest_reg, binop(pred, left_wat, right_wat), slots)]

      {:bool_scalar, _} ->
        pred =
          case kind do
            :eq -> "i32.eq"
            :neq -> "i32.ne"
            _ -> "i32.eq"
          end

        left_wat = bool_scalar_operand_wat(left_reg, slots, opts)
        right_wat = bool_scalar_operand_wat(right_reg, slots, opts)
        [set_reg(dest_reg, binop(pred, left_wat, right_wat), slots)]

      {:float_boxed, _} ->
        pred =
          case kind do
            :eq -> "f32.eq"
            :neq -> "f32.ne"
            :gt -> "f32.gt"
            :gte -> "f32.ge"
            :lt -> "f32.lt"
            :lte -> "f32.le"
            _ -> "f32.eq"
          end

        left_wat = float_operand_wat(left_reg, slots, opts)
        right_wat = float_operand_wat(right_reg, slots, opts)
        [set_reg(dest_reg, binop(pred, left_wat, right_wat), slots)]

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

  # Raw int consts (e.g. `0` in `stripIndex == 0`) must convert, not as_float —
  # handle id 0 is null and other small ints can alias live handles.
  defp float_operand_wat(reg, slots, opts) do
    reg_expr = WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])

    if raw_scalar_int_operand?(opts, reg, MapSet.new()) do
      WasmTypes.sexpr("f32.convert_i32_s", [" ", format_operand(reg_expr)])
    else
      bits = call_import("runtime.as_float", [reg_expr])
      WasmTypes.sexpr("f32.reinterpret_i32", [" ", format_operand(bits)])
    end
  end

  defp emit_boxed_binop(%{dest: dest_reg, args: %{op: op, lhs: lhs, rhs: rhs} = args}, slots, rc?, opts) do
    float_mode? = Map.get(args, :mode) == :float

    cond do
      # Float division must never take the native-int path. `emit_native_int_binop`
      # has no `:fdiv` clause and emitted `i32.const 0` — so `toFloat c / 255`
      # (Color.rgb255) became 0 and Scene3d cleared to black.
      op == :fdiv ->
        emit_fdiv_binop(lhs, rhs, dest_reg, slots, rc?, opts)

      op == :idiv and
          (float_mode? or
             (not native_int_binop_operands?(lhs, rhs, opts, MapSet.new()) and
                (floatish_reg?(opts, lhs, MapSet.new()) or floatish_reg?(opts, rhs, MapSet.new())))) ->
        emit_fdiv_binop(lhs, rhs, dest_reg, slots, rc?, opts)

      # Plan-marked Float ops (float_mixture / Color soft-float params) and
      # Float-ish regs (record_get, new_float, basics_abs, …). Boxed Int
      # `x * 2` in Result.andThen stays on as_int/i32 when neither applies.
      op in [:add, :sub, :mul] and
          (float_mode? or floatish_reg?(opts, lhs, MapSet.new()) or
             floatish_reg?(opts, rhs, MapSet.new())) ->
        emit_float_binop(op, lhs, rhs, dest_reg, slots, rc?, opts)

      op in [:add, :sub, :mul, :idiv] ->
        native_dest? =
          MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg)

        if native_dest? do
          [emit_native_int_binop(op, lhs, rhs, dest_reg, slots, opts)]
        else
          expr =
            case op do
              :add -> binop("i32.add", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))
              :sub -> binop("i32.sub", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))
              :mul -> binop("i32.mul", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))
              :idiv -> binop("i32.div_s", int_operand_wat(lhs, slots, opts), int_operand_wat(rhs, slots, opts))
            end

          emit_runtime_call(:new_int, [expr], dest_reg, slots, rc?, opts)
        end

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

  defp emit_float_binop(op, lhs, rhs, dest_reg, slots, rc?, opts, kw \\ []) do
    rhs_is_const? = Keyword.get(kw, :rhs_is_const, false)
    const_value = Keyword.get(kw, :const_value, 0)

    {left, prep_left} = boxed_runtime_arg_wat(lhs, slots, opts)

    {bits_rhs, prep_right} =
      if rhs_is_const? do
        {float32_bits_const(const_value * 1.0), []}
      else
        {right, prep} = boxed_runtime_arg_wat(rhs, slots, opts)
        {call_import("runtime.as_float", [right]), prep}
      end

    wasm_op =
      case op do
        :add -> "f32.add"
        :sub -> "f32.sub"
        :mul -> "f32.mul"
        _ -> "f32.add"
      end

    bits_lhs = call_import("runtime.as_float", [left])

    f32_lhs = WasmTypes.sexpr("f32.reinterpret_i32", [" ", format_operand(bits_lhs)])
    f32_rhs = WasmTypes.sexpr("f32.reinterpret_i32", [" ", format_operand(bits_rhs)])

    f32_result = binop(wasm_op, f32_lhs, f32_rhs)

    result_bits =
      WasmTypes.sexpr("i32.reinterpret_f32", [" ", format_operand(f32_result)])

    prep_left ++ prep_right ++ emit_runtime_call(:new_float, [result_bits], dest_reg, slots, rc?, opts)
  end

  defp emit_native_int_binop(op, lhs, rhs, dest_reg, slots, opts) do
    left = int_operand_wat(lhs, slots, opts)
    right = int_operand_wat(rhs, slots, opts)

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

  defp native_int_binop_operands?(lhs, rhs, opts, visited)
       when is_integer(lhs) and is_integer(rhs) do
    native_int_reg?(opts, lhs, visited) and native_int_reg?(opts, rhs, visited)
  end

  defp native_int_binop_operands?(_, _, _, _), do: false

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :native_int_to_float, args: [reg]}}, slots, rc?, opts)
       when is_integer(reg) do
    # Convert the i32 payload as a native int. Do not call as_int first: raw
    # consts like 72 collide with live handles (handle 72 may be Int(2)).
    scalar = WasmTypes.sexpr("local.get", [Slots.reg_name(slots, reg)])

    f32 =
      WasmTypes.sexpr("f32.convert_i32_s", [
        " ",
        format_operand(scalar)
      ])

    bits =
      WasmTypes.sexpr("i32.reinterpret_f32", [
        " ",
        format_operand(f32)
      ])

    emit_runtime_call(:new_float, [bits], dest_reg, slots, rc?, opts)
  end

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

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: id} = args_map}, slots, rc?, opts) do
    call_args = Map.get(args_map, :args) || []
    {reg_exprs, prep} = build_runtime_call_args(id, call_args, slots, opts)
    literal = Map.get(args_map, :literal)
    c_expr = Map.get(args_map, :c_expr)

    extra =
      cond do
        id == :new_float and is_number(literal) -> [float32_bits_const(literal)]
        literal != nil and is_integer(literal) -> [int_const(literal)]
        is_binary(c_expr) or is_integer(c_expr) -> [c_expr_int_wat(c_expr, opts)]
        true -> []
      end

    prep ++ emit_runtime_call(id, reg_exprs ++ extra, dest_reg, slots, rc?, opts)
  end

  defp c_expr_int_wat(expr, opts) do
    case resolve_c_expr_int(expr) do
      {:ok, n} ->
        int_const(n)

      :error when is_binary(expr) ->
        # Native-int ABI params are boxed via `new_int` + C param name; map back to `$paramN`.
        case param_index_for_c_expr(expr, opts) do
          {:ok, idx} -> WasmTypes.sexpr("local.get", [WasmTypes.ident("param#{idx}")])
          :error -> int_const(0)
        end

      :error ->
        int_const(0)
    end
  end

  defp param_index_for_c_expr(name, opts) when is_binary(name) do
    case Keyword.get(opts, :parent_plan) do
      %{params: params} when is_list(params) ->
        idx =
          Enum.find_index(params, fn
            %{name: ^name} -> true
            ^name -> true
            _ -> false
          end)

        if is_integer(idx), do: {:ok, idx}, else: :error

      _ ->
        :error
    end
  end

  defp emit_call_fn(%{dest: dest_reg, args: %{module: mod, name: name, args: args}}, slots, fn_table, rc?, opts) do
    _idx = FnTable.index(fn_table, {mod, name})
    track_wasm_callee!(mod, name, args || [])
    callee = WasmTypes.fn_ident(mod, name)

    # Box const_int / native-int temps to heap handles. Raw i32.const 0/1 (True/False)
    # collide with immortal UNIT (handle 1); retain rematerializes True as Int(0).
    {arg_exprs, prep} =
      Enum.map_reduce(args || [], [], fn reg, acc_prep ->
        {expr, prep_add} = boxed_runtime_arg_wat(reg, slots, opts)
        {expr, acc_prep ++ prep_add}
      end)

    call =
      WasmTypes.sexpr("call", [
        callee | Enum.map(arg_exprs, fn expr -> " " <> format_operand(expr) end)
      ])

    {pop_value, pop_rc} =
      if dest_reg in [:fn_out, :branch_out] do
        {slots.fn_out_local, slots.rc_local}
      else
        {dest_slot(dest_reg, slots), slots.rc_local}
      end

    call_lines =
      prep ++
        [
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

  defp emit_call_closure(%{dest: dest_reg, args: %{callee: callee, args: args}}, slots, rc?, opts) do
    call_args = args || []

    {arg_exprs, prep} =
      Enum.map_reduce(call_args, [], fn reg, acc_prep ->
        {expr, prep_add} = boxed_runtime_arg_wat(reg, slots, opts)
        {expr, acc_prep ++ prep_add}
      end)

    prep ++
      emit_runtime_call(
        :call_closure,
        [int_const(length(call_args)), Slots.reg_name(slots, callee) | arg_exprs],
        dest_reg,
        slots,
        rc?,
        opts
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

  defp emit_record_update(%{dest: dest_reg, args: args}, slots, rc?, opts) do
    base_reg = Map.fetch!(args, :base)
    value_reg = Map.fetch!(args, :value)
    {value_expr, prep} = boxed_runtime_arg_wat(value_reg, slots, opts)

    prep ++
      emit_runtime_call(
        :record_update,
        [
          Slots.reg_name(slots, base_reg),
          value_expr,
          int_const(field_index(args))
        ],
        dest_reg,
        slots,
        rc?,
        opts
      ) ++ cow_drop_alias_null(dest_reg, base_reg, slots)
  end

  # Match C cow_drop_alias_null: host cow_drop already released the old record;
  # null the base owned shadow so LIFO does not double-free nested fields.
  defp cow_drop_alias_null(dest_reg, base_reg, slots)
       when is_integer(base_reg) do
    dest_idx = Map.get(slots.slot_map, dest_reg)
    base_idx = Map.get(slots.slot_map, base_reg)

    if is_integer(base_idx) and dest_idx != base_idx do
      Slots.clear_owned_slot(slots, base_reg)
    else
      []
    end
  end

  defp cow_drop_alias_null(_dest_reg, _base_reg, _slots), do: []

  defp emit_release(%{args: %{reg: reg}}, slots, opts) when is_integer(reg) do
    if raw_scalar_int_operand?(opts, reg, MapSet.new()) do
      [
        WasmTypes.line(
          WasmTypes.sexpr("local.set", [
            Slots.reg_name(slots, reg),
            " ",
            WasmTypes.sexpr("i32.const", [0])
          ])
        )
      ] ++ Slots.clear_owned_slot(slots, reg)
    else
      Slots.release_owned_slot(slots, reg)
    end
  end

  defp emit_release(_, _, _), do: []

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

  defp emit_phi(%{dest: dest_reg, args: args}, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    cond_reg = Map.get(args, :cond)
    dest = Slots.reg_name(slots, dest_reg)

    cond_wat =
      case cond_reg do
        cond when is_integer(cond) or cond in [:fn_out, :branch_out] ->
          bool_cond_wat(Slots.reg_name(slots, cond))

        _ ->
          WasmTypes.sexpr("i32.const", [0])
      end

    native_int? = Map.get(args, :native_int_phi) == true
    truthy? = Map.get(args, :truthy_native) == true

    if rc? and not native_int? and not truthy? do
      emit_phi_transfer_merge(dest_reg, dest, cond_wat, args, slots)
    else
      {then_expr, else_expr} = phi_arm_exprs(args, slots, opts)

      [
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
        | Slots.sync_owned_slot(slots, dest_reg, dest)
      ]
    end
  end

  # Match C phi transfer into merge owned: copy winning arm, null its owned shadow
  # so LIFO epilogue does not double-free the published handle.
  defp emit_phi_transfer_merge(dest_reg, dest, cond_wat, args, slots) do
    then_reg = Map.get(args, :then)
    else_reg = Map.get(args, :else)
    {then_expr, else_expr} = phi_arm_exprs(args, slots, [])

    then_arm =
      [
        WasmTypes.line(WasmTypes.sexpr("local.set", [dest, " ", then_expr]))
        | if(is_integer(then_reg), do: Slots.clear_owned_slot(slots, then_reg), else: [])
      ]

    else_arm =
      [
        WasmTypes.line(WasmTypes.sexpr("local.set", [dest, " ", else_expr]))
        | if(is_integer(else_reg), do: Slots.clear_owned_slot(slots, else_reg), else: [])
      ]

    [
      WasmTypes.line(WasmTypes.sexpr_open("if", [cond_wat])),
      WasmTypes.line("(then"),
      WasmTypes.indent(then_arm, 1),
      WasmTypes.line(") (else"),
      WasmTypes.indent(else_arm, 1),
      WasmTypes.line(")"),
      WasmTypes.line(")")
    ] ++ Slots.sync_owned_slot(slots, dest_reg, dest)
  end

  defp phi_arm_exprs(%{native_int_phi: true} = args, _slots, _opts) do
    {
      phi_shape_wat(Map.get(args, :then_shape)),
      phi_shape_wat(Map.get(args, :else_shape))
    }
  end

  # Match C phi_truthy_arm_exprs: truthy_native arms drop their compare/const
  # instrs, so reconstruct from shapes instead of local.get on unset regs.
  # Without this, `a && b` (probeInsertAlias) left the second compare's dest at 0.
  defp phi_arm_exprs(%{truthy_native: true} = args, slots, opts) do
    {
      truthy_shape_wat(Map.get(args, :then_shape), Map.get(args, :then), slots, opts),
      truthy_shape_wat(Map.get(args, :else_shape), Map.get(args, :else), slots, opts)
    }
  end

  defp phi_arm_exprs(args, slots, _opts) do
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

  defp truthy_shape_wat({:const_int, value}, _reg, _slots, _opts) when value in [0, 1],
    do: int_const(value)

  defp truthy_shape_wat({:compare, kind, left, right}, _reg, slots, opts) do
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

    binop(pred, int_operand_wat(left, slots, opts), int_operand_wat(right, slots, opts))
  end

  defp truthy_shape_wat({:reg, reg}, _phi_reg, slots, _opts) when is_integer(reg) do
    bool_cond_wat(Slots.reg_name(slots, reg))
  end

  defp truthy_shape_wat(_shape, reg, slots, _opts) when is_integer(reg) do
    bool_cond_wat(Slots.reg_name(slots, reg))
  end

  defp truthy_shape_wat(_, _, _, _), do: int_const(0)

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

  defp emit_test_list_length_gte(%{dest: dest_reg, args: %{reg: reg, min: min}}, slots, rc?)
       when is_integer(min) do
    emit_runtime_call(
      :list_length_gte,
      [Slots.reg_name(slots, reg), int_const(min)],
      dest_reg,
      slots,
      rc?
    )
  end

  defp emit_test_ctor_tag(%{dest: dest_reg, args: args}, slots, rc?) do
    subject = Map.fetch!(args, :subject)
    tag = order_runtime_tag(Map.get(args, :union_ctor), Map.fetch!(args, :tag))

    emit_runtime_call(
      :union_tag_matches,
      [Slots.reg_name(slots, subject), int_const(tag)],
      dest_reg,
      slots,
      rc?
    )
  end

  # Match C TagRefs.order_runtime_scalar_ref: Order is TAG_ORDER -1/0/1, not
  # constructor-table ids (typically 1/2/3 for Basics.LT/EQ/GT).
  defp order_runtime_tag(ctor, tag) when is_binary(ctor) do
    case ctor |> String.split(".") |> List.last() do
      "LT" -> -1
      "EQ" -> 0
      "GT" -> 1
      _ -> tag
    end
  end

  defp order_runtime_tag(_ctor, tag), do: tag

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

  defp emit_list_cursor_map(%{dest: dest_reg, args: args}, slots, rc?, opts) do
    start_wat = cursor_bound_wat(args, :start, :start_literal?, slots)
    end_wat = cursor_bound_wat(args, :end, :end_literal?, slots)
    parent = Keyword.fetch!(opts, :parent_plan)
    registry = Process.get(:elmc_wasm_closure_registry)
    global_idx = ClosureRegistry.global_index(registry, parent, Map.fetch!(args, :lambda_idx))

    emit_runtime_call(
      :list_cursor_map,
      [start_wat, end_wat, int_const(global_idx)],
      dest_reg,
      slots,
      rc?,
      opts
    )
  end

  defp cursor_bound_wat(args, key, literal_key, slots) do
    if Map.get(args, literal_key) do
      int_const(Map.fetch!(args, key))
    else
      Slots.reg_name(slots, Map.fetch!(args, key))
    end
  end

  defp emit_unsupported_platform(%{dest: dest_reg, op: op}, slots) do
    emit_comment("unsupported platform op #{op}", %{dest: dest_reg}, slots)
  end

  defp emit_ret(reg, slots, rc?, opts) do
    cond do
      reg == :fn_out ->
        []

      is_integer(reg) ->
        # Zero-arity memoized values may have rc_required=false but still use the
        # (rc, fn_out) ABI. Always publish via publish_fn_out so native/raw
        # scalars are boxed (raw i32 0/1 collides with immortal UNIT/bool handles).
        publish_fn_out(slots, reg, opts)

      rc? ->
        emit_runtime_call(:new_int, [int_operand_wat(reg, slots, opts)], :fn_out, slots, rc?, opts)

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

  # Mirror C `emit_null_consumed_slots`: after a consuming op, abandon owned
  # temps (release when callee borrowed+retained; null-only on ownership transfer).
  defp emit_null_consumed_slots(%{op: :publish}, _slots, _opts), do: []
  defp emit_null_consumed_slots(%{op: :release}, _slots, _opts), do: []

  defp emit_null_consumed_slots(instr, slots, opts) do
    if tail_fn_out_owned_cleanup_instr?(instr) and not transferring_consume_instr?(instr) do
      []
    else
      emit_null_consumed_slots_from_effects(instr, slots, opts)
    end
  end

  defp emit_null_consumed_slots_from_effects(%{effects: %{consumes: consumes}} = instr, slots, opts)
       when is_list(consumes) do
    transfer? = transferring_consume_instr?(instr)

    consumes
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&retain_owned_transfer_null?(instr, &1))
    |> Enum.uniq()
    |> Enum.flat_map(fn reg ->
      cond do
        transfer? ->
          # Host retain builders: null shadows only.
          Slots.clear_owned_slot(slots, reg)

        # const_int / native i32 temps are not heap handles. Releasing the raw
        # value (e.g. i32.const 2) frees whatever live handle currently has that
        # id — classic Tuple.first (1,2) → 2 after release(2) kills Int(1).
        raw_scalar_int_operand?(opts, reg, MapSet.new()) ->
          [
            WasmTypes.line(
              WasmTypes.sexpr("local.set", [
                Slots.reg_name(slots, reg),
                " ",
                WasmTypes.sexpr("i32.const", [0])
              ])
            )
          ] ++ Slots.clear_owned_slot(slots, reg)

        true ->
          Slots.release_owned_slot(slots, reg)
      end
    end)
  end

  defp emit_null_consumed_slots_from_effects(_, _slots, _opts), do: []

  defp tail_fn_out_owned_cleanup_instr?(%{op: op, dest: dest})
       when op in [:call_runtime, :call_fn, :call_closure, :record_update, :make_closure, :pebble_cmd] and
              dest in [:fn_out, :branch_out],
       do: true

  defp tail_fn_out_owned_cleanup_instr?(_), do: false

  defp retain_owned_transfer_null?(
         %{op: :call_runtime, args: %{builtin: :retain, args: [src]}, effects: %{consumes: consumes}},
         reg
       )
       when is_integer(src) and is_list(consumes),
       do: reg == src and src in consumes

  defp retain_owned_transfer_null?(_, _), do: false

  defp transferring_consume_instr?(%{op: :const_static_list, args: %{kind: kind}})
       when kind in [:values, :record_array],
       do: true

  defp transferring_consume_instr?(%{
         op: :call_runtime,
         args: %{builtin: :retain, args: [src]},
         effects: %{consumes: consumes}
       })
       when is_integer(src) and is_list(consumes) do
    src in consumes
  end

  defp transferring_consume_instr?(%{op: :call_runtime, args: %{builtin: id}}) do
    # Host retain builders (tuple2 / make_closure / record_new): caller's owned
    # args become nested under the result — null shadows only (do not release).
    id in [
      :record_new,
      :record_new_take,
      :tuple2,
      :tuple2_take,
      :make_closure,
      :sub_batch,
      :cmd_batch,
      :sub_map,
      :cmd_map
    ] or RuntimeBuiltins.ownership_transfer?(id)
  end

  defp transferring_consume_instr?(%{op: op}) when op in [:make_closure, :record_update], do: true

  defp transferring_consume_instr?(_), do: false

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
       when op in [:html_cmd, :dom_sub, :browser_cmd, :json_cmd, :bytes_cmd, :parser_cmd] do
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
        :parser_cmd -> "runtime.parser_cmd"
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

  defp bool_scalar_operand_wat(reg, slots, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :const_int, args: %{value: value}} when value in [0, 1] ->
        int_const(value)

      %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when value in [0, 1] ->
        int_const(value)

      %{op: :call_runtime, args: %{builtin: :new_bool, literal: value}} when value in [0, 1] ->
        int_const(value)

      _ ->
        bool_cond_wat(Slots.reg_name(slots, reg))
    end
  end

  defp bool_scalar_operand_wat(reg, slots, _opts) do
    bool_cond_wat(Slots.reg_name(slots, reg))
  end

  defp effective_compare_mode(args, opts) do
    mode = Map.get(args, :mode, :pointer)
    kind = Map.get(args, :kind, :eq)

    if mode == :pointer and kind in [:eq, :neq] and boxed_bool_test_compare_reg?(args, opts) do
      :bool_scalar
    else
      mode
    end
  end

  defp boxed_bool_test_compare_reg?(%{left: left, right: right}, opts) do
    boxed_bool_test_plan_reg?(left, opts) or boxed_bool_test_plan_reg?(right, opts)
  end

  defp boxed_bool_test_plan_reg?(reg, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: op} when op in [:test_list_empty, :test_maybe_nothing] ->
        true

      %{op: :call_runtime, args: %{builtin: builtin}}
      when builtin in [:list_is_empty, :maybe_is_nothing, :string_length_boxed] ->
        true

      _ ->
        false
    end
  end

  defp boxed_bool_test_plan_reg?(_, _), do: false

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
        :error -> resolve_field_index_macro(trimmed)
      end
    end)
  end

  defp normalize_field_index(_), do: 0

  defp resolve_field_index_macro(macro) when is_binary(macro) do
    case Process.get(:elmc_wasm_record_field_macro_indices, %{}) do
      indices when is_map(indices) ->
        case Map.get(indices, macro) do
          idx when is_integer(idx) -> idx
          _ -> 0
        end

      _ ->
        0
    end
  end

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

  defp literal_string_arg(value) when is_binary(value) do
    case Process.get(:elmc_wasm_immortal_index) do
      %{} = index ->
        case Map.fetch(index, value) do
          {:ok, id} ->
            int_const(id)

          :error ->
            id = map_size(index)
            Process.put(:elmc_wasm_immortal_index, Map.put(index, value, id))

            strings = Process.get(:elmc_wasm_immortal_strings, [])
            Process.put(:elmc_wasm_immortal_strings, strings ++ [value])

            int_const(id)
        end

      _ ->
        int_const(:erlang.phash2(value, 1_000_000))
    end
  end

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
            {int_operand_wat(reg, slots, opts), []}

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
    # const_int / native ints live in i32 locals, but runtime builtins expect
    # boxed handles. Always box before tuple2/union use — even when the reg
    # already has a slot (previously we passed the raw tag i32 as a handle id).
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :const_int, args: %{value: value}} when is_integer(value) ->
        box_const_int_arg(value, reg, slots)

      %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
        box_const_int_arg(value, reg, slots)

      %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
        case resolve_c_expr_int(expr) do
          {:ok, value} -> box_const_int_arg(value, reg, slots)
          :error -> box_native_or_passthrough(reg, slots, opts)
        end

      _ ->
        box_native_or_passthrough(reg, slots, opts)
    end
  end

  defp box_native_or_passthrough(reg, slots, opts) do
    if native_int_reg?(opts, reg, MapSet.new()) do
      box_native_int_arg(reg, slots, opts)
    else
      {Slots.reg_name(slots, reg), []}
    end
  end

  defp box_const_int_arg(value, reg, slots) do
    offset = Map.fetch!(slots.reg_mem, reg)
    prep = box_const_int_prep(value, offset)
    {boxed_handle_at_offset(offset), prep}
  end

  defp box_native_int_arg(reg, slots, opts) do
    offset = Map.fetch!(slots.reg_mem, reg)
    prep = box_native_int_prep(reg, slots, offset, opts)
    {boxed_handle_at_offset(offset), prep}
  end

  defp box_const_int_prep(value, offset) do
    [
      WasmTypes.line(
        WasmTypes.sexpr("drop", [
          " ",
          WasmTypes.sexpr("call", [
            WasmTypes.import_ident("runtime.new_int"),
            " ",
            int_const(offset),
            " ",
            int_const(value)
          ])
        ])
      )
    ]
  end

  defp box_native_int_prep(reg, slots, offset, opts) do
    [
      WasmTypes.line(
        WasmTypes.sexpr("drop", [
          " ",
          WasmTypes.sexpr("call", [
            WasmTypes.import_ident("runtime.new_int"),
            " ",
            int_const(offset),
            " ",
            int_operand_wat(reg, slots, opts)
          ])
        ])
      )
    ]
  end

  defp raw_scalar_int_operand?(opts, reg, visited) do
    cond do
      not is_integer(reg) ->
        false

      MapSet.member?(visited, reg) ->
        false

      true ->
        visited = MapSet.put(visited, reg)

        case Keyword.get(opts, :parent_plan) do
          %FunctionPlan{} = plan ->
            instrs = CLowerFunction.all_defining_instrs(plan, reg)

            # Same rule as raw_native_int_fn_out_reg?: mixed multi-block defs
            # (raw const Ok arm + boxed tuple_proj Err arm) are not raw.
            instrs != [] and Enum.all?(instrs, &raw_scalar_defining_instr?(&1, opts, visited))

          _ ->
            false
        end
    end
  end

  defp raw_scalar_defining_instr?(instr, opts, visited) do
    case instr do
      %{op: :const_int} ->
        true

      # int_arith only stays raw when the dest is in native_int_only_regs.
      # Otherwise emit_int_arith boxes via new_int — treating the handle id as
      # an i32 made `1+10+100` become `handle(11)+100` (113) in probeCompare.
      %{op: :int_arith, dest: dest} when is_integer(dest) ->
        MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest)

      %{op: :compare, args: args} ->
        compare_produces_raw_scalar_int?(args, opts)

      %{op: :phi, args: %{native_int_phi: true}} ->
        true

      %{op: :phi, args: %{then: then_r, else: else_r}} ->
        raw_scalar_int_operand?(opts, then_r, visited) and
          raw_scalar_int_operand?(opts, else_r, visited)

      %{op: :load_param, args: %{index: index}} ->
        param_kinds = Keyword.get(opts, :param_kinds, [])
        Enum.at(param_kinds, index, :boxed) == :native_int

      _ ->
        false
    end
  end

  # Float payloads that plan may still feed to int_arith (Quantity unwrap, etc.).
  defp floatish_reg?(opts, reg, visited) do
    cond do
      not is_integer(reg) ->
        false

      MapSet.member?(visited, reg) ->
        false

      true ->
        visited = MapSet.put(visited, reg)

        case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
          %{op: :call_runtime, args: %{builtin: builtin}}
          when builtin in [:new_float, :basics_to_float, :basics_sqrt, :basics_abs] ->
            true

          %{op: :boxed_binop, args: %{op: op, mode: :float}}
          when op in [:add, :sub, :mul, :fdiv, :idiv] ->
            true

          %{op: :boxed_binop, args: %{op: op}} when op in [:add, :sub, :mul, :fdiv] ->
            true

          %{op: :tuple_proj} ->
            true

          %{op: :call_runtime, args: %{builtin: builtin}}
          when builtin in [:tuple_proj, :tuple_second, :tuple_first, :record_get] ->
            true

          %{op: :record_get} ->
            true

          %{op: :int_arith, args: args} ->
            lhs = Map.get(args, :lhs)
            rhs = Map.get(args, :rhs)

            (is_integer(lhs) and floatish_reg?(opts, lhs, visited)) or
              (is_integer(rhs) and floatish_reg?(opts, rhs, visited))

          _ ->
            false
        end
    end
  end

  defp boxed_handle_at_offset(offset) do
    WasmTypes.i32_load_offset(offset)
  end

  defp native_int_reg?(opts, reg, visited) do
    cond do
      not is_integer(reg) ->
        false

      MapSet.member?(visited, reg) ->
        false

      true ->
        _visited = MapSet.put(visited, reg)

        case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
          %{op: :const_int} ->
            true

          %{op: :int_arith, dest: dest} when is_integer(dest) ->
            MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest)

          %{op: :compare, args: args} ->
            compare_produces_raw_scalar_int?(args, opts)

          %{op: :phi, args: %{native_int_phi: true}} ->
            true

          # `:record_get_int` still lowers to boxed `runtime.record_get` on WASM
          # (no native-int import). Treating it as i32 causes `as_int` of Point
          # handles when a field name is misclassified (e.g. Svg.Arrow `.start`).

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
  end

  # String equality writes a boxed Int handle via runtime.string_equals. Callers
  # such as basics_not must pass that handle through — not re-box local.get as
  # new_int(handle_id), which made `item /= ""` always false for non-empty paths.
  defp compare_produces_raw_scalar_int?(args, opts) when is_map(args) do
    effective_compare_mode(args, opts) != :string
  end

  defp compare_produces_raw_scalar_int?(_, _), do: true

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
