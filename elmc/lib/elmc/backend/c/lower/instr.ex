defmodule Elmc.Backend.C.Lower.Instr do
  @moduledoc false

  alias Elmc.Backend.C.Lower.{Lambda, NativeReturn}
  alias Elmc.Backend.CCodegen.{FunctionCallAbi, FunctionEmit, RcRequired}
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types

  @rc_allocators_with_take ~w(
    elmc_new_int
    elmc_new_bool
    elmc_new_float
    elmc_new_string
    elmc_list_cons
    elmc_list_from_int_array
    elmc_list_from_float_array
    elmc_list_from_tuple2_int_array
    elmc_list_from_record_array
    elmc_list_from_values_take
    elmc_record_new
    elmc_record_new_take
    elmc_record_new_values_take
    elmc_record_new_values_ints
    elmc_record_new_static_take
    elmc_tuple2
    elmc_maybe_just_own
    elmc_result_ok_own
    elmc_result_err_own
    elmc_string_append
    elmc_string_from_native_int
    elmc_cmd0
    elmc_cmd1
    elmc_cmd1_string
    elmc_cmd2
  )

  @spec emit(Types.t(), %{optional(non_neg_integer()) => non_neg_integer()}, keyword()) ::
          String.t()
  def emit(%Types{op: op} = instr, slots, opts)
      when op in [:catch_begin, :catch_end, :publish, :load_param],
      do: emit_op_only(instr, slots, opts)

  def emit(%Types{op: :phi} = instr, slots, opts), do: emit_phi(instr, slots, opts)

  def emit(%Types{dest: dest} = instr, slots, opts) when is_integer(dest) do
    if MapSet.member?(instr_skip_regs(opts), dest) do
      ""
    else
      emit_instr(instr, slots, opts)
    end
  end

  defp instr_skip_regs(opts) do
    Keyword.get(opts, :fused_string_skip_regs, MapSet.new())
    |> MapSet.union(Keyword.get(opts, :tail_inline_skip_regs, MapSet.new()))
  end

  def emit(%Types{} = instr, slots, opts), do: emit_instr(instr, slots, opts)

  defp emit_instr(%Types{op: op} = instr, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    dest = format_dest(instr.dest, slots, opts)

    case op do
      :const_int ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest) do
          ""
        else
          rc_assign(rc?, dest, "elmc_new_int", [Integer.to_string(instr.args.value)])
        end

      :const_c_expr ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest) do
          ""
        else
          rc_assign(rc?, dest, "elmc_new_int", [Map.fetch!(instr.args, :value)])
        end

      :record_get_int ->
        emit_record_get_int(instr, slots, rc?, dest, opts)

      :const_static_list ->
        emit_const_static_list(instr, slots, dest, rc?, opts)

      :const_immortal_string ->
        escaped = Util.escape_c_string(instr.args.value)
        rc_assign(rc?, dest, "elmc_new_string", ["\"#{escaped}\""])

      :load_local ->
        src = slot_ref(instr.args.source, slots, opts)
        "#{dest} = #{src};"

      :call_runtime ->
        emit_call_runtime(instr, slots, rc?, dest, opts)

      :call_fn ->
        emit_call_fn(instr, slots, rc?, dest, opts)

      :call_closure ->
        emit_call_closure(instr, slots, rc?, dest, opts)

      :release ->
        if Keyword.get(opts, :epilogue_lifo, false), do: "", else: emit_release(instr, slots)

      :record_get ->
        base = slot_ref(instr.args.base, slots, opts)
        field = instr.args.field
        index = record_get_index_ref(field, Map.get(instr.args, :field_index, "0"))
        assign_value_return(rc?, dest, "elmc_record_get_index(#{base}, #{index})")

      :record_update ->
        base = slot_ref(instr.args.base, slots, opts)
        value = slot_ref(instr.args.value, slots, opts)
        index = Map.get(instr.args, :field_index, "0")

        assign =
          assign_value_return(
            rc?,
            dest,
            "elmc_record_update_index_cow_drop(#{base}, #{index}, #{value})"
          )

        alias_guard = cow_drop_alias_null(instr.dest, instr.args.base, slots, opts)

        [assign, alias_guard]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      :compare ->
        emit_compare(instr, slots, rc?, dest, opts)

      :int_arith ->
        if skip_inlined_int_dest?(instr.dest, opts) do
          ""
        else
          emit_int_arith(instr, slots, rc?, dest, opts)
        end

      :boxed_binop ->
        emit_boxed_binop(instr, slots, rc?, dest, opts)

      :test_maybe_nothing ->
        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          "elmc_maybe_is_nothing(#{subject})"
        end)

      :test_list_empty ->
        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          "elmc_as_bool(elmc_list_is_empty(#{subject}))"
        end)

      :test_ctor_tag ->
        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          tag = instr.args.tag
          "elmc_union_tag_matches(#{subject}, #{tag})"
        end)

      :bool_and ->
        emit_bool_and(instr, slots, rc?, dest, opts)

      :switch_ctor_tag ->
        emit_switch_ctor_tag(instr, slots, rc?, dest, opts)

      :pebble_cmd ->
        emit_pebble_cmd(instr, slots, rc?, dest, opts)

      :render_cmd ->
        emit_render_cmd(instr, slots, rc?, dest, opts)

      :render_text_cmd ->
        emit_render_text_cmd(instr, slots, rc?, dest, opts)

      :list_cursor_map ->
        emit_list_cursor_map(instr, slots, rc?, dest, opts)

      :pebble_sub ->
        emit_pebble_sub(instr, slots, rc?, dest, opts)

      :tuple_proj ->
        base = slot_ref(instr.args.base, slots, opts)

        call =
          case instr.args.which do
            :first -> "elmc_tuple_first(#{base})"
            :second -> "elmc_tuple_second(#{base})"
          end

        assign_value_return(rc?, dest, call)

      :make_closure ->
        emit_make_closure(instr, slots, opts, rc?, dest)

      :forward_ref_set ->
        emit_forward_ref_set(instr, slots, opts)

      :forward_ref_load ->
        emit_forward_ref_load(instr, slots, rc?, dest)

      :forward_ref_capture ->
        emit_forward_ref_capture(instr, slots, rc?, dest)

      :forward_ref_load_captured ->
        emit_forward_ref_load_captured(instr, slots, rc?, dest)

      :maybe_is_nothing ->
        "elmc_maybe_is_nothing(#{slot_ref(instr.args.reg, slots, opts)})"

      _ ->
        "/* plan op #{op} unlowered */"
    end
  end

  @doc false
  def branch_cond_expr(reg, slots, opts) when is_integer(reg), do: branch_cond_expr_impl(reg, slots, opts)

  defp branch_cond_expr_impl(reg, slots, opts) when is_integer(reg) do
    cond do
      MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) ->
        Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), reg)

      MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) ->
        int_operand_ref(reg, slots, opts)

      true ->
        "elmc_as_bool(#{slot_ref(reg, slots, opts)})"
    end
  end

  defp emit_phi(%{dest: dest_reg, args: args = %{then: then_reg, else: else_reg, cond: cond_reg}}, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    merge = format_dest(dest_reg, slots, opts)
    cond_expr = ternary_cond_expr(cond_reg, slots, opts)
    native_bool_cond? = MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), cond_reg)
    native_bool_dest? = MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg)

    cond do
      Map.get(args, :native_int_phi) == true and
          not MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) ->
        {then_s, else_s} = native_int_phi_arm_exprs(args, slots, opts)

        """
        if (#{cond_expr}) {
          #{rc_assign(rc?, merge, "elmc_new_int", [then_s])}
        } else {
          #{rc_assign(rc?, merge, "elmc_new_int", [else_s])}
        }
        """
        |> String.trim()

      MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) ->
        {then_s, else_s} =
          if Map.get(args, :native_int_phi) == true do
            native_int_phi_arm_exprs(args, slots, opts)
          else
            {int_operand_ref(then_reg, slots, opts), int_operand_ref(else_reg, slots, opts)}
          end

        emit_native_store(dest_reg, merge, "(#{cond_expr}) ? #{then_s} : #{else_s}", opts)

      native_bool_dest? ->
        {then_s, else_s} = phi_truthy_arm_exprs(args, then_reg, else_reg, slots, opts)
        emit_native_bool_store(dest_reg, merge, "(#{cond_expr}) ? #{then_s} : #{else_s}", opts)

      native_bool_cond? ->
        """
        if (#{cond_expr}) {
          #{phi_arm_assign(rc?, merge, then_reg, slots, opts)}
        } else {
          #{phi_arm_assign(rc?, merge, else_reg, slots, opts)}
        }
        """
        |> String.trim()

      true ->
        then_s = slot_ref(then_reg, slots, opts)
        else_s = slot_ref(else_reg, slots, opts)

        if rc? do
          """
          if (#{cond_expr}) {
            #{retain_into_owned(merge, then_s)}
          } else {
            #{retain_into_owned(merge, else_s)}
          }
          """
          |> String.trim()
        else
          """
          if (#{cond_expr}) {
            #{merge} = #{then_s};
          } else {
            #{merge} = #{else_s};
          }
          """
          |> String.trim()
        end
    end
  end

  defp phi_arm_assign(rc?, merge, reg, slots, opts) do
    src = slot_ref(reg, slots, opts)
    if rc?, do: retain_into_owned(merge, src), else: "#{merge} = #{src};"
  end

  defp native_int_phi_arm_exprs(args, slots, opts) do
    {
      native_int_phi_shape_c_expr(Map.fetch!(args, :then_shape), slots, opts),
      native_int_phi_shape_c_expr(Map.fetch!(args, :else_shape), slots, opts)
    }
  end

  defp native_int_phi_shape_c_expr({:const_int, value}, _slots, _opts), do: Integer.to_string(value)

  defp native_int_phi_shape_c_expr({:new_int, value}, _slots, _opts) when is_integer(value),
    do: Integer.to_string(value)

  defp native_int_phi_shape_c_expr({:new_int, expr}, _slots, _opts) when is_binary(expr), do: expr

  defp native_int_phi_shape_c_expr({:int_arith, args}, slots, opts),
    do: Elmc.Backend.C.Lower.NativeIntFold.int_arith_c_expr(args, slots, opts) || "0"

  defp native_int_phi_shape_c_expr(_shape, _slots, _opts), do: "0"

  defp phi_truthy_arm_exprs(args, then_reg, else_reg, slots, opts) do
    if Map.get(args, :truthy_native) == true do
      {truthy_shape_c_expr(Map.fetch!(args, :then_shape), slots, opts),
       truthy_shape_c_expr(Map.fetch!(args, :else_shape), slots, opts)}
    else
      {phi_truthy_arm_expr(then_reg, slots, opts), phi_truthy_arm_expr(else_reg, slots, opts)}
    end
  end

  defp truthy_shape_c_expr({:const_int, 0}, _slots, _opts), do: "false"
  defp truthy_shape_c_expr({:const_int, 1}, _slots, _opts), do: "true"

  defp truthy_shape_c_expr({:compare, kind, left, right}, slots, opts) do
    compare_native_c_expr(
      kind,
      int_operand_ref(left, slots, opts),
      int_operand_ref(right, slots, opts)
    )
  end

  defp truthy_shape_c_expr({:reg, reg}, slots, opts) when is_integer(reg) do
    branch_cond_expr_impl(reg, slots, opts)
  end

  defp phi_truthy_arm_expr(reg, slots, opts) when is_integer(reg) do
    native_bool_regs = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    const_int_regs = Keyword.get(opts, :const_int_regs, %{})
    native_int_regs = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    cond do
      MapSet.member?(native_bool_regs, reg) ->
        branch_cond_expr_impl(reg, slots, opts)

      Map.has_key?(const_int_regs, reg) ->
        case Map.fetch!(const_int_regs, reg) do
          0 -> "false"
          1 -> "true"
          v -> "(#{v} != 0)"
        end

      MapSet.member?(native_int_regs, reg) ->
        "#{int_operand_ref(reg, slots, opts)} != 0"

      true ->
        case plan_defining_instr(Keyword.get(opts, :parent_plan), reg) do
          %{op: :compare, args: args} ->
            compare_native_c_expr(
              Map.get(args, :kind, :eq),
              int_operand_ref(Map.fetch!(args, :left), slots, opts),
              int_operand_ref(Map.fetch!(args, :right), slots, opts)
            )

          %{op: :call_runtime, args: %{builtin: :new_bool, literal: value}} when value in [0, 1] ->
            if(value == 1, do: "true", else: "false")

          %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when value in [0, 1] ->
            if(value == 1, do: "true", else: "false")

          _ ->
            truthy_expr(reg, slots, opts)
        end
    end
  end

  defp plan_defining_instr(%{blocks: blocks}, reg) when is_integer(reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.find(fn %{dest: dest} -> dest == reg end)
  end

  defp plan_defining_instr(_, _), do: nil

  defp truthy_expr(reg, slots, opts) when is_integer(reg) do
    cond do
      MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) ->
        branch_cond_expr_impl(reg, slots, opts)

      MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) ->
        "(#{int_operand_ref(reg, slots, opts)} != 0)"

      true ->
        "elmc_as_bool(#{slot_ref(reg, slots, opts)})"
    end
  end

  defp ternary_cond_expr(reg, slots, opts) when is_integer(reg) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) and
         not MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) do
      "#{int_operand_ref(reg, slots, opts)} != 0"
    else
      branch_cond_expr_impl(reg, slots, opts)
    end
  end

  defp emit_compare(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    left = int_operand_ref(args.left, slots, opts)
    right = int_operand_ref(args.right, slots, opts)

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      cmp = compare_native_c_expr(args.kind, left, right)
      emit_native_bool_store(dest_reg, dest, cmp, opts)
    else
      cmp = compare_c_expr(args.kind, left, right)
      rc_assign(rc?, dest, "elmc_new_bool", [cmp])
    end
  end

  defp emit_bool_and(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    left = truthy_expr(args.left, slots, opts)
    right = truthy_expr(args.right, slots, opts)
    expr = "(#{left} && #{right})"

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      emit_native_bool_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", ["#{expr} ? 1 : 0"])
    end
  end

  defp emit_native_bool_test(%{dest: dest_reg, args: args}, slots, rc?, dest, opts, subject_expr) do
    subject =
      case args do
        %{reg: reg} -> slot_ref(reg, slots, opts)
        %{subject: reg} -> slot_ref(reg, slots, opts)
      end

    expr = subject_expr.(subject)

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      emit_native_bool_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", ["#{expr} ? 1 : 0"])
    end
  end

  defp emit_native_bool_store(dest_reg, _dest, expr, opts) do
    name = Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), dest_reg)

    if MapSet.member?(Keyword.get(opts, :native_bool_mutable_regs, MapSet.new()), dest_reg) do
      "#{name} = #{expr};"
    else
      "const bool #{name} = #{expr};"
    end
  end

  defp compare_native_c_expr(:eq, left, right), do: "(#{left} == #{right})"
  defp compare_native_c_expr(:neq, left, right), do: "(#{left} != #{right})"
  defp compare_native_c_expr(:gt, left, right), do: "(#{left} > #{right})"
  defp compare_native_c_expr(:gte, left, right), do: "(#{left} >= #{right})"
  defp compare_native_c_expr(:lt, left, right), do: "(#{left} < #{right})"
  defp compare_native_c_expr(:lte, left, right), do: "(#{left} <= #{right})"
  defp compare_native_c_expr(_, left, right), do: "(#{left} == #{right})"

  defp compare_c_expr(:eq, left, right), do: "(#{left} == #{right}) ? 1 : 0"
  defp compare_c_expr(:neq, left, right), do: "(#{left} != #{right}) ? 1 : 0"
  defp compare_c_expr(:gt, left, right), do: "(#{left} > #{right}) ? 1 : 0"
  defp compare_c_expr(:gte, left, right), do: "(#{left} >= #{right}) ? 1 : 0"
  defp compare_c_expr(:lt, left, right), do: "(#{left} < #{right}) ? 1 : 0"
  defp compare_c_expr(:lte, left, right), do: "(#{left} <= #{right}) ? 1 : 0"
  defp compare_c_expr(_, left, right), do: "(#{left} == #{right}) ? 1 : 0"

  defp emit_switch_ctor_tag(%{dest: dest_reg, args: args}, slots, rc?, merge, opts) do
    subject = slot_ref(args.subject, slots, opts)
    native? = MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg)

    arm_lines =
      Enum.map(args.arms, fn %{tag: tag, reg: reg} ->
        cond_line = "if (elmc_union_tag_matches(#{subject}, #{tag}))"

        body =
          if native? do
            src = int_operand_ref(reg, slots, opts)
            emit_native_store(dest_reg, merge, src, opts)
          else
            src = slot_ref(reg, slots, opts)

            if rc? do
              retain_into_owned(merge, src)
            else
              "#{merge} = #{src};"
            end
          end

        "#{cond_line} {\n  #{body}\n}"
      end)

    default_line =
      case Map.get(args, :default) do
        reg when is_integer(reg) ->
          body =
            if native? do
              src = int_operand_ref(reg, slots, opts)
              emit_native_store(dest_reg, merge, src, opts)
            else
              src = slot_ref(reg, slots, opts)

              if rc? do
                retain_into_owned(merge, src)
              else
                "#{merge} = #{src};"
              end
            end

          "else {\n  #{body}\n}"

        _ ->
          ""
      end

    chain =
      case {arm_lines, default_line} do
        {[], ""} ->
          ""

        {arms, ""} ->
          Enum.join(arms, " else ")

        {arms, def} ->
          Enum.join(arms, " else ") <> " " <> def
      end

    chain |> String.trim()
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :min_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "(#{lhs_s} <= #{rhs_s}) ? #{lhs_s} : #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :max_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "(#{lhs_s} >= #{rhs_s}) ? #{lhs_s} : #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :add_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} + #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :mul_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} * #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :sub_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} - #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :idiv_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "(#{rhs_s} == 0 ? 0 : #{lhs_s} / #{rhs_s})", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :mod_vars, lhs: base, rhs: value}}, slots, rc?, dest, opts) do
    base_s = int_operand_ref(base, slots, opts)
    value_s = int_operand_ref(value, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, elm_mod_by_c_expr(base_s, value_s), opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :rem_vars, lhs: base, rhs: value}}, slots, rc?, dest, opts) do
    base_s = int_operand_ref(base, slots, opts)
    value_s = int_operand_ref(value, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "(#{base_s} == 0 ? 0 : #{value_s} % #{base_s})", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :add_const, lhs: lhs, value: value}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} + #{value}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :sub_const, lhs: lhs, value: value}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} - #{value}", opts)
  end

  defp emit_int_arith(_, _slots, _rc?, _dest, _opts), do: "/* int_arith unlowered */"

  defp emit_int_result_assign(dest_reg, dest, _rc?, expr, opts) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(Keyword.get(opts, :rc_required, true), dest, "elmc_new_int", [expr])
    end
  end

  defp emit_native_store(dest_reg, dest, expr, opts) do
    if MapSet.member?(Keyword.get(opts, :native_int_mutable_regs, MapSet.new()), dest_reg) or
         Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), dest_reg) do
      "#{dest} = #{expr};"
    else
      "const elmc_int_t #{dest} = #{expr};"
    end
  end

  defp emit_record_get_int(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    base = slot_ref(args.base, slots, opts)
    field = args.field
    index = record_get_index_ref(field, Map.get(args, :field_index, "0"))
    expr = "ELMC_RECORD_GET_INDEX_INT(#{base}, #{index})"

    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", [expr])
    end
  end

  defp emit_boxed_binop(%{dest: dest_reg, args: %{op: op, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    if native_int_binop_operands?(lhs, rhs, opts) do
      op_sym =
        case op do
          :add -> "+"
          :sub -> "-"
          :mul -> "*"
          :idiv -> "/"
          :fdiv -> "/"
          other -> raise ArgumentError, "unknown boxed_binop #{inspect(other)}"
        end

      left = int_operand_ref(lhs, slots, opts)
      right = int_operand_ref(rhs, slots, opts)
      emit_int_result_assign(dest_reg, dest, rc?, "#{left} #{op_sym} #{right}", opts)
    else
      emit_boxed_binop_dynamic(op, lhs, rhs, slots, rc?, dest, opts)
    end
  end

  defp emit_boxed_binop_dynamic(op, lhs, rhs, slots, rc?, dest, opts) do
    op_sym =
      case op do
        :add -> "+"
        :sub -> "-"
        :mul -> "*"
        :idiv -> "/"
        :fdiv -> "/"
        other -> raise ArgumentError, "unknown boxed_binop #{inspect(other)}"
      end

    left = slot_ref(lhs, slots, opts)
    right = slot_ref(rhs, slots, opts)

    float_expr = "elmc_as_float(#{left}) #{op_sym} elmc_as_float(#{right})"
    int_expr = "elmc_as_int(#{left}) #{op_sym} elmc_as_int(#{right})"

    """
    if (((#{left}) && (#{left})->tag == ELMC_TAG_FLOAT) || ((#{right}) && (#{right})->tag == ELMC_TAG_FLOAT)) {
      #{rc_assign(rc?, dest, "elmc_new_float", [float_expr])}
    } else {
      #{rc_assign(rc?, dest, "elmc_new_int", [int_expr])}
    }
    """
    |> String.trim()
  end

  defp native_int_binop_operands?(lhs, rhs, opts) when is_integer(lhs) and is_integer(rhs) do
    native_int_operand_reg?(lhs, opts) and native_int_operand_reg?(rhs, opts)
  end

  defp native_int_binop_operands?(_, _, _), do: false

  defp native_int_operand_reg?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), reg)
  end

  defp float_literal_c(value) when is_integer(value), do: "#{value}.0"
  defp float_literal_c(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])

  defp emit_call_runtime(%{args: %{builtin: :list_repeat, args: [count, value]}}, slots, rc?, dest, opts)
       when is_integer(count) and is_integer(value) do
    value_s = slot_ref(value, slots, opts)

    if native_int_repeat_count?(count, opts) do
      count_s = int_operand_ref(count, slots, opts)
      rc_assign(rc?, dest, "elmc_list_repeat_count", [count_s, value_s])
    else
      count_s = slot_ref(count, slots, opts)
      rc_assign(rc?, dest, "elmc_list_repeat", [count_s, value_s])
    end
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :record_new_values_ints, args: args}}, slots, rc?, dest, opts)
       when is_list(args) do
    suffix = record_new_suffix(dest_reg)
    count = length(args)

    values_s =
      args
      |> Enum.map_join(", ", &int_operand_ref(&1, slots, opts))

    values_decl = "elmc_int_t rec_values_#{suffix}[#{max(count, 1)}] = { #{values_s} };"

    """
    #{values_decl}
    #{rc_assign(rc?, dest, "elmc_record_new_values_ints", [Integer.to_string(count), "rec_values_#{suffix}"])}
    """
    |> String.trim()
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: id, args: args} = args_map}, slots, rc?, dest, opts)
       when id in [:record_new, :record_new_take] and is_list(args) do
    shape = Map.get(args_map, :shape)
    module = Keyword.get(opts, :module)

    field_names =
      case Map.get(args_map, :field_names) do
        names when is_list(names) and names != [] ->
          names

        _ ->
          resolve_record_field_names(shape, length(args), module)
      end
    suffix = record_new_suffix(dest_reg)
    count = length(args)
    values_array = record_values_array(args, slots, opts)
    values_decl = "ElmcValue *rec_values_#{suffix}[#{max(count, 1)}] = { #{values_array} };"

    use_named? =
      Process.get(:elmc_named_record_literals, false) and is_list(field_names) and field_names != []

    {names_decl, sym, call_args} =
      if use_named? do
        names_array =
          field_names
          |> Enum.map_join(", ", fn name -> "\"#{Util.escape_c_string(to_string(name))}\"" end)

        {
          "const char *rec_names_#{suffix}[#{max(count, 1)}] = { #{names_array} };",
          "elmc_record_new_static_take",
          ["#{count}", "rec_names_#{suffix}", "rec_values_#{suffix}"]
        }
      else
        {"", "elmc_record_new_values_take", ["#{count}", "rec_values_#{suffix}"]}
      end

    """
    #{names_decl}
    #{values_decl}
    #{rc_assign(rc?, dest, sym, call_args)}
    """
    |> String.trim()
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :retain, args: [src]}}, slots, rc?, dest, opts)
       when is_integer(src) and is_integer(dest_reg) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      src_expr = int_operand_ref(src, slots, opts)
      emit_native_store(dest_reg, dest, src_expr, opts)
    else
      sym = RuntimeBuiltins.c_symbol(:retain)
      src_s = slot_ref(src, slots, opts)
      assign_value_return(rc?, dest, "#{sym}(#{src_s})")
    end
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :string_append, args: args}}, slots, rc?, dest, opts)
       when is_integer(dest_reg) and is_list(args) do
    case Map.get(Keyword.get(opts, :fused_string_roots, %{}), dest_reg) do
      segments when is_list(segments) ->
        Elmc.Backend.C.Lower.StringConcat.emit(segments, dest, rc?, opts)

      _ ->
        sym = RuntimeBuiltins.c_symbol(:string_append)
        c_args = Enum.map(args, &slot_ref(&1, slots, opts))
        rc_assign(rc?, dest, sym, c_args)
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :new_int, literal: value}}, _slots, rc?, dest, _opts)
       when is_integer(value) do
    rc_assign(rc?, dest, "elmc_new_int", [Integer.to_string(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_float, literal: value}}, _slots, rc?, dest, _opts)
       when is_number(value) do
    rc_assign(rc?, dest, "elmc_new_float", [float_literal_c(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_int, c_expr: expr}}, _slots, rc?, dest, _opts)
       when is_binary(expr) do
    rc_assign(rc?, dest, "elmc_new_int", [expr])
  end

  defp emit_call_runtime(%{args: %{builtin: :unit, args: []}}, _slots, rc?, dest, _opts) do
    assign_value_return(rc?, dest, "elmc_unit()")
  end

  defp emit_call_runtime(%{args: %{builtin: :string_from_int, args: [arg]}}, slots, rc?, dest, opts) do
    sym = RuntimeBuiltins.c_symbol(:string_from_int)
    native = int_operand_ref(arg, slots, opts)
    rc_assign(rc?, dest, sym, [native])
  end

  defp emit_call_runtime(%{args: %{builtin: :tuple2, args: args}}, slots, rc?, dest, opts) do
    c_args = Enum.map(args, &boxed_value_ref(&1, slots, opts))

    if rc? do
      rc_assign(true, dest, "elmc_tuple2", c_args)
    else
      assign_owned(false, dest, "elmc_tuple2_take_value(#{Enum.join(c_args, ", ")})")
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :tuple2_take, args: args}}, slots, rc?, dest, opts) do
    c_args = Enum.map(args, &slot_ref(&1, slots, opts))

    if rc? do
      rc_assign(true, dest, "elmc_tuple2_take", c_args)
    else
      assign_owned(false, dest, "elmc_tuple2_take_value(#{Enum.join(c_args, ", ")})")
    end
  end

  defp emit_call_runtime(%{dest: dest_reg, args: %{builtin: :int_list_head_int, args: [list]}}, slots, rc?, dest, opts)
       when is_integer(list) do
    list_ref = slot_ref(list, slots, opts)

    expr =
      "elmc_list_head_with_default_int(0, #{list_ref})"

    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", [expr])
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :tuple2_ints, args: args}}, slots, rc?, dest, opts) do
    left = int_operand_ref(Enum.at(args, 0), slots, opts)
    right = int_operand_ref(Enum.at(args, 1), slots, opts)

    if rc? do
      rc_assign(true, dest, "elmc_tuple2_ints", [left, right])
    else
      assign_owned(false, dest, "elmc_tuple2_ints_take_value(#{left}, #{right})")
    end
  end

  defp emit_call_runtime(%{args: %{builtin: id, args: args}}, slots, rc?, dest, opts) do
    sym = RuntimeBuiltins.c_symbol(id) || "elmc_unknown"

    c_args =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        if RuntimeBuiltins.native_int_arg?(id, index) do
          int_operand_ref(arg, slots, opts)
        else
          slot_ref(arg, slots, opts)
        end
      end)

    call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"

    cond do
      RuntimeBuiltins.direct_value_return?(id) ->
        assign_value_return(rc?, dest, call_expr)

      RuntimeBuiltins.c_value_return?(id) and not rc? ->
        sym = non_rc_value_return_symbol(sym)
        call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"
        assign_owned(false, dest, call_expr)

      RuntimeBuiltins.c_value_return?(id) ->
        assign_owned(rc?, dest, call_expr)

      RuntimeBuiltins.value_return?(id) ->
        assign_owned(rc?, dest, call_expr)

      true ->
        rc_assign(rc?, dest, sym, c_args)
    end
  end

  defp emit_release(%{args: %{reg: reg}}, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "elmc_release(owned[#{i}]);\nowned[#{i}] = NULL;"
      _ -> ""
    end
  end

  defp emit_release(_, _), do: ""

  defp emit_call_closure(%{args: %{callee: callee, args: args}}, slots, true, dest, opts) do
    callee_s = slot_ref(callee, slots, opts)
    c_args = Enum.map(args, &slot_ref(&1, slots, opts))
    argc = length(c_args)
    args_var = "plan_closure_argv_#{System.unique_integer([:positive])}"
    dest_ptr = if dest == "*out", do: "out", else: dest

    """
    ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{Enum.join(c_args, ", ")} };
    Rc = elmc_closure_call_rc(#{if(dest == "*out", do: "&out", else: "&#{dest_ptr}")}, #{callee_s}, #{args_var}, #{argc});
    CHECK_RC(Rc);
    """
    |> String.trim()
  end

  defp emit_call_closure(%{args: %{callee: callee, args: args}}, slots, false, dest, opts) do
    callee_s = slot_ref(callee, slots, opts)
    c_args = Enum.map(args, &slot_ref(&1, slots, opts))
    argc = length(c_args)
    args_var = "plan_closure_argv_#{System.unique_integer([:positive])}"

    """
    ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{Enum.join(c_args, ", ")} };
    #{dest} = elmc_closure_call(#{callee_s}, #{args_var}, #{argc});
    """
    |> String.trim()
  end

  defp emit_call_fn(%{dest: dest_reg, args: %{module: mod, name: name, args: args}}, slots, rc?, dest, opts) do
    c_name = Util.module_fn_name(mod, name)
    dest_ref = if dest == "*out", do: "out", else: dest
    decl_map = Process.get(:elmc_program_decls, %{})
    decl = Map.get(decl_map, {mod, name})
    native_ret = NativeReturn.cached_kind({mod, name})

    {prefix, call_arg_s} =
      cond do
        native_ret in [:native_int, :native_bool] and decl ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          c_args = call_arg_refs(args, slots, opts, kinds)
          {"", Enum.join(c_args, ", ")}

        native_ret == :native_int ->
          c_args = Enum.map(args, &int_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", ")}

        native_ret == :native_bool ->
          c_args = Enum.map(args, &bool_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", ")}

        decl && FunctionCallAbi.argv_abi?(decl, mod, decl_map) ->
          c_args = Enum.map(args, &slot_ref(&1, slots, opts))
          {setup, args_var, argc} = FunctionCallAbi.emit_argv_setup("plan", c_args)
          {setup <> "\n", "#{args_var}, #{argc}"}

        decl && FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map) &&
            FunctionEmit.mixed_direct_abi?(decl, mod, decl_map) ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          c_args = call_arg_refs(args, slots, opts, kinds)
          {"", Enum.join(c_args, ", ")}

        true ->
          c_args = Enum.map(args, &slot_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", ")}
      end

    prefix <>
      emit_fn_call(rc?, dest, dest_ref, dest_reg, c_name, call_arg_s, {mod, name}, native_ret, opts)
  end

  defp call_arg_refs(args, slots, opts, kinds) do
    args
    |> Enum.zip(kinds)
    |> Enum.map(fn {arg_reg, kind} ->
      case kind do
        :native_int -> int_operand_ref(arg_reg, slots, opts)
        :native_bool -> bool_operand_ref(arg_reg, slots, opts)
        _ -> slot_ref(arg_reg, slots, opts)
      end
    end)
  end

  defp emit_fn_call(true, dest, _dest_ref, dest_reg, c_name, call_arg_s, {mod, name} = callee, native_ret, opts) do
    cond do
      native_ret in [:native_int, :native_bool] ->
        emit_native_scalar_fn_call(native_ret, true, dest, dest_reg, c_name, call_arg_s, opts, callee)

      RcRequired.rc_required?(mod, name) ->
        rc_call(true, if(dest == "*out", do: "out", else: dest), c_name, call_arg_s)

      true ->
        "#{dest} = #{c_name}(#{call_arg_s});"
    end
  end

  defp emit_fn_call(false, dest, dest_ref, dest_reg, c_name, call_arg_s, {mod, name} = callee, native_ret, opts) do
    cond do
      native_ret in [:native_int, :native_bool] ->
        emit_native_scalar_fn_call(native_ret, false, dest, dest_reg, c_name, call_arg_s, opts, callee)

      RcRequired.rc_required?(mod, name) ->
        rc_callee_from_value_return(dest, dest_ref, c_name, call_arg_s)

      true ->
        "#{dest} = #{c_name}(#{call_arg_s});"
    end
  end

  defp emit_native_scalar_fn_call(:native_int, rc?, dest, dest_reg, c_name, call_arg_s, opts, callee) do
    value_return? = NativeReturn.value_return?(callee)
    native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    cond do
      value_return? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        "plan_native_int_#{dest_reg} = #{c_name}(#{call_arg_s});"

      value_return? and dest == "*out" ->
        "return #{c_name}(#{call_arg_s});"

      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        out = "plan_native_int_#{dest_reg}"
        "Rc = #{c_name}(&#{out}, #{call_arg_s});\nCHECK_RC(Rc);"

      true ->
        emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s)
    end
  end

  defp emit_native_scalar_fn_call(:native_bool, rc?, dest, dest_reg, c_name, call_arg_s, opts, callee) do
    value_return? = NativeReturn.value_return?(callee)
    native_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())

    cond do
      value_return? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        "plan_native_bool_#{dest_reg} = #{c_name}(#{call_arg_s});"

      value_return? and dest == "*out" ->
        "return #{c_name}(#{call_arg_s});"

      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        out = "plan_native_bool_#{dest_reg}"
        "Rc = #{c_name}(&#{out}, #{call_arg_s});\nCHECK_RC(Rc);"

      true ->
        emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s)
    end
  end

  defp emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s) do
    tmp = "plan_call_int_#{dest_reg}"
    box_dest = if dest == "*out", do: "out", else: dest

    """
    elmc_int_t #{tmp};
    Rc = #{c_name}(&#{tmp}, #{call_arg_s});
    CHECK_RC(Rc);
    #{rc_assign(rc?, box_dest, "elmc_new_int", [tmp])}
    """
    |> String.trim()
  end

  defp emit_pebble_cmd(%{args: %{builtin: id, kind: kind, params: params}}, slots, rc?, dest, opts) do
    sym = RuntimeBuiltins.c_symbol(id) || "elmc_cmd0"
    kind_s = Map.get(kind, :c_expr, "0")
    args = Enum.join([kind_s | native_int_param_refs(params, slots, opts)], ", ")
    rc_call(rc?, if(dest == "*out", do: "out", else: dest), sym, args)
  end

  defp emit_render_cmd(%{args: %{kind: kind, params: params} = args}, slots, rc?, dest, opts) do
    if Map.get(args, :direct_scene_push) == true and Keyword.get(opts, :direct_scene_writer) do
      emit_render_cmd_scene_push(kind, params, slots, opts)
    else
      emit_render_cmd_boxed(kind, params, slots, rc?, dest, opts)
    end
  end

  defp emit_render_cmd_boxed(kind, params, slots, rc?, dest, opts) do
    kind_s = platform_kind_c(kind)
    args = Enum.join([kind_s | padded_param_refs(params, 6, slots, opts)], ", ")
    dest_ref = if dest == "*out", do: "out", else: dest
    rc_call(rc?, dest_ref, "elmc_render_cmd6_take", args)
  end

  defp emit_render_text_cmd(%{args: %{kind: kind, params: params, text: text}}, slots, rc?, dest, opts) do
    kind_s = platform_kind_c(kind)
    int_args = Enum.map(params, &int_operand_ref(&1, slots, opts))
    text_ref = slot_ref(text, slots, opts)
    dest_ref = if dest == "*out", do: "out", else: dest
    args = Enum.join([kind_s | int_args ++ [text_ref]], ", ")
    rc_call(rc?, dest_ref, "elmc_render_text_cmd_take", args)
  end

  defp emit_render_text_cmd(_, _slots, _rc?, _dest, _opts), do: ""

  defp emit_render_cmd_scene_push(kind, params, slots, opts) do
    kind_s = platform_kind_c(kind)
    param_lines = padded_param_refs(params, 6, slots, opts)

    assignments =
      param_lines
      |> Enum.with_index()
      |> Enum.map_join("\n  ", fn {value, index} -> "scene_cmd.p#{index} = #{value};" end)

    writer = Keyword.get(opts, :scene_writer_var, "writer")

    """
    elmc_draw_cmd_init(&scene_cmd, #{kind_s});
    #{assignments}
    if (elmc_scene_writer_push_cmd(#{writer}, &scene_cmd) != 0) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    """
    |> String.trim()
  end

  defp emit_list_cursor_map(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    start_s =
      if Map.get(args, :start_literal?) do
        Integer.to_string(args.start)
      else
        int_operand_ref(args.start, slots, opts)
      end

    end_s =
      if Map.get(args, :end_literal?) do
        Integer.to_string(args.end)
      else
        int_operand_ref(args.end, slots, opts)
      end

    loop_id = Map.get(args, :lambda_idx, 0)
    parent = Keyword.get(opts, :parent_plan)
    closure = Elmc.Backend.C.Lower.Lambda.closure_fn_name(parent, loop_id)
    fwd_head = "list_map_cursor_head_#{loop_id}"
    item = "list_map_cursor_item_#{loop_id}"
    idx = "list_map_cursor_i_#{loop_id}"
    dest_slot = format_dest(dest_reg, slots, opts)

    body = """
    ElmcValue *#{fwd_head} = elmc_int_zero();
    for (elmc_int_t #{idx} = #{start_s}; #{idx} <= #{end_s}; #{idx}++) {
      ElmcValue *#{item} = NULL;
      ElmcValue *loop_args[1];
      Rc = elmc_new_int(&loop_args[0], #{idx});
      CHECK_RC(Rc);
      Rc = #{closure}(&#{item}, loop_args, 1, NULL, 0);
      CHECK_RC(Rc);
      elmc_release(loop_args[0]);
      {
        ElmcValue *next = NULL;
        Rc = elmc_list_append(&next, #{fwd_head}, #{item});
        CHECK_RC(Rc);
        #{fwd_head} = next;
        #{item} = NULL;
      }
    }
    """

    if rc? and dest != "*out" do
      body <> "\n#{retain_into_owned(dest_slot, fwd_head)}"
    else
      body <> "\n#{dest_slot} = #{fwd_head};"
    end
  end

  defp emit_pebble_sub(%{args: %{kind: mask, params: params}}, slots, rc?, dest, opts) do
    mask_s = platform_kind_c(mask)
    arity = length(params)
    fn_name = "elmc_sub#{arity}"
    args = Enum.join([mask_s | native_int_param_refs(params, slots, opts)], ", ")
    rc_call(rc?, if(dest == "*out", do: "out", else: dest), fn_name, args)
  end

  defp platform_kind_c(%{c_expr: value}) when is_binary(value), do: value
  defp platform_kind_c(%{literal: value}) when is_integer(value), do: Integer.to_string(value)
  defp platform_kind_c(_), do: "0"

  defp padded_param_refs(params, n, slots, opts) do
    refs = native_int_param_refs(params, slots, opts)
    refs ++ List.duplicate("0", max(0, n - length(refs)))
  end

  defp native_int_param_refs(params, slots, opts) do
    Enum.map(params, fn reg -> int_operand_ref(reg, slots, opts) end)
  end

  @doc false
  def int_operand_ref(reg, slots, opts) when is_integer(reg), do: int_operand_ref_impl(reg, slots, opts)

  defp int_operand_ref_impl(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :native_int_inline, %{}), reg) do
      expr when is_binary(expr) ->
        expr

      nil ->
        case Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) do
          name when is_binary(name) ->
            name

          nil ->
            case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
              value when is_integer(value) ->
                Integer.to_string(value)

              nil ->
                if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
                  "plan_native_int_#{reg}"
                else
                  "elmc_as_int(#{slot_ref(reg, slots, opts)})"
                end
            end
        end
    end
  end

  defp boxed_value_ref(reg, slots, opts) when is_integer(reg) do
    case tail_inline_take_expr(reg, slots, opts) do
      expr when is_binary(expr) ->
        expr

      nil ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
          "elmc_new_int_take(#{int_operand_ref(reg, slots, opts)})"
        else
          slot_ref(reg, slots, opts)
        end
    end
  end

  defp tail_inline_take_expr(reg, slots, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :const_int, args: %{value: value}} when is_integer(value) ->
        "elmc_new_int_take(#{value})"

      %{args: %{builtin: :tuple2_ints, args: [left, right]}} ->
        "elmc_tuple2_ints_take_value(#{int_operand_ref(left, slots, opts)}, #{int_operand_ref(right, slots, opts)})"

      %{args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
        "elmc_new_int_take(#{value})"

      _ ->
        nil
    end
  end

  defp defining_plan_instr(%{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp defining_plan_instr(_, _), do: nil

  defp skip_inlined_int_dest?(dest_reg, opts) when is_integer(dest_reg) do
    Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), dest_reg)
  end

  defp skip_inlined_int_dest?(_, _), do: false

  defp bool_operand_ref(reg, slots, opts) when is_integer(reg) do
    ref = slot_ref(reg, slots, opts)
    "elmc_as_bool(#{ref})"
  end

  defp native_int_direct_regs(opts), do: Keyword.get(opts, :native_int_regs, %{})

  defp non_rc_value_return_symbol("elmc_tuple2_take"), do: "elmc_tuple2_take_value"
  defp non_rc_value_return_symbol("elmc_tuple2_ints"), do: "elmc_tuple2_ints_take_value"
  defp non_rc_value_return_symbol(sym), do: sym

  defp emit_const_static_list(%{args: %{kind: kind} = args}, slots, dest, rc?, opts) do
    values_id = System.unique_integer([:positive])

    case kind do
      :int_array ->
        values = Map.fetch!(args, :values)
        count = length(values)
        values_name = "plan_list_int_values_#{values_id}"

        values_s =
          values
          |> Enum.map(&Integer.to_string/1)
          |> Enum.join(", ")

        decl = "static const elmc_int_t #{values_name}[#{count}] = { #{values_s} };"
        call = rc_assign(rc?, dest, "elmc_list_from_int_array", [values_name, Integer.to_string(count)])
        decl <> "\n" <> call

      :float_array ->
        values = Map.fetch!(args, :values)
        count = length(values)
        values_name = "plan_list_float_values_#{values_id}"

        values_s =
          values
          |> Enum.map(&float_literal_c/1)
          |> Enum.join(", ")

        decl = "static const double #{values_name}[#{count}] = { #{values_s} };"
        call = rc_assign(rc?, dest, "elmc_list_from_float_array", [values_name, Integer.to_string(count)])
        decl <> "\n" <> call

      :tuple2_int_array ->
        pairs = Map.fetch!(args, :pairs)
        count = length(pairs)
        values_name = "plan_list_tuple2_values_#{values_id}"

        values_s =
          pairs
          |> Enum.map(fn {left, right} -> "{ #{left}, #{right} }" end)
          |> Enum.join(", ")

        decl = "static const elmc_int_t #{values_name}[#{count}][2] = { #{values_s} };"
        call = rc_assign(rc?, dest, "elmc_list_from_tuple2_int_array", [values_name, Integer.to_string(count)])
        decl <> "\n" <> call

      :values ->
        emit_const_static_list_from_regs(args, slots, dest, rc?, values_id, "plan_list_items", "elmc_list_from_values_take", opts)

      :record_array ->
        emit_const_static_list_from_regs(
          args,
          slots,
          dest,
          rc?,
          values_id,
          "plan_list_record_items",
          "elmc_list_from_record_array",
          opts
        )
    end
  end

  defp emit_const_static_list_from_regs(args, slots, dest, rc?, values_id, prefix, callee, opts) do
    regs = Map.fetch!(args, :regs)
    count = length(regs)
    array_name = "#{prefix}_#{values_id}"
    refs = Enum.map_join(regs, ", ", &slot_ref(&1, slots, opts))

    """
    ElmcValue *#{array_name}[#{count}] = { #{refs} };
    #{rc_assign(rc?, dest, callee, [array_name, Integer.to_string(count)])}
    """
    |> String.trim()
  end

  defp rc_assign(true, dest, fn_name, args) do
    dest_ref = if String.starts_with?(dest, "*"), do: "out", else: dest
    call_args = format_call_args(dest_arg(dest_ref, dest), Enum.join(args, ", "))
    "Rc = #{fn_name}(#{call_args});\nCHECK_RC(Rc);"
  end

  defp rc_assign(false, dest, fn_name, args) do
    arg_s = Enum.join(args, ", ")
    "#{dest} = #{value_return_allocator(fn_name)}(#{arg_s});"
  end

  defp value_return_allocator("elmc_tuple2_take"), do: "elmc_tuple2_take_value"

  defp value_return_allocator(fn_name) do
    if fn_name in @rc_allocators_with_take, do: "#{fn_name}_take", else: fn_name
  end

  defp assign_value_return(false, "*out", call_expr), do: "return #{call_expr};"
  defp assign_value_return(_rc?, dest, call_expr), do: "#{dest} = #{call_expr};"

  defp assign_owned(true, dest, call_expr) do
    """
    #{dest} = #{call_expr};
    if (!#{dest}) {
      Rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(Rc);
    }
    """
    |> String.trim()
  end

  defp assign_owned(false, "*out", call_expr), do: "return #{call_expr};"
  defp assign_owned(false, dest, call_expr), do: "#{dest} = #{call_expr};"

  defp retain_into_owned(dest, src), do: "#{dest} = elmc_retain(#{src});"

  defp emit_forward_ref_set(%{args: %{ref: ref, value: value_reg}}, slots, opts) do
    "elmc_forward_ref_set(#{ref}, #{slot_ref(value_reg, slots, opts)});"
  end

  defp emit_forward_ref_load(%{args: %{ref: ref}}, _slots, rc?, dest) do
    assign_owned(rc?, dest, "elmc_forward_ref_get(#{ref})")
  end

  defp emit_forward_ref_capture(%{args: %{ref: ref}}, _slots, rc?, dest) do
    assign_owned(rc?, dest, "elmc_forward_ref_capture(#{ref})")
  end

  defp emit_forward_ref_load_captured(_instr, _slots, rc?, dest) do
    assign_owned(
      rc?,
      dest,
      "elmc_forward_ref_get((capture_count > 0 && captures[0] && captures[0]->tag == ELMC_TAG_FORWARD_REF && captures[0]->payload) ? *((ElmcForwardRef **)captures[0]->payload) : NULL)"
    )
  end

  defp format_call_args(dest_arg, ""), do: dest_arg
  defp format_call_args(dest_arg, args), do: "#{dest_arg}, #{args}"

  defp rc_call(true, dest_ref, fn_name, args) do
    call_args = format_call_args(dest_arg(dest_ref, dest_ref), args)
    "Rc = #{fn_name}(#{call_args});\nCHECK_RC(Rc);"
  end

  defp rc_call(false, dest_ref, fn_name, args) do
    "#{dest_ref} = #{fn_name}(#{args});"
  end

  defp rc_callee_from_value_return(dest, _dest_ref, fn_name, args) do
    out_ptr = if String.starts_with?(dest, "*"), do: "out", else: "&#{dest}"
    call_args = if args == "", do: out_ptr, else: "#{out_ptr}, #{args}"

    """
    {
      RC __call_rc = #{fn_name}(#{call_args});
      if (__call_rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(__call_rc, "#{fn_name}", "plan call failed");
        #{dest} = elmc_int_zero();
      }
    }
    """
    |> String.trim()
  end

  defp dest_arg("out", _), do: "out"
  defp dest_arg(dest_ref, _), do: "&#{dest_ref}"

  defp cow_drop_alias_null(dest, base_reg, slots, opts) when is_integer(base_reg) do
    dest_s = format_dest(dest, slots, opts)
    base_s = slot_ref(base_reg, slots, opts)

    if dest_s != base_s do
      "if (#{dest_s} == #{base_s}) { #{base_s} = NULL; }"
    else
      ""
    end
  end

  defp cow_drop_alias_null(_, _, _, _), do: ""

  defp format_dest(nil, _, _opts), do: "_"
  defp format_dest(:fn_out, _, _opts), do: "*out"
  defp format_dest(:branch_out, _, _opts), do: "*out"

  defp format_dest(reg, slots, opts) when is_integer(reg) do
    cond do
      MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) ->
        Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), reg)

      MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) ->
        Map.get(Keyword.get(opts, :native_int_regs, %{}), reg, "plan_native_int_#{reg}")

      true ->
        slot_var(reg, slots)
    end
  end

  defp emit_make_closure(instr, slots, opts, rc?, dest) do
    idx = Map.get(instr.args, :index, 0)
    arity = Map.get(instr.args, :arity, 0)
    captures = Map.get(instr.args, :captures, [])
    parent = Keyword.fetch!(opts, :parent_plan)
    closure_fn = Lambda.closure_fn_name(parent, idx)
    cap_refs = Enum.map(captures, &slot_ref(&1, slots, opts))
    cap_count = length(cap_refs)

    {cap_array_code, cap_arg} =
      if cap_count > 0 do
        cap_var = "plan_cap_#{instr.id}"
        {"ElmcValue *#{cap_var}[#{cap_count}] = { #{Enum.join(cap_refs, ", ")} };", cap_var}
      else
        {"", "NULL"}
      end

    if rc? do
      dest_ref = if dest == "*out", do: "out", else: dest
      ptr = if String.starts_with?(dest, "owned["), do: "&#{dest}", else: dest_arg(dest_ref, dest)

      """
      #{cap_array_code}
      Rc = elmc_closure_new_rc(#{ptr}, #{closure_fn}, #{arity}, #{cap_count}, #{cap_arg});
      CHECK_RC(Rc);
      """
      |> String.trim()
    else
      """
      #{cap_array_code}
      #{dest} = elmc_closure_new_take(#{closure_fn}, #{arity}, #{cap_count}, #{cap_arg});
      """
      |> String.trim()
    end
  end

  defp emit_op_only(%Types{op: :publish, dest: :fn_out, args: %{source: reg}}, slots, opts)
       when is_integer(reg) do
    if Keyword.get(opts, :native_scalar_out) in [:native_int, :native_bool] do
      ""
    else
      publish_fn_out(reg, slots, opts)
    end
  end

  defp emit_op_only(%Types{op: :publish, dest: :fn_out}, _slots, _opts), do: ""

  defp emit_op_only(%Types{op: :load_param, dest: dest_reg, args: %{index: index}}, slots, opts) do
    borrow_param_regs = Keyword.get(opts, :borrow_param_regs, %{})

    if Map.has_key?(borrow_param_regs, dest_reg) do
      ""
    else
      emit_load_param_copy(%Types{op: :load_param, dest: dest_reg, args: %{index: index}}, slots, opts)
    end
  end

  defp emit_load_param_copy(%Types{op: :load_param, dest: dest_reg, args: %{index: index}}, slots, opts) do
    params = Keyword.get(opts, :params, [])
    param_kinds = Keyword.get(opts, :param_kinds, [])
    dest = slot_var(dest_reg, slots)
    ownership = Keyword.get(opts, :ownership, [])
    rc? = Keyword.get(opts, :rc_required, false)
    param_kind = Enum.at(param_kinds, index, :boxed)

    case Keyword.get(opts, :closure_mode) do
      %{capture_count: cap_n} when is_integer(cap_n) ->
        c_arg =
          if index < cap_n do
            "captures[#{index}]"
          else
            arg_i = index - cap_n
            "(argc > #{arg_i} ? args[#{arg_i}] : NULL)"
          end

        cond do
          rc? and index < cap_n ->
            retain_into_owned(dest, c_arg)

          true ->
            "#{dest} = #{c_arg};"
        end

      _ ->
        c_arg = FunctionCallAbi.param_c_arg(index, params)

        cond do
          param_kind == :native_int and Map.has_key?(native_int_direct_regs(opts), dest_reg) ->
            ""

          param_kind == :native_int ->
            rc_assign(rc?, dest, "elmc_new_int", [c_arg])

          param_kind == :native_bool ->
            rc_assign(rc?, dest, "elmc_new_bool", ["(#{c_arg}) ? 1 : 0"])

          rc? and :retain_arg in List.wrap(ownership) ->
            retain_into_owned(dest, c_arg)

          rc? ->
            "#{dest} = #{c_arg};"

          true ->
            "#{dest} = #{c_arg};"
        end
    end
  end

  defp emit_op_only(%Types{op: :catch_begin}, _slots, _opts), do: "CATCH_BEGIN"
  defp emit_op_only(%Types{op: :catch_end}, _slots, _opts), do: "CATCH_END;"
  defp emit_op_only(_, _slots, _opts), do: ""

  defp publish_fn_out(reg, slots, opts) do
    src = slot_ref(reg, slots, opts)

    case Map.get(slots, reg) do
      i when is_integer(i) ->
        "*out = #{src};\nowned[#{i}] = NULL;"

      nil ->
        "*out = #{src};"
    end
  end

  defp slot_var(reg, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "owned[#{i}]"
      _ -> "tmp_#{reg}"
    end
  end

  defp slot_ref(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
      c_arg when is_binary(c_arg) ->
        c_arg

      _ ->
        case Map.get(slots, reg) do
          i when is_integer(i) -> "owned[#{i}]"
          nil -> "arg#{reg}"
          _ -> "tmp_#{reg}"
        end
    end
  end

  defp slot_ref(:fn_out, _slots, _opts), do: "*out"
  defp slot_ref(:branch_out, _slots, _opts), do: "*out"

  defp record_new_suffix(dest_reg) when is_integer(dest_reg), do: Integer.to_string(dest_reg)
  defp record_new_suffix(:fn_out), do: "out"
  defp record_new_suffix(_), do: "0"

  defp record_values_array(field_regs, slots, opts) do
    field_regs
    |> Enum.with_index()
    |> Enum.map_join(", ", fn {reg, idx} ->
      ref = slot_ref(reg, slots, opts)
      prior = Enum.take(field_regs, idx)
      if reg in prior, do: "elmc_retain(#{ref})", else: ref
    end)
  end

  defp resolve_record_field_names(shape, field_count, module) do
    cond do
      is_list(shape) and shape != [] ->
        shape

      is_binary(shape) ->
        lookup_record_shape_type(shape, module)

      true ->
        infer_record_shape_by_count(field_count, module)
    end
  end

  defp lookup_record_shape_type(type, module) when is_binary(type) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    short = type |> String.split(".") |> List.last()

    Map.get(shapes, {module, type}) ||
      Map.get(shapes, {module, short}) ||
      Enum.find_value(shapes, fn {{m, name}, fields} ->
        if m == module and name in [type, short], do: fields
      end)
  end

  defp infer_record_shape_by_count(_count, nil), do: nil

  defp infer_record_shape_by_count(count, module) when is_integer(count) and is_binary(module) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case Enum.filter(shapes, fn {{m, _name}, fields} -> m == module and length(fields) == count end) do
      [{{_, _}, fields}] -> fields
      _ -> nil
    end
  end

  defp record_get_index_ref(field, index) when is_binary(field) and is_binary(index) do
    case Integer.parse(index) do
      {_, ""} -> "#{index} /* #{Util.escape_c_comment(field)} */"
      _ -> index
    end
  end

  @doc false
  @spec elm_mod_by_c_expr(String.t(), String.t()) :: String.t()
  def elm_mod_by_c_expr(base_s, value_s) do
    value_s = parenthesize_mod_value(value_s)

    case parse_int_literal(base_s) do
      {:ok, 0} ->
        "0"

      {:ok, base} ->
        correction = mod_abs_addend(base)
        mod_expr = "(elmc_int_t)(#{value_s} % #{base})"
        "((#{mod_expr}) < 0 ? (#{mod_expr}) + (elmc_int_t)#{correction} : #{mod_expr})"

      :dynamic ->
        "(#{base_s} == 0 ? 0 : (((elmc_int_t)(#{value_s} % #{base_s})) < 0 ? ((elmc_int_t)(#{value_s} % #{base_s})) + (elmc_int_t)#{mod_abs_addend_expr(base_s)} : (elmc_int_t)(#{value_s} % #{base_s})))"
    end
  end

  defp mod_abs_addend(base) when is_integer(base) and base > 0, do: Integer.to_string(base)
  defp mod_abs_addend(base) when is_integer(base) and base < 0, do: Integer.to_string(-base)
  defp mod_abs_addend(0), do: "0"

  defp mod_abs_addend_expr(base_s), do: "(#{base_s} < 0 ? -#{base_s} : #{base_s})"

  defp parse_int_literal(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> {:ok, n}
      _ -> :dynamic
    end
  end

  defp native_int_repeat_count?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg)
  end

  defp parenthesize_mod_value(value_s) when is_binary(value_s) do
    trimmed = String.trim(value_s)

    if trimmed != "" and not String.starts_with?(trimmed, "(") and
         String.match?(trimmed, ~r/[+\-*]/) do
      "(#{trimmed})"
    else
      trimmed
    end
  end
end
