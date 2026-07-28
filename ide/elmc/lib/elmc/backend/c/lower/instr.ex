defmodule Elmc.Backend.C.Lower.Instr do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.C.Lower.{Function, Lambda, NativeReturn, NativeIntFold, TagRefs}
  alias Elmc.Backend.CCodegen.{FunctionCallAbi, FunctionEmit, Fusion, ImmortalStringLiteral, PlanNativeProjection, RcRequired, RcRuntimeEmit, RowMajorLayout}
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.SpecialValues.ElmCore
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.SizeProfile

  # Plan `call_runtime` ids → elm/core qualified names (parity with CallCompile comments).
  @elm_core_runtime_targets %{
    list_append: "List.append",
    list_cons: "List.cons",
    list_repeat: "List.repeat",
    list_map: "List.map",
    list_foldl: "List.foldl",
    list_length: "List.length",
    list_reverse: "List.reverse",
    list_is_empty: "List.isEmpty",
    maybe_and_then: "Maybe.andThen",
    maybe_with_default: "Maybe.withDefault",
    result_and_then: "Result.andThen",
    result_with_default: "Result.withDefault",
    basics_min: "Basics.min",
    basics_max: "Basics.max",
    basics_mod_by: "Basics.modBy",
    string_append: "String.append",
    string_length: "String.length",
    char_to_code: "Char.toCode",
    char_from_code: "Char.fromCode"
  }

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

  def emit(%Types{} = instr, slots, opts), do: emit_instr(instr, slots, opts)

  @spec instr_skip_regs(keyword()) :: Types.ir_expr()

  defp instr_skip_regs(opts) do
    Keyword.get(opts, :fused_string_skip_regs, MapSet.new())
    |> MapSet.union(Keyword.get(opts, :tail_inline_skip_regs, MapSet.new()))
  end

  @spec emit_instr(map(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_instr(%Types{op: op} = instr, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    dest = format_dest(instr.dest, slots, opts)

    case op do
      :const_int ->
        skip_const? =
          MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest) or
            MapSet.member?(Keyword.get(opts, :fusion_native_literal_regs, MapSet.new()), instr.dest)

        if skip_const? do
          ""
        else
          value = Integer.to_string(instr.args.value)

          if Map.get(instr.args, :bool_lit) == true do
            rc_assign(rc?, dest, "elmc_new_bool", [value])
          else
            rc_assign(rc?, dest, "elmc_new_int", [value])
          end
        end

      :const_c_expr ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest) do
          ""
        else
          rc_assign(rc?, dest, "elmc_new_int", [Map.fetch!(instr.args, :value)])
        end

      :platform_static_int ->
        emit_platform_static_int(instr, rc?, dest, opts)

      :record_get_int ->
        emit_record_get_int(instr, slots, rc?, dest, opts)

      :const_static_list ->
        emit_const_static_list(instr, slots, dest, rc?, opts)

      :const_immortal_string ->
        emit_const_immortal_string(instr, dest, rc?)

      :load_local ->
        emit_load_local(instr, slots, rc?, dest, opts)

      :call_runtime ->
        emit_call_runtime(instr, slots, rc?, dest, opts)

      :call_fn ->
        emit_call_fn(instr, slots, rc?, dest, opts)

      :call_closure ->
        emit_call_closure(instr, slots, rc?, dest, opts)

      :release ->
        emit_release(instr, slots)

      :record_get ->
        base = slot_ref(instr.args.base, slots, opts)
        field = instr.args.field
        index = record_get_index_ref(field, Map.get(instr.args, :field_index, "0"))
        assign_value_return(rc?, dest, "elmc_record_get_index(#{base}, #{index})")

      :record_update ->
        base = slot_ref(instr.args.base, slots, opts)
        value = slot_ref(instr.args.value, slots, opts)
        field = Map.get(instr.args, :field)
        index = record_get_index_ref(field, Map.get(instr.args, :field_index, "0"))
        call_expr = "elmc_record_update_index_cow_drop(#{base}, #{index}, #{value})"
        fn_out_tail? = instr.dest in [:fn_out, :branch_out] and not rc?

        assign =
          if fn_out_tail? do
            assign_value_return_tail(rc?, dest, call_expr, instr, slots, opts)
          else
            assign_value_return(rc?, dest, call_expr)
          end

        alias_guard =
          if fn_out_tail? do
            ""
          else
            cow_drop_alias_null(
              instr.dest,
              instr.args.base,
              Map.get(instr.args, :retain_copy, false),
              slots,
              opts
            )
          end

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

      :test_string_literal ->
        literal = Map.fetch!(instr.args, :literal)
        escaped = Util.escape_c_string(literal)

        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          "elmc_string_equals_cstr(#{subject}, \"#{escaped}\")"
        end)

      :test_ctor_tag ->
        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          tag = instr.args.tag
          tag_ref = TagRefs.union_tag_ref(tag, Map.get(instr.args, :union_ctor), plan_module_from(opts))
          "elmc_union_tag_matches(#{subject}, #{tag_ref})"
        end)

      :test_bool ->
        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          boxed_bool_test_expr(subject, Map.fetch!(instr.args, :want_true))
        end)

      :bool_and ->
        emit_bool_and(instr, slots, rc?, dest, opts)

      :switch_ctor_tag ->
        emit_switch_ctor_tag(instr, slots, rc?, dest, opts)

      :boxed_tag_peel ->
        subject = slot_ref(Map.fetch!(instr.args, :subject), slots, opts)
        dest_reg = instr.dest
        name = Map.fetch!(Keyword.get(opts, :native_int_regs, %{}), dest_reg)

        peel_fn =
          if SizeProfile.enum_tag_peel?(Process.get(:elmc_codegen_opts, %{})) do
            "elmc_union_tag_as_int"
          else
            "elmc_as_int"
          end

        "#{name} = #{peel_fn}(#{subject});"

      :pebble_cmd ->
        emit_pebble_cmd(instr, slots, rc?, dest, opts)

      :render_cmd ->
        emit_render_cmd(instr, slots, rc?, dest, opts)

      :render_text_cmd ->
        emit_render_text_cmd(instr, slots, rc?, dest, opts)

      :list_cursor_map ->
        emit_list_cursor_map(instr, slots, rc?, dest, opts)

      :pipe_apply_repeat ->
        emit_pipe_apply_repeat(instr, slots, rc?, dest, opts)

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
  @spec branch_cond_expr(integer() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  def branch_cond_expr(reg, slots, opts) when is_integer(reg), do: branch_cond_expr_impl(reg, slots, opts)

  def branch_cond_expr(dest, slots, opts) when dest in [:fn_out, :branch_out] do
    "elmc_as_bool(#{slot_ref(dest, slots, opts)})"
  end

  @spec branch_cond_expr_impl(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  @spec emit_phi(map(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

      native_bool_cond? and not native_bool_dest? and Map.get(args, :truthy_native) == true ->
        then_s = truthy_shape_boxed_c_expr(Map.fetch!(args, :then_shape), slots, opts)
        else_s = truthy_shape_boxed_c_expr(Map.fetch!(args, :else_shape), slots, opts)

        """
        if (#{cond_expr}) {
          #{phi_boxed_arm_assign(rc?, merge, then_s)}
        } else {
          #{phi_boxed_arm_assign(rc?, merge, else_s)}
        }
        """
        |> String.trim()

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
        """
        if (#{cond_expr}) {
          #{phi_arm_assign(rc?, merge, then_reg, slots, opts)}
        } else {
          #{phi_arm_assign(rc?, merge, else_reg, slots, opts)}
        }
        """
        |> String.trim()
    end
  end

  @spec phi_arm_assign(boolean(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp phi_arm_assign(rc?, merge, reg, slots, opts) do
    src = phi_boxed_arm_source(reg, slots, opts)
    borrow_retain? = Map.has_key?(Keyword.get(opts, :borrow_param_regs, %{}), reg)
    phi_boxed_arm_assign(rc?, merge, src, borrow_retain?: borrow_retain?)
  end

  # Native-int params / locals must be boxed when merging into an owned slot — never `elmc_retain`
  # on an `elmc_int_t` C value. Prefer an existing owned slot when the reg was already boxed
  # (e.g. native-int param with boxed phi uses).
  @spec phi_boxed_arm_source(integer() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp phi_boxed_arm_source(reg, slots, opts) when is_integer(reg) do
    native_int_regs = Keyword.get(opts, :native_int_regs, %{})
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    const_int_regs = Keyword.get(opts, :const_int_regs, %{})

    cond do
      is_integer(Map.get(slots, reg)) ->
        slot_ref(reg, slots, opts)

      MapSet.member?(native_int_only, reg) ->
        boxed_value_ref(reg, slots, opts)

      Map.has_key?(native_int_regs, reg) ->
        boxed_value_ref(reg, slots, opts)

      Map.has_key?(const_int_regs, reg) ->
        boxed_value_ref(reg, slots, opts)

      true ->
        slot_ref(reg, slots, opts)
    end
  end

  defp phi_boxed_arm_source(reg, slots, opts), do: slot_ref(reg, slots, opts)

  @spec phi_boxed_arm_assign(boolean(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp phi_boxed_arm_assign(rc?, merge, src, opts \\ []) do
    borrow_retain? = Keyword.get(opts, :borrow_retain?, false)

    retain? =
      cond do
        rc? and String.contains?(src, "_take(") -> false
        rc? -> true
        borrow_retain? -> true
        # Non-RC phi must not alias owned arm slots into the merge slot and then
        # release the arms — that frees closures/tuples still referenced by merge
        # or by the returned value. Treat like RC (retain or dead-slot transfer).
        assignable_owned_slot_ref?(src) and merge != src -> true
        true -> false
      end

    phi_owned_merge_assign(rc?, merge, src, retain: retain?, borrow_retain?: borrow_retain?)
  end

  @spec phi_owned_merge_assign(boolean(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp phi_owned_merge_assign(rc?, merge, src, opts) do
    retain? = Keyword.get(opts, :retain, false)
    borrow_retain? = Keyword.get(opts, :borrow_retain?, false)
    src_owned? = assignable_owned_slot_ref?(src)
    merge_dead? = phi_merge_dest_dead?(merge)
    src_live? = phi_owned_src_live?(src)
    merge_owned? = assignable_owned_slot_ref?(merge)

    # Transfer (move + null src) is only safe when the source slot has no further
    # uses. Otherwise keep the source live and retain into the merge (e.g. Set
    # `next = if … then remove else withInsert` followed by `Set.member … withInsert`).
    use_transfer? =
      merge_dead? and src_owned? and retain? and not borrow_retain? and merge != src and
        not src_live?

    assign =
      cond do
        use_transfer? ->
          "#{merge} = #{src};"

        rc? and String.contains?(src, "_take(") ->
          "#{merge} = #{src};"

        retain? ->
          retain_into_owned(merge, src)

        true ->
          "#{merge} = #{src};"
      end

    null_src =
      if use_transfer? or (not retain? and merge != src and src_owned? and not src_live?) do
        "\n    #{src} = NULL;"
      else
        ""
      end

    # Linear owned-live tracking walks both CFG arms, so a phi dest may look
    # "dead" after the other arm released it while this arm still holds a value
    # (e.g. double-cons `a` left in owned[i] on the equal-merge arm). Always
    # release before overwrite; elmc_release(NULL) is a no-op.
    release_dest =
      if merge_owned? and merge != src do
        "elmc_release(#{merge});\n    #{merge} = NULL;\n    "
      else
        ""
      end

    """
    #{release_dest}#{assign}#{null_src}
    """
    |> String.trim()
  end

  @spec phi_merge_dest_dead?(Types.ir_expr()) :: boolean()

  defp phi_merge_dest_dead?(merge) do
    case owned_slot_index(merge) do
      idx when is_integer(idx) ->
        live = Process.get(:elmc_plan_owned_live, MapSet.new())
        not MapSet.member?(live, idx)

      _ ->
        false
    end
  end

  @spec phi_owned_src_live?(Types.ir_expr() | term()) :: boolean()

  defp phi_owned_src_live?(src) do
    case owned_slot_index(src) do
      idx when is_integer(idx) ->
        live = Process.get(:elmc_plan_owned_live, MapSet.new())
        MapSet.member?(live, idx)

      _ ->
        false
    end
  end

  @spec owned_slot_index(Types.ir_expr() | term()) :: Types.ir_expr()

  defp owned_slot_index("owned[" <> rest) do
    case Integer.parse(rest) do
      {idx, "]"} -> idx
      _ -> nil
    end
  end

  defp owned_slot_index(_), do: nil

  @spec truthy_shape_boxed_c_expr(term() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp truthy_shape_boxed_c_expr({:const_int, value}, _slots, _opts) when is_integer(value) do
    "elmc_new_bool_take(#{value})"
  end

  defp truthy_shape_boxed_c_expr({:compare, kind, left, right}, slots, opts) do
    cmp = compare_branch_c_expr(kind, left, right, slots, opts)
    "elmc_new_bool_take((#{cmp}) ? 1 : 0)"
  end

  defp truthy_shape_boxed_c_expr({:reg, reg}, slots, opts) when is_integer(reg) do
    boxed_value_ref(reg, slots, opts)
  end

  defp truthy_shape_boxed_c_expr(_shape, _slots, _opts), do: "elmc_new_bool_take(0)"

  @spec native_int_phi_arm_exprs([String.t()], Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp native_int_phi_arm_exprs(args, slots, opts) do
    {
      native_int_phi_shape_c_expr(Map.fetch!(args, :then_shape), slots, opts),
      native_int_phi_shape_c_expr(Map.fetch!(args, :else_shape), slots, opts)
    }
  end

  @spec native_int_phi_shape_c_expr(term() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp native_int_phi_shape_c_expr({:const_int, value}, _slots, _opts), do: Integer.to_string(value)

  defp native_int_phi_shape_c_expr({:new_int, value}, _slots, _opts) when is_integer(value),
    do: Integer.to_string(value)

  defp native_int_phi_shape_c_expr({:new_int, expr}, _slots, _opts) when is_binary(expr), do: expr

  defp native_int_phi_shape_c_expr({:int_arith, args}, slots, opts),
    do: Elmc.Backend.C.Lower.NativeIntFold.int_arith_c_expr(args, slots, opts) || "0"

  defp native_int_phi_shape_c_expr(_shape, _slots, _opts), do: "0"

  @spec phi_truthy_arm_exprs([String.t()], Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp phi_truthy_arm_exprs(args, then_reg, else_reg, slots, opts) do
    if Map.get(args, :truthy_native) == true do
      {truthy_shape_c_expr(Map.fetch!(args, :then_shape), slots, opts),
       truthy_shape_c_expr(Map.fetch!(args, :else_shape), slots, opts)}
    else
      {phi_truthy_arm_expr(then_reg, slots, opts), phi_truthy_arm_expr(else_reg, slots, opts)}
    end
  end

  @spec truthy_shape_c_expr(term(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp truthy_shape_c_expr({:const_int, 0}, _slots, _opts), do: "false"
  defp truthy_shape_c_expr({:const_int, 1}, _slots, _opts), do: "true"

  defp truthy_shape_c_expr({:compare, kind, left, right}, slots, opts) do
    compare_branch_c_expr(kind, left, right, slots, opts)
  end

  defp truthy_shape_c_expr({:reg, reg}, slots, opts) when is_integer(reg) do
    branch_cond_expr_impl(reg, slots, opts)
  end

  @spec phi_truthy_arm_expr(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp phi_truthy_arm_expr(reg, slots, opts) when is_integer(reg) do
    native_bool_regs = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    const_int_regs = Keyword.get(opts, :const_int_regs, %{})
    native_int_regs = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    cond do
      MapSet.member?(native_bool_regs, reg) ->
        branch_cond_expr_impl(reg, slots, opts)

      Map.has_key?(const_int_regs, reg) ->
        case Map.fetch!(const_int_regs, reg) |> const_int_value() do
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

  @spec plan_defining_instr(map() | term(), integer() | term()) :: Types.ir_expr()

  defp plan_defining_instr(%{blocks: blocks}, reg) when is_integer(reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.find(fn %{dest: dest} -> dest == reg end)
  end

  defp plan_defining_instr(_, _), do: nil

  @spec truthy_expr(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  @spec ternary_cond_expr(Types.ir_expr() | integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp ternary_cond_expr(dest, slots, opts) when dest in [:fn_out, :branch_out] do
    branch_cond_expr(dest, slots, opts)
  end

  defp ternary_cond_expr(reg, slots, opts) when is_integer(reg) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) and
         not MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) do
      "#{int_operand_ref(reg, slots, opts)} != 0"
    else
      branch_cond_expr_impl(reg, slots, opts)
    end
  end

  @spec emit_compare(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_compare(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    cmp =
      compare_branch_c_expr(
        args.kind,
        args.left,
        args.right,
        slots,
        opts,
        Map.get(args, :mode, :pointer)
      )

    cond do
      MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) ->
        emit_native_bool_store(dest_reg, dest, cmp, opts)

      dest == "*out" and Keyword.get(opts, :native_scalar_out) == :native_bool ->
        "*out = #{cmp};"

      true ->
        rc_assign(rc?, dest, "elmc_new_bool", [cmp])
    end
  end

  @spec emit_bool_and(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_bool_and(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    left = truthy_expr(args.left, slots, opts)
    right = truthy_expr(args.right, slots, opts)
    expr = "(#{left} && #{right})"

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      emit_native_bool_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_bool", ["#{expr} ? 1 : 0"])
    end
  end

  @spec emit_native_bool_test(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword(), Types.expr()) :: Types.ir_expr()

  defp emit_native_bool_test(%{dest: dest_reg, args: args}, slots, rc?, dest, opts, subject_expr) do
    subject = bool_test_subject_ref(args, slots, opts)
    expr = subject_expr.(subject)

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      emit_native_bool_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_bool", ["#{expr} ? 1 : 0"])
    end
  end

  @spec bool_test_subject_ref(map() | integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp bool_test_subject_ref(%{reg: reg}, slots, opts), do: bool_test_subject_ref(reg, slots, opts)
  defp bool_test_subject_ref(%{subject: reg}, slots, opts), do: bool_test_subject_ref(reg, slots, opts)

  defp bool_test_subject_ref(reg, slots, opts) when is_integer(reg) do
    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) do
      Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), reg)
    else
      slot_ref(reg, slots, opts)
    end
  end

  @spec boxed_bool_test_expr(Types.expr(), boolean()) :: Types.ir_expr()

  defp boxed_bool_test_expr(subject, want_true?) do
    core =
      cond do
        String.match?(subject, ~r/^plan_native_bool_\d+$/) ->
          subject

        String.starts_with?(subject, "const bool plan_native_bool_") ->
          subject |> String.replace_prefix("const bool ", "")

        # Native-bool ABI: False/True are const 0/1. Never pass those through
        # elmc_as_bool (treats 0 as a NULL pointer).
        subject == "0" ->
          "false"

        subject == "1" ->
          "true"

        true ->
          "elmc_as_bool(#{subject})"
      end

    if want_true?, do: core, else: "!(#{core})"
  end

  @spec emit_native_bool_store(Types.ir_expr(), Types.ir_expr(), Types.expr(), keyword()) :: Types.ir_expr()

  defp emit_native_bool_store(dest_reg, _dest, expr, opts) do
    name = Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), dest_reg)

    if MapSet.member?(Keyword.get(opts, :native_bool_mutable_regs, MapSet.new()), dest_reg) do
      "#{name} = #{expr};"
    else
      "const bool #{name} = #{expr};"
    end
  end

  @spec compare_native_c_expr(Types.ir_expr() | term(), Types.expr(), Types.expr()) :: Types.ir_expr()

  defp compare_native_c_expr(:eq, left, right), do: "(#{left} == #{right})"
  defp compare_native_c_expr(:neq, left, right), do: "(#{left} != #{right})"
  defp compare_native_c_expr(:gt, left, right), do: "(#{left} > #{right})"
  defp compare_native_c_expr(:gte, left, right), do: "(#{left} >= #{right})"
  defp compare_native_c_expr(:lt, left, right), do: "(#{left} < #{right})"
  defp compare_native_c_expr(:lte, left, right), do: "(#{left} <= #{right})"
  defp compare_native_c_expr(_, left, right), do: "(#{left} == #{right})"

  @spec compare_branch_c_expr(atom(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp compare_branch_c_expr(kind, left_reg, right_reg, slots, opts, compare_mode \\ :pointer)
       when is_integer(left_reg) and is_integer(right_reg) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    left_native? = MapSet.member?(native_int_only, left_reg)
    right_native? = MapSet.member?(native_int_only, right_reg)

    cond do
      left_native? and right_native? ->
        compare_native_c_expr(
          kind,
          int_operand_ref(left_reg, slots, opts),
          int_operand_ref(right_reg, slots, opts)
        )

      kind in [:eq, :neq] and compare_mode == :list_int ->
        left = slot_ref(left_reg, slots, opts)
        right = slot_ref(right_reg, slots, opts)
        eq_expr = "elmc_list_equal_int(#{left}, #{right})"
        if kind == :eq, do: eq_expr, else: "(!#{eq_expr})"

      kind in [:eq, :neq] and compare_mode == :string ->
        left = slot_ref(left_reg, slots, opts)
        right = slot_ref(right_reg, slots, opts)
        eq_expr = "elmc_string_equals(#{left}, #{right})"
        if kind == :eq, do: eq_expr, else: "(!#{eq_expr})"

      compare_mode == :string ->
        left = slot_ref(left_reg, slots, opts)
        right = slot_ref(right_reg, slots, opts)
        compare_native_c_expr(kind, "elmc_string_compare(#{left}, #{right})", "0")

      kind in [:eq, :neq] and compare_mode == :int_boxed ->
        left = compare_int_boxed_operand(left_reg, left_native?, slots, opts)
        right = compare_int_boxed_operand(right_reg, right_native?, slots, opts)
        eq_expr = "(#{left} == #{right})"
        if kind == :eq, do: eq_expr, else: "(!#{eq_expr})"

      compare_mode == :float_boxed ->
        compare_native_c_expr(
          kind,
          compare_float_boxed_operand(left_reg, slots, opts),
          compare_float_boxed_operand(right_reg, slots, opts)
        )

      kind in [:eq, :neq] ->
        left = int_operand_ref(left_reg, slots, opts)
        right = int_operand_ref(right_reg, slots, opts)
        eq_expr = "(#{left} == #{right})"
        if kind == :eq, do: eq_expr, else: "(!#{eq_expr})"

      true ->
        compare_native_c_expr(
          kind,
          int_operand_ref(left_reg, slots, opts),
          int_operand_ref(right_reg, slots, opts)
        )
    end
  end

  @spec compare_float_boxed_operand(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp compare_float_boxed_operand(reg, slots, opts) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    cond do
      MapSet.member?(native_int_only, reg) ->
        "(double)(#{int_operand_ref(reg, slots, opts)})"

      true ->
        case peel_native_int_operand_ref(reg, slots, opts) do
          native when is_binary(native) -> "(double)(#{native})"
          _ -> "elmc_as_float(#{slot_ref(reg, slots, opts)})"
        end
    end
  end

  @spec compare_int_boxed_operand(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp compare_int_boxed_operand(reg, true, slots, opts),
    do: int_operand_ref(reg, slots, opts)

  defp compare_int_boxed_operand(reg, false, slots, opts) do
    case peel_native_int_operand_ref(reg, slots, opts) do
      native when is_binary(native) -> native
      _ -> "elmc_as_int(#{slot_ref(reg, slots, opts)})"
    end
  end

  @spec emit_switch_ctor_tag(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_switch_ctor_tag(%{dest: dest_reg, args: args}, slots, rc?, merge, opts) do
    subject = switch_subject_ref(args.subject, slots, opts)
    native? = MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg)

    arm_lines =
      Enum.map(args.arms, fn %{tag: tag, reg: reg} ->
        cond_line = "if (elmc_union_tag_matches(#{subject}, #{tag}))"

        body =
          if native? do
            src = int_operand_ref(reg, slots, opts)
            emit_native_store(dest_reg, merge, src, opts)
          else
            src = boxed_value_ref(reg, slots, opts)

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
              src = boxed_value_ref(reg, slots, opts)

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

  @spec emit_int_arith(map() | term(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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
    lhs_s = NativeIntFold.parenthesize_int_expr(int_operand_ref(lhs, slots, opts))
    rhs_s = NativeIntFold.parenthesize_int_expr(int_operand_ref(rhs, slots, opts))
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} * #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :sub_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = NativeIntFold.parenthesize_int_expr(int_operand_ref(lhs, slots, opts))
    rhs_s = NativeIntFold.parenthesize_int_expr(int_operand_ref(rhs, slots, opts))
    emit_int_result_assign(dest_reg, dest, rc?, "#{lhs_s} - #{rhs_s}", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :idiv_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = NativeIntFold.parenthesize_int_expr(int_operand_ref(lhs, slots, opts))
    rhs_s = NativeIntFold.parenthesize_int_expr(int_operand_ref(rhs, slots, opts))
    emit_int_result_assign(dest_reg, dest, rc?, idiv_c_expr(lhs_s, rhs_s), opts)
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

  @spec emit_int_result_assign(Types.ir_expr(), Types.ir_expr(), boolean(), Types.expr(), keyword()) :: Types.ir_expr()

  defp emit_int_result_assign(dest_reg, dest, _rc?, expr, opts) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(Keyword.get(opts, :rc_required, true), dest, "elmc_new_int", [expr])
    end
  end

  @spec emit_native_store(Types.ir_expr(), Types.ir_expr(), Types.expr(), keyword()) :: Types.ir_expr()

  defp emit_native_store(dest_reg, dest, expr, opts) do
    if MapSet.member?(Keyword.get(opts, :native_int_mutable_regs, MapSet.new()), dest_reg) do
      "#{dest} = #{expr};"
    else
      "const elmc_int_t #{dest} = #{expr};"
    end
  end

  @spec emit_record_get_int(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  @spec emit_boxed_binop(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_boxed_binop(%{dest: dest_reg, args: %{op: op, lhs: lhs, rhs: rhs} = args}, slots, rc?, dest, opts) do
    float_mode? = Map.get(args, :mode) == :float or op == :fdiv

    if float_mode? do
      left = slot_ref(lhs, slots, opts)
      right = slot_ref(rhs, slots, opts)

      op_sym =
        case op do
          :add -> "+"
          :sub -> "-"
          :mul -> "*"
          :idiv -> "/"
          :fdiv -> "/"
          other -> raise ArgumentError, "unknown boxed_binop #{inspect(other)}"
        end

      float_expr = "elmc_as_float(#{left}) #{op_sym} elmc_as_float(#{right})"
      rc_assign(rc?, dest, "elmc_new_float", [float_expr])
    else
      if native_int_binop_operands?(lhs, rhs, opts) do
        op_sym =
          case op do
            :add -> "+"
            :sub -> "-"
            :mul -> "*"
            :idiv -> "/"
            other -> raise ArgumentError, "unknown boxed_binop #{inspect(other)}"
          end

        left = int_operand_ref(lhs, slots, opts)
        right = int_operand_ref(rhs, slots, opts)
        emit_int_result_assign(dest_reg, dest, rc?, "#{left} #{op_sym} #{right}", opts)
      else
        emit_boxed_binop_dynamic(op, lhs, rhs, slots, rc?, dest, opts)
      end
    end
  end

  @spec emit_boxed_binop_dynamic(atom(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

    # Non-fdiv boxed binops are Int in practice when they reach this fallback
    # (Float arithmetic is lowered via float-specific ops / as_float paths).
    # Emitting a dead `elmc_new_float` branch broke Int helpers such as
    # integerLetArithmetic (`refute body =~ "elmc_new_float"`).
    if op == :fdiv do
      float_expr = "elmc_as_float(#{left}) #{op_sym} elmc_as_float(#{right})"
      rc_assign(rc?, dest, "elmc_new_float", [float_expr])
    else
      int_expr = "elmc_as_int(#{left}) #{op_sym} elmc_as_int(#{right})"
      rc_assign(rc?, dest, "elmc_new_int", [int_expr])
    end
  end

  @spec native_int_binop_operands?(integer() | term(), integer() | term(), keyword() | term()) :: boolean()

  defp native_int_binop_operands?(lhs, rhs, opts) when is_integer(lhs) and is_integer(rhs) do
    native_int_operand_reg?(lhs, opts) and native_int_operand_reg?(rhs, opts)
  end

  defp native_int_binop_operands?(_, _, _), do: false

  @spec native_int_operand_reg?(integer(), keyword()) :: boolean()

  defp native_int_operand_reg?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), reg)
  end

  @spec float_literal_c(integer() | float()) :: Types.ir_expr()

  defp float_literal_c(value) when is_integer(value), do: "#{value}.0"
  defp float_literal_c(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])

  @spec consumed_owned_transfer?(map() | term(), Types.ir_expr() | term()) :: boolean()

  defp consumed_owned_transfer?(%{consumes: consumes}, src) when is_list(consumes),
    do: src in consumes

  defp consumed_owned_transfer?(_, _), do: false

  @spec fresh_int_take_expr?(String.t() | term()) :: boolean()

  defp fresh_int_take_expr?(src_s) when is_binary(src_s),
    do: String.starts_with?(src_s, "elmc_new_int_take(")

  defp fresh_int_take_expr?(_), do: false

  @spec assignable_owned_slot_ref?(String.t() | term()) :: boolean()

  defp assignable_owned_slot_ref?(src) when is_binary(src),
    do: String.match?(src, ~r/^owned\[\d+\]$/)

  defp assignable_owned_slot_ref?(_), do: false

  @spec native_int_slot_ref(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp native_int_slot_ref(reg, slots, opts) when is_integer(reg) do
    inline = Keyword.get(opts, :native_int_inline, %{})
    skip? = MapSet.member?(instr_skip_regs(opts), reg)

    cond do
      Map.has_key?(inline, reg) ->
        Map.fetch!(inline, reg)

      skip? ->
        skipped_native_int_operand_ref(reg, slots, opts)

      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg) ->
        Map.fetch!(Keyword.get(opts, :native_int_regs, %{}), reg)

      true ->
        "plan_native_int_#{reg}"
    end
  end

  @spec skipped_native_int_operand_ref(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp skipped_native_int_operand_ref(reg, slots, opts) when is_integer(reg) do
    case native_int_def_c_expr(reg, slots, opts) do
      expr when is_binary(expr) ->
        expr

      nil ->
        int_operand_ref_impl_no_copy(
          reg,
          slots,
          Keyword.put(opts, :native_int_only_regs, MapSet.new())
        )
    end
  end

  @spec native_int_def_c_expr(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp native_int_def_c_expr(reg, slots, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :int_arith, args: args} ->
        NativeIntFold.int_arith_c_expr(args, slots, opts)

      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        case peel_native_int_operand_ref(reg, slots, opts) do
          peeled when is_binary(peeled) ->
            peeled

          _ ->
            int_operand_ref(src, slots, opts)
        end

      %{op: :const_int, args: %{value: value}} when is_integer(value) ->
        Integer.to_string(value)

      %{op: :const_c_expr, args: %{value: value}} when is_binary(value) ->
        "(#{value})"

      _ ->
        nil
    end
  end

  @spec record_int_operand_ref(integer() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp record_int_operand_ref(reg, slots, opts) when is_integer(reg) do
    inline = Keyword.get(opts, :native_int_inline, %{})

    cond do
      Map.has_key?(inline, reg) ->
        Map.fetch!(inline, reg)

      MapSet.member?(instr_skip_regs(opts), reg) ->
        skipped_native_int_operand_ref(reg, slots, opts)

      true ->
        int_operand_ref(reg, slots, opts)
    end
  end

  defp record_int_operand_ref(other, _slots, _opts), do: to_string(other)

  # Arg 0 is always native-int via RuntimeBuiltins.native_int_arg?/2 → int_operand_ref/3.
  # Keep the callee symbol on the *_int ABI or C gets elmc_as_int(...) into ElmcValue*.
  @spec runtime_builtin_sym(Types.ir_expr() | atom(), [String.t()], Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp runtime_builtin_sym(:list_take, _args, _slots, _opts), do: "elmc_list_take_int"

  defp runtime_builtin_sym(:list_drop, _args, _slots, _opts), do: "elmc_list_drop_int"

  defp runtime_builtin_sym(id, _args, _slots, _opts), do: RuntimeBuiltins.c_symbol(id)

  @spec emit_call_runtime(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  defp emit_call_runtime(
         %{dest: dest_reg, id: instr_id, args: %{builtin: :record_new_values_ints, args: args} = args_map},
         slots,
         rc?,
         dest,
         opts
       )
       when is_list(args) do
    suffix = record_new_suffix(dest_reg, instr_id)
    count = length(args)
    module = Keyword.get(opts, :module)

    field_names =
      case Map.get(args_map, :field_names) do
        names when is_list(names) and names != [] ->
          names

        _ ->
          resolve_record_field_names(Map.get(args_map, :shape), count, module)
      end

    values_s =
      args
      |> Enum.map_join(", ", &record_int_operand_ref(&1, slots, opts))

    values_decl = "elmc_int_t rec_values_#{suffix}[#{max(count, 1)}] = { #{values_s} };"

    use_named? =
      Process.get(:elmc_named_record_literals, false) and is_list(field_names) and field_names != []

    {names_decl, sym, call_args} =
      if use_named? do
        names_array =
          field_names
          |> Enum.map_join(", ", fn name -> "\"#{Util.escape_c_string(to_string(name))}\"" end)

        {
          "const char *rec_names_#{suffix}[#{max(count, 1)}] = { #{names_array} };",
          "elmc_record_new_static_ints",
          ["#{count}", "rec_names_#{suffix}", "rec_values_#{suffix}"]
        }
      else
        {"", "elmc_record_new_values_ints", ["#{count}", "rec_values_#{suffix}"]}
      end

    """
    #{names_decl}
    #{values_decl}
    #{rc_assign(rc?, dest, sym, call_args)}
    """
    |> String.trim()
  end

  defp emit_call_runtime(%{dest: dest_reg, id: instr_id, args: %{builtin: id, args: args} = args_map}, slots, rc?, dest, opts)
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
    suffix = record_new_suffix(dest_reg, instr_id)
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
    #{null_owned_slots_named_in_values_array(values_array)}
    """
    |> String.trim()
  end

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :retain, view_peel: peel_id, view_peel_args: peel_args}},
         slots,
         rc?,
         dest,
         opts
       )
       when is_integer(dest_reg) do
    peel_sym = RuntimeBuiltins.c_symbol(peel_id) || "elmc_unknown"

    peel_args_c =
      peel_args
      |> Enum.map(&slot_ref(&1, slots, opts))

    peel_expr = "#{peel_sym}(#{Enum.join(peel_args_c, ", ")})"
    assign_owned(rc?, dest, "elmc_retain(#{peel_expr})")
  end

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :retain, args: [src]}, effects: effects},
         slots,
         rc?,
         dest,
         opts
       )
       when is_integer(src) and is_integer(dest_reg) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      src_expr = int_operand_ref(src, slots, opts)
      emit_native_store(dest_reg, dest, src_expr, opts)
    else
      src_s = boxed_value_ref(src, slots, opts)

      cond do
        consumed_owned_transfer?(effects, src) ->
          emit_owned_slot_transfer(dest_reg, src, slots, dest, src_s, rc?)

        fresh_int_take_expr?(src_s) ->
          assign_value_return(rc?, dest, src_s)

        true ->
          sym = RuntimeBuiltins.c_symbol(:retain)
          assign_value_return(rc?, dest, "#{sym}(#{src_s})")
      end
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

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :new_int, literal: value}},
         _slots,
         rc?,
         dest,
         opts
       )
       when is_integer(value) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      ""
    else
      rc_assign(rc?, dest, "elmc_new_int", [Integer.to_string(value)])
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :new_bool, literal: value}}, _slots, rc?, dest, _opts)
       when value in [0, 1] do
    rc_assign(rc?, dest, "elmc_new_bool", [Integer.to_string(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_order, literal: value}}, _slots, rc?, dest, _opts)
       when is_integer(value) do
    rc_assign(rc?, dest, "elmc_new_order", [Integer.to_string(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :string_length_boxed, args: [arg]}}, slots, rc?, dest, opts)
       when is_integer(arg) do
    src = boxed_value_ref(arg, slots, opts)
    rc_assign(rc?, dest, "elmc_new_int", ["elmc_string_length(#{src})"])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_float, literal: value}}, _slots, rc?, dest, _opts)
       when is_number(value) do
    rc_assign(rc?, dest, "elmc_new_float", [float_literal_c(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_char, literal: value}}, _slots, rc?, dest, _opts)
       when is_integer(value) do
    assign_owned(rc?, dest, "elmc_new_char(#{value})")
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
    call_opts = if rc?, do: [], else: [consume_args: true]
    {c_args, prep_lines, cleanup_lines} = build_runtime_call_args(:tuple2, args, slots, opts, call_opts)

    call_body =
      if rc? do
        rc_assign(true, dest, "elmc_tuple2", c_args)
      else
        assign_owned(false, dest, "elmc_tuple2_take_value(#{Enum.join(c_args, ", ")})")
      end

    emit_with_ephemeral_cleanup(prep_lines, call_body, cleanup_lines)
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

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :maybe_with_default_int, args: [default, maybe]}},
         slots,
         rc?,
         dest,
         opts
       )
       when is_integer(default) and is_integer(maybe) do
    default_ref = int_operand_ref(default, slots, opts)
    maybe_ref = slot_ref(maybe, slots, opts)
    expr = "elmc_maybe_with_default_int(#{default_ref}, #{maybe_ref})"

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

  defp emit_call_runtime(%{args: %{builtin: id, args: args}} = instr, slots, rc?, dest, opts) do
    sym = runtime_builtin_sym(id, args, slots, opts) || "elmc_unknown"
    core_comment = elm_core_runtime_comment(id)

    cond do
      RuntimeBuiltins.direct_value_return?(id) ->
        {c_args, prep_lines, cleanup_lines} =
          build_runtime_call_args(id, args, slots, opts, consume_args: not rc?)

        call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"

        emit_with_ephemeral_cleanup(
          prep_lines,
          core_comment <> assign_value_return_tail(rc?, dest, call_expr, instr, slots, opts),
          cleanup_lines
        )

      RuntimeBuiltins.c_value_return?(id) and not rc? ->
        {c_args, prep_lines, cleanup_lines} =
          build_runtime_call_args(id, args, slots, opts, consume_args: true)

        sym = non_rc_value_return_symbol(sym)
        call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"

        emit_with_ephemeral_cleanup(
          prep_lines,
          core_comment <> assign_non_rc_c_value_return(dest, call_expr, instr, slots, opts),
          cleanup_lines
        )

      true ->
        {c_args, prep_lines, cleanup_lines} = build_runtime_call_args(id, args, slots, opts)
        call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"

        cond do
          RuntimeBuiltins.c_value_return?(id) ->
            emit_with_ephemeral_cleanup(
              prep_lines,
              core_comment <> assign_owned(rc?, dest, call_expr),
              cleanup_lines
            )

          RuntimeBuiltins.value_return?(id) ->
            assign =
              if not rc? and dest == "*out" do
                assign_value_return_tail(false, dest, call_expr, instr, slots, opts)
              else
                assign_owned(rc?, dest, call_expr)
              end

            emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)

          true ->
            {c_args, prep_lines, cleanup_lines} = build_runtime_call_args(id, args, slots, opts)

            assign =
              if not rc? and dest == "*out" do
                call_expr = "#{value_return_allocator(sym)}(#{Enum.join(c_args, ", ")})"
                assign_value_return_tail(false, dest, call_expr, instr, slots, opts)
              else
                rc_assign(rc?, dest, sym, c_args)
              end

            emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)
        end
    end
  end

  # After record_new_values_take moves field pointers into *out, any bare `owned[i]` named as an
  # array element must be nulled. Do not null operands of `elmc_retain(owned[i])` — those are
  # borrows; the take owns the retained temporary, not the named slot.
  @spec null_owned_slots_named_in_values_array(String.t() | term()) :: Types.ir_expr()

  defp null_owned_slots_named_in_values_array(values_array) when is_binary(values_array) do
    values_array
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(fn
      "owned[" <> rest ->
        case Integer.parse(rest) do
          {idx, "]"} -> [idx]
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq()
    |> Enum.map_join("\n", fn idx -> "owned[#{idx}] = NULL;" end)
  end

  defp null_owned_slots_named_in_values_array(_), do: ""

  @spec elm_core_runtime_comment(atom()) :: Types.ir_expr()

  defp elm_core_runtime_comment(id) when is_atom(id) do
    case Map.get(@elm_core_runtime_targets, id) do
      target when is_binary(target) -> String.trim_leading(ElmCore.comment_line(target))
      _ -> ""
    end
  end

  @spec build_runtime_call_args(Types.ir_expr(), [String.t()], Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp build_runtime_call_args(id, args, slots, opts, call_opts \\ []) do
    consume_args? = Keyword.get(call_opts, :consume_args, false)

    args
    |> Enum.with_index()
    |> Enum.map_reduce({[], []}, fn {arg, index}, {prep, cleanup} ->
      ref =
        cond do
          RuntimeBuiltins.ownership_transfer_arg?(id, index) ->
            slot_ref(arg, slots, opts)

          RuntimeBuiltins.native_int_arg?(id, index) ->
            int_operand_ref(arg, slots, opts)

          true ->
            boxed_value_ref(arg, slots, opts)
        end

      materialize_ephemeral_owned_box(ref, prep, cleanup, consume_args?)
    end)
    |> then(fn {c_args, {prep, cleanup}} -> {c_args, prep, cleanup} end)
  end

  @spec materialize_ephemeral_owned_box(Types.ir_expr() | String.t(), Types.ir_expr(), Types.ir_expr(), boolean() | Types.ir_expr()) :: Types.ir_expr()

  defp materialize_ephemeral_owned_box(ref, prep, cleanup, consume_args?)

  defp materialize_ephemeral_owned_box(ref, prep, cleanup, true) when is_binary(ref) do
    if ephemeral_owned_box?(ref) do
      {ref, {prep, cleanup}}
    else
      materialize_ephemeral_owned_box(ref, prep, cleanup, false)
    end
  end

  defp materialize_ephemeral_owned_box(ref, prep, cleanup, false) when is_binary(ref) do
    if ephemeral_owned_box?(ref) do
      var = "plan_ephemeral_box_#{System.unique_integer([:positive])}"
      {var, {prep ++ ["ElmcValue *#{var} = #{ref};"], cleanup ++ ["elmc_release(#{var});"]}}
    else
      {ref, {prep, cleanup}}
    end
  end

  @spec ephemeral_owned_box?(String.t()) :: boolean()

  defp ephemeral_owned_box?(ref) when is_binary(ref) do
    String.starts_with?(ref, "elmc_new_int_take(") or
      String.starts_with?(ref, "elmc_tuple2_ints_take_value(") or
      String.starts_with?(ref, "elmc_tuple2_take_value(")
  end

  @spec emit_with_ephemeral_cleanup(Types.ir_expr(), pos_integer(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_with_ephemeral_cleanup(prep_lines, call_line, cleanup_lines) do
    (prep_lines ++ List.wrap(call_line) ++ cleanup_lines)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec emit_release(map() | term(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp emit_release(%{args: %{reg: reg}}, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "elmc_release(owned[#{i}]);\nowned[#{i}] = NULL;"
      _ -> ""
    end
  end

  defp emit_release(_, _), do: ""

  @spec emit_call_closure(map(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_call_closure(%{args: %{callee: callee, args: args}}, slots, true, dest, opts) do
    callee_s = slot_ref(callee, slots, opts)
    c_args = Enum.map(args, &slot_ref(&1, slots, opts))
    argc = length(c_args)
    args_var = "plan_closure_argv_#{System.unique_integer([:positive])}"
    # `out` is already ElmcValue ** — pass it directly, never &out (ElmcValue ***).
    dest_ptr = if dest == "*out", do: "out", else: dest
    out_arg = dest_arg(dest_ptr, dest)

    """
    ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{Enum.join(c_args, ", ")} };
    Rc = elmc_closure_call_rc(#{out_arg}, #{callee_s}, #{args_var}, #{argc});
    CHECK_RC(Rc);
    """
    |> String.trim()
  end

  defp emit_call_closure(%{args: %{callee: callee, args: args}} = instr, slots, false, dest, opts) do
    callee_s = slot_ref(callee, slots, opts)
    c_args = Enum.map(args, &slot_ref(&1, slots, opts))
    argc = length(c_args)
    args_var = "plan_closure_argv_#{System.unique_integer([:positive])}"

    call_expr = "elmc_closure_call(#{callee_s}, #{args_var}, #{argc})"

    """
    ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{Enum.join(c_args, ", ")} };
    #{assign_value_return_tail(false, dest, call_expr, instr, slots, opts)}
    """
    |> String.trim()
  end

  @spec emit_call_fn(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_call_fn(%{dest: dest_reg, args: %{module: mod, name: name, args: args} = call_args} = instr, slots, rc?, dest, opts) do
    decl_map = Process.get(:elmc_program_decls, %{})

    cond do
      {mod, name} == {"Main", "clamp"} and length(args) == 3 ->
        emit_basics_clamp_call(dest_reg, args, slots, rc?, dest, opts)

      missing_decl_kernel_log_cmd?(mod, name, args, decl_map) ->
        emit_missing_decl_kernel_log_cmd(dest_reg, name, args, slots, rc?, dest, opts, instr)

      missing_decl_int_builtin?(mod, name, args, decl_map) ->
        emit_missing_decl_int_builtin(dest_reg, name, args, slots, rc?, dest, opts, instr)

      true ->
        emit_call_fn_impl(dest_reg, call_args, slots, rc?, dest, opts, instr)
    end
  end

  @spec missing_decl_int_builtin?(Types.ir_expr(), String.t(), [String.t()], Types.decl_map()) :: boolean()

  defp missing_decl_int_builtin?(mod, name, args, decl_map) do
    is_nil(Map.get(decl_map, {mod, name})) and mod in ["Main", "Basics"] and
      ((name in ["max", "min"] and length(args) == 2) or (name == "not" and length(args) == 1))
  end

  @spec missing_decl_kernel_log_cmd?(Types.ir_expr(), String.t(), [String.t()], Types.decl_map()) :: boolean()

  defp missing_decl_kernel_log_cmd?(mod, name, args, decl_map) do
    is_nil(Map.get(decl_map, {mod, name})) and mod == "Elm.Kernel.PebbleWatch" and
      name in ["logInfoCode", "logWarnCode", "logErrorCode"] and length(args) == 1
  end

  @spec emit_missing_decl_kernel_log_cmd(Types.ir_expr(), String.t(), [String.t()], Types.ir_expr(), boolean(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_missing_decl_kernel_log_cmd(_dest_reg, name, args, slots, rc?, dest, opts, instr) do
    borrows =
      instr
      |> Map.get(:effects, %{})
      |> Map.get(:borrows, [])

    [arg] = args
    code_ref = "elmc_as_int(#{call_site_slot_ref(arg, slots, opts, borrows)})"

    kind =
      case name do
        "logInfoCode" -> "ELMC_PEBBLE_CMD_LOG_INFO_CODE"
        "logWarnCode" -> "ELMC_PEBBLE_CMD_LOG_WARN_CODE"
        "logErrorCode" -> "ELMC_PEBBLE_CMD_LOG_ERROR_CODE"
      end

    out = if dest == "*out", do: "out", else: dest

    if rc? do
      rc_call(true, out, "elmc_cmd1", [kind, code_ref])
    else
      assign_value_return(false, dest, "elmc_cmd1_take(#{kind}, #{code_ref})")
    end
  end

  @spec emit_missing_decl_int_builtin(Types.ir_expr(), String.t(), [String.t()], Types.ir_expr(), boolean(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_missing_decl_int_builtin(dest_reg, name, args, slots, rc?, dest, opts, instr) do
    borrows =
      instr
      |> Map.get(:effects, %{})
      |> Map.get(:borrows, [])

    out = if dest == "*out", do: "out", else: dest

    case name do
      n when n in ["max", "min"] ->
        [left, right] = args
        lhs = "elmc_as_int(#{call_site_slot_ref(left, slots, opts, borrows)})"
        rhs = "elmc_as_int(#{call_site_slot_ref(right, slots, opts, borrows)})"

        expr =
          if n == "max" do
            "(#{lhs} >= #{rhs}) ? #{lhs} : #{rhs}"
          else
            "(#{lhs} <= #{rhs}) ? #{lhs} : #{rhs}"
          end

        emit_int_result_assign(dest_reg, out, rc?, expr, opts)

      "not" ->
        [arg] = args
        ref = "elmc_as_bool(#{call_site_slot_ref(arg, slots, opts, borrows)})"
        rc_assign(rc?, out, "elmc_new_bool", ["(!#{ref}) ? 1 : 0"])
    end
  end

  @spec emit_basics_clamp_call(Types.ir_expr(), [String.t()], Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_basics_clamp_call(_dest_reg, args, slots, _rc?, dest, opts) do
    [low, high, value] = Enum.map(args, &slot_ref(&1, slots, opts))
    "#{dest} = elmc_basics_clamp(#{Enum.join([low, high, value], ", ")});"
  end

  @spec resolve_plan_call_target(Types.ir_expr(), String.t(), Types.decl(), Types.decl_map(), list()) :: Types.ir_expr()

  defp resolve_plan_call_target(mod, name, decl, decl_map, args) when is_list(args) do
    c_name = Util.module_fn_name(mod, name)
    effective_args = FunctionEmit.effective_decl_args(decl || %{}, mod, decl_map)

    if is_map(decl) and args != [] and length(args) > length(effective_args) do
      case FunctionEmit.delegate_call_target(decl, mod, decl_map) do
        {dmod, dname} = target ->
          ddecl = Map.get(decl_map, target)
          dc_name = Util.module_fn_name(dmod, dname)
          {dmod, dname, ddecl, dc_name}

        nil ->
          {mod, name, decl, c_name}
      end
    else
      {mod, name, decl, c_name}
    end
  end

  @spec emit_call_fn_impl(Types.ir_expr(), map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_call_fn_impl(dest_reg, %{module: mod, name: name, args: args}, slots, rc?, dest, opts, instr) do
    decl_map = Process.get(:elmc_program_decls, %{})
    decl = Map.get(decl_map, {mod, name})

    borrows =
      instr
      |> Map.get(:effects, %{})
      |> Map.get(:borrows, [])

    {mod, name, decl, c_name} =
      resolve_plan_call_target(mod, name, decl, decl_map, args)

    dest_ref = if dest == "*out", do: "out", else: dest

    supersedes_native? =
      is_map(decl) and PlanNativeProjection.native_callee_only?(decl, mod, decl_map)

    native_ret =
      cond do
        supersedes_native? -> PlanNativeProjection.native_call_return_kind(decl, mod, decl_map)
        true -> NativeReturn.cached_kind({mod, name})
      end

    direct_plan_call? =
      is_map(decl) and FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map)

    fusion_arg_kinds =
      if direct_plan_call?, do: nil, else: Fusion.rc_native_fusion_arg_kinds({mod, name})

    c_name =
      cond do
        plan_call_uses_native_fusion?(fusion_arg_kinds, rc?, native_ret, mod, name) ->
          "#{c_name}_native"

        supersedes_native? and not NativeReturn.value_return?({mod, name}) ->
          "#{c_name}_native"

        true ->
          c_name
      end

    {prefix, call_arg_s} =
      cond do
        fusion_arg_kinds ->
          {"", rc_native_fusion_call_args(args, fusion_arg_kinds, slots, opts, borrows)}

        native_ret in [:native_int, :native_bool] and decl ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          c_args = call_arg_refs(args, slots, opts, kinds, borrows)
          {"", Enum.join(c_args, ", ")}

        native_ret == :native_int ->
          c_args = Enum.map(args, &int_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", ")}

        native_ret == :native_bool ->
          c_args = Enum.map(args, &bool_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", ")}

        decl && signature_native_direct_args?(decl, mod, decl_map) ->
          kinds = NativeFunctionCall.call_site_arg_kinds(decl, mod, decl_map)

          box_native_int? =
            plan_rc_box_native_int_args?(decl, mod, decl_map, fusion_arg_kinds, native_ret)

          c_args =
            args
            |> Enum.zip(kinds)
            |> Enum.map(fn {arg_reg, kind} ->
              plan_call_site_arg_ref(arg_reg, kind, box_native_int?, slots, opts, borrows)
            end)

          {"", Enum.join(c_args, ", ")}

        decl && FunctionEmit.mixed_direct_abi?(decl, mod, decl_map) ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          c_args = call_arg_refs(args, slots, opts, kinds, borrows)
          {"", Enum.join(c_args, ", ")}

        decl && FunctionCallAbi.argv_abi?(decl, mod, decl_map) ->
          c_args = Enum.map(args, &call_site_slot_ref(&1, slots, opts, borrows))
          {setup, args_var, argc} = FunctionCallAbi.emit_argv_setup("plan", c_args)
          {setup <> "\n", "#{args_var}, #{argc}"}

        true ->
          box_native_int? =
            is_map(decl) and
              plan_rc_box_native_int_args?(decl, mod, decl_map, fusion_arg_kinds, native_ret)

          c_args =
            if is_map(decl) do
              kinds = NativeFunctionCall.call_site_arg_kinds(decl, mod, decl_map)

              args
              |> Enum.zip(kinds)
              |> Enum.map(fn {arg_reg, kind} ->
                plan_call_site_arg_ref(arg_reg, kind, box_native_int?, slots, opts, borrows)
              end)
            else
              if kernel_stub_callee?(mod, c_name, decl) do
                Enum.map(args, &boxed_value_ref(&1, slots, opts))
              else
                Enum.map(args, &call_site_slot_ref(&1, slots, opts, borrows))
              end
            end

          {"", Enum.join(c_args, ", ")}
      end

    folded =
      maybe_emit_folded_union_int_call(
        fusion_arg_kinds,
        mod,
        name,
        args,
        rc?,
        dest,
        opts
      )

    prefix <>
      case folded do
        {:ok, code} ->
          code

        :error ->
          emit_fn_call(
            rc?,
            dest,
            dest_ref,
            dest_reg,
            c_name,
            call_arg_s,
            {mod, name},
            native_ret,
            opts,
            decl,
            plan_rc_boxed_callee?(decl, mod, decl_map, fusion_arg_kinds, native_ret),
            fusion_arg_kinds
          )
      end
  end

  @spec maybe_emit_folded_union_int_call(Types.ir_expr(), Types.ir_expr(), String.t(), term() | [String.t()], Types.ir_expr() | boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr() | nil

  defp maybe_emit_folded_union_int_call(fusion_arg_kinds, mod, name, [arg_reg], true, dest, opts)
       when is_list(fusion_arg_kinds) do
    const_int_regs = Keyword.get(opts, :const_int_regs, %{})

    case Map.get(const_int_regs, arg_reg) |> const_int_value() do
      union_tag when is_integer(union_tag) ->
        case Fusion.union_int_lut_lookup({mod, name}, union_tag) do
          {:ok, wire} ->
            dest_ref = if dest == "*out", do: "out", else: dest
            {:ok, "Rc = elmc_new_int(#{dest_ref}, #{wire});\nCHECK_RC(Rc);"}

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp maybe_emit_folded_union_int_call(_fusion_arg_kinds, _mod, _name, _args, _rc?, _dest, _opts),
    do: :error

  @spec signature_native_direct_args?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp signature_native_direct_args?(decl, _module, _decl_map) do
    is_map(decl) and NativeFunctionCall.signature_has_native_args?(decl)
  end

  @spec plan_boxed_direct_call_abi?(Types.decl(), String.t(), Types.decl_map()) :: boolean()

  defp plan_boxed_direct_call_abi?(decl, module, decl_map) do
    FunctionCallAbi.direct_plan_call_abi?(decl, module, decl_map) or
      (Plan.plan_ir_mode(Process.get(:elmc_codegen_opts, [])) == :primary and
         FunctionCallAbi.primary_lowered?(decl, module, decl_map) and
         not NativeFunctionCall.native_scalar_fn?(decl, module, decl_map))
  end

  @spec plan_rc_boxed_callee?(Types.decl(), String.t(), Types.decl_map(), Types.ir_expr(), Types.ir_expr()) :: boolean()

  defp plan_rc_boxed_callee?(decl, module, decl_map, fusion_arg_kinds, native_ret) do
    !!(
      is_map(decl) and
        is_nil(fusion_arg_kinds) and
        native_ret not in [:native_int, :native_bool] and
        (plan_boxed_direct_call_abi?(decl, module, decl_map) or
           RcRequired.rc_required?(module, Map.get(decl, :name)))
    )
  end

  @spec rc_native_fusion_call_args([String.t()], Types.ir_expr(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp rc_native_fusion_call_args(args, kinds, slots, opts, borrows) do
    args
    |> Enum.zip(kinds)
    |> Enum.map(fn {reg, kind} ->
      case kind do
        :boxed_int_tag ->
          case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
            entry when not is_nil(entry) -> const_int_c_ref(entry, opts)
            _ -> RowMajorLayout.union_tag_expr(call_site_slot_ref(reg, slots, opts, borrows))
          end

        :native_int ->
          case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
            entry when not is_nil(entry) ->
              const_int_c_ref(entry, opts)

            _ ->
              native_int_regs = Keyword.get(opts, :native_int_regs, %{})
              native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

              if Map.has_key?(native_int_regs, reg) or MapSet.member?(native_only, reg) do
                int_call_site_ref(reg, slots, opts, borrows)
              else
                "elmc_as_int(#{call_site_slot_ref(reg, slots, opts, borrows)})"
              end
          end

        _ ->
          call_site_slot_ref(reg, slots, opts, borrows)
      end
    end)
    |> Enum.join(", ")
  end

  @spec call_site_slot_ref(Types.ir_expr(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp call_site_slot_ref(reg, slots, opts, borrows) do
    case borrow_call_param_c_ref(reg, borrows, opts) do
      c_arg when is_binary(c_arg) -> c_arg
      _ -> slot_ref(reg, slots, opts)
    end
  end

  @spec call_arg_refs([String.t()], Types.ir_expr(), keyword(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp call_arg_refs(args, slots, opts, kinds, borrows) do
    args
    |> Enum.zip(kinds)
    |> Enum.map(fn {arg_reg, kind} ->
      case kind do
        :native_int -> int_call_site_ref(arg_reg, slots, opts, borrows)
        :native_bool -> bool_call_site_ref(arg_reg, slots, opts, borrows)
        _ -> plan_call_site_arg_ref(arg_reg, :boxed, false, slots, opts, borrows)
      end
    end)
  end

  @spec plan_call_site_arg_ref(Types.ir_expr(), atom(), boolean(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp plan_call_site_arg_ref(reg, kind, box_native_int?, slots, opts, borrows) do
    case borrow_call_param_c_ref(reg, borrows, opts) do
      c_arg when is_binary(c_arg) ->
        if kind == :boxed do
          boxed_value_ref(reg, slots, opts)
        else
          case {kind, box_native_int?} do
            {:native_int, true} ->
              "elmc_new_int_take(#{int_operand_ref(reg, slots, opts)})"

            {:native_int, false} ->
              int_operand_ref(reg, slots, opts)

            {:native_bool, _} ->
              bool_operand_ref(reg, slots, opts)

            _ ->
              c_arg
          end
        end

      _ ->
        plan_rc_call_arg_ref(reg, kind, box_native_int?, slots, opts)
    end
  end

  @spec borrow_call_param_c_ref(Types.ir_expr() | term(), Types.ir_expr() | term(), keyword() | term()) :: Types.ir_expr()

  defp borrow_call_param_c_ref(reg, borrows, opts)
       when is_integer(reg) and is_list(borrows) do
    if Keyword.get(opts, :closure_mode) do
      nil
    else
      borrow_call_param_c_ref_impl(reg, borrows, opts)
    end
  end

  defp borrow_call_param_c_ref(_, _, _), do: nil

  @spec borrow_call_param_c_ref_impl(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp borrow_call_param_c_ref_impl(reg, borrows, opts) do
    if reg in borrows do
      case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
        %{op: :load_param, args: %{index: index}} ->
          FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

        _ ->
          nil
      end
    else
      nil
    end
  end

  # Always go through int/bool operand refs so a boxed borrow param (`ElmcValue *`)
  # is coerced with `elmc_as_int` / `elmc_as_bool` when the callee wants a native scalar.
  # A bare borrow short-circuit would pass the pointer name into an `elmc_int_t` slot.
  @spec int_call_site_ref(Types.ir_expr(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp int_call_site_ref(reg, slots, opts, _borrows),
    do: int_operand_ref(reg, slots, opts)

  @spec bool_call_site_ref(Types.ir_expr(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp bool_call_site_ref(reg, slots, opts, _borrows),
    do: bool_operand_ref(reg, slots, opts)

  @spec plan_rc_call_arg_ref(Types.ir_expr(), Types.ir_expr() | atom(), Types.ir_expr() | boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp plan_rc_call_arg_ref(reg, :native_int, true, slots, opts),
    do: "elmc_new_int_take(#{int_operand_ref(reg, slots, opts)})"

  defp plan_rc_call_arg_ref(reg, :native_int, false, slots, opts),
    do: int_operand_ref(reg, slots, opts)

  defp plan_rc_call_arg_ref(reg, :native_bool, _boxed_rc?, slots, opts),
    do: bool_operand_ref(reg, slots, opts)

  defp plan_rc_call_arg_ref(reg, :boxed, _boxed_rc?, slots, opts),
    do: boxed_value_ref(reg, slots, opts)

  defp plan_rc_call_arg_ref(reg, _kind, _boxed_rc?, slots, opts),
    do: slot_ref(reg, slots, opts)

  @spec plan_rc_box_native_int_args?(Types.decl(), Types.ir_expr(), Types.decl_map(), Types.ir_expr(), Types.ir_expr()) :: boolean()

  defp plan_rc_box_native_int_args?(decl, mod, decl_map, fusion_arg_kinds, native_ret) do
    plan_rc_boxed_callee?(decl, mod, decl_map, fusion_arg_kinds, native_ret) and
      not FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map)
  end

  @spec fusion_native_rc_callee?(String.t(), Types.ir_expr()) :: boolean()

  defp fusion_native_rc_callee?(c_name, fusion_arg_kinds),
    do: not is_nil(fusion_arg_kinds) and String.ends_with?(c_name, "_native")

  @spec kernel_stub_callee?(Types.ir_expr() | term(), String.t() | term(), Types.ir_expr() | term()) :: boolean()

  defp kernel_stub_callee?("Elm.Kernel", _name, nil), do: true

  defp kernel_stub_callee?(_mod, c_name, nil) when is_binary(c_name),
    do: String.starts_with?(c_name, "elmc_fn_Elm_Kernel_")

  defp kernel_stub_callee?(_, _, _), do: false

  @spec plan_call_uses_native_fusion?(Types.ir_expr(), boolean(), Types.ir_expr(), Types.ir_expr(), String.t()) :: boolean()

  defp plan_call_uses_native_fusion?(fusion_arg_kinds, rc?, native_ret, mod, name) do
    not is_nil(fusion_arg_kinds) and
      (rc? or native_ret in [:native_int, :native_bool] or Fusion.rc_native_only?({mod, name}))
  end

  @spec emit_fn_call(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), String.t(), Types.ir_expr(), term(), Types.ir_expr(), keyword(), Types.decl(), boolean(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_fn_call(
         true,
         dest,
         _dest_ref,
         dest_reg,
         c_name,
         call_arg_s,
         {mod, _name} = callee,
         native_ret,
         opts,
         decl,
         _direct_plan_boxed?,
         fusion_arg_kinds
       ) do
    cond do
      fusion_native_rc_callee?(c_name, fusion_arg_kinds) ->
        rc_call(true, if(dest == "*out", do: "out", else: dest), c_name, call_arg_s)

      native_ret in [:native_int, :native_bool] ->
        emit_native_scalar_fn_call(native_ret, true, dest, dest_reg, c_name, call_arg_s, opts, callee)

      NativeReturn.value_return?(callee) ->
        "#{dest} = #{c_name}(#{call_arg_s});"

      direct_plan_value_return_callee?(decl, mod) ->
        "#{dest} = #{c_name}(#{call_arg_s});"

      legacy_argv_value_callee?(decl, mod, native_ret) ->
        "#{dest} = #{c_name}(#{call_arg_s});"

      true ->
        rc_call(true, if(dest == "*out", do: "out", else: dest), c_name, call_arg_s)
    end
  end

  defp emit_fn_call(
         false,
         dest,
         dest_ref,
         dest_reg,
         c_name,
         call_arg_s,
         {mod, name} = callee,
         native_ret,
         opts,
         decl,
         direct_plan_boxed?,
         fusion_arg_kinds
       ) do
    cond do
      fusion_native_rc_callee?(c_name, fusion_arg_kinds) ->
        rc_callee_from_value_return(dest, dest_ref, c_name, call_arg_s, dest_reg: dest_reg)

      native_ret in [:native_int, :native_bool] ->
        emit_native_scalar_fn_call(native_ret, false, dest, dest_reg, c_name, call_arg_s, opts, callee)

      NativeReturn.value_return?(callee) ->
        assign_value_return(false, dest, "#{c_name}(#{call_arg_s})")

      direct_plan_value_return_callee?(decl, mod) ->
        assign_value_return(false, dest, "#{c_name}(#{call_arg_s})")

      direct_plan_boxed? == true or RcRequired.rc_required?(mod, name) ->
        rc_callee_from_value_return(dest, dest_ref, c_name, call_arg_s, dest_reg: dest_reg)

      legacy_argv_value_callee?(decl, mod, native_ret) ->
        assign_value_return(false, dest, "#{c_name}(#{call_arg_s})")

      true ->
        assign_value_return(false, dest, "#{c_name}(#{call_arg_s})")
    end
  end

  @spec legacy_argv_value_callee?(Types.decl(), String.t(), Types.ir_expr()) :: boolean()

  defp legacy_argv_value_callee?(decl, module, native_ret) do
    decl_map = Process.get(:elmc_program_decls, %{})

    is_map(decl) and native_ret not in [:native_int, :native_bool] and
      FunctionCallAbi.argv_abi?(decl, module, decl_map) and
      not RcRequired.rc_required?(module, Map.get(decl, :name))
  end

  @spec direct_plan_value_return_callee?(Types.decl(), String.t()) :: boolean()

  defp direct_plan_value_return_callee?(decl, module) do
    decl_map = Process.get(:elmc_program_decls, %{})

    is_map(decl) and
      FunctionCallAbi.direct_plan_call_abi?(decl, module, decl_map) and
      not RcRequired.rc_required?(module, Map.get(decl, :name))
  end

  @spec emit_native_scalar_fn_call(Types.ir_expr(), boolean(), Types.ir_expr(), Types.ir_expr(), String.t(), Types.ir_expr(), keyword(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_native_scalar_fn_call(:native_int, rc?, dest, dest_reg, c_name, call_arg_s, opts, {mod, name} = callee) do
    value_return? = NativeReturn.value_return?(callee)
    native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    # Non-RC definitions with a cached native kind still return ElmcValue* (box via
    # elmc_new_int_take). Only RC callees implement the `RC fn(elmc_int_t *out, …)` ABI.
    # Also treat self-recursion inside an RC plan as out-param (unit tests seed
    # plan.rc_required without always populating `:elmc_rc_required`).
    rc_callee? = RcRequired.rc_required?(mod, name) or native_scalar_rc_out_callee?(callee, opts)

    cond do
      value_return? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        "plan_native_int_#{dest_reg} = #{c_name}(#{call_arg_s});"

      # A plain `return` only matches the enclosing function's own ABI when that
      # function is itself compiled without the RC/out-pointer contract. When `rc?`
      # is true, `*out` is the caller's boxed result slot and must be filled via
      # `elmc_new_int`/CHECK_RC, not returned as a raw native value in place of RC.
      value_return? and dest == "*out" and not rc? ->
        "return #{c_name}(#{call_arg_s});"

      not value_return? and not rc_callee? ->
        emit_boxed_value_callee_as_native_int(rc?, dest, dest_reg, c_name, call_arg_s, opts)

      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        out = "plan_native_int_#{dest_reg}"
        rc_scalar_assign_call(rc?, c_name, out, call_arg_s, fallback: "0")

      true ->
        emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, callee)
    end
  end

  defp emit_native_scalar_fn_call(:native_bool, rc?, dest, dest_reg, c_name, call_arg_s, opts, {mod, name} = callee) do
    value_return? = NativeReturn.value_return?(callee)
    native_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    rc_callee? = RcRequired.rc_required?(mod, name) or native_scalar_rc_out_callee?(callee, opts)

    cond do
      value_return? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        "plan_native_bool_#{dest_reg} = #{c_name}(#{call_arg_s});"

      # See the :native_int clause above: only take the raw `return` shortcut when
      # the enclosing function itself is not RC/out-pointer ABI.
      value_return? and dest == "*out" and not rc? ->
        "return #{c_name}(#{call_arg_s});"

      not value_return? and not rc_callee? ->
        emit_boxed_value_callee_as_native_bool(rc?, dest, dest_reg, c_name, call_arg_s, opts)

      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        out = "plan_native_bool_#{dest_reg}"

        """
        bool #{out} = false;
        #{rc_scalar_assign_call(rc?, c_name, out, call_arg_s, fallback: "false")}
        """
        |> String.trim()

      true ->
        emit_native_bool_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, callee)
    end
  end

  defp native_scalar_rc_out_callee?({mod, name}, opts) do
    case Keyword.get(opts, :parent_plan) do
      %{rc_required: true, module: ^mod, name: ^name} ->
        NativeReturn.cached_kind({mod, name}) in [:native_int, :native_bool] and
          not NativeReturn.value_return?({mod, name})

      _ ->
        false
    end
  end

  # Callee is `ElmcValue *fn(...)` but the caller wants a native scalar result.
  defp emit_boxed_value_callee_as_native_int(rc?, dest, dest_reg, c_name, call_arg_s, opts) do
    native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    cond do
      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        tmp = "plan_box_int_#{dest_reg}"

        """
        ElmcValue *#{tmp} = #{c_name}(#{call_arg_s});
        plan_native_int_#{dest_reg} = elmc_as_int(#{tmp});
        elmc_release(#{tmp});
        """
        |> String.trim()

      true ->
        assign_value_return(rc?, dest, "#{c_name}(#{call_arg_s})")
    end
  end

  defp emit_boxed_value_callee_as_native_bool(rc?, dest, dest_reg, c_name, call_arg_s, opts) do
    native_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())

    cond do
      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        tmp = "plan_box_bool_#{dest_reg}"

        """
        ElmcValue *#{tmp} = #{c_name}(#{call_arg_s});
        plan_native_bool_#{dest_reg} = elmc_as_bool(#{tmp});
        elmc_release(#{tmp});
        """
        |> String.trim()

      true ->
        assign_value_return(rc?, dest, "#{c_name}(#{call_arg_s})")
    end
  end

  @spec emit_native_bool_fn_call_boxed(boolean(), Types.ir_expr(), Types.ir_expr(), String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_native_bool_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, {mod, name} = callee) do
    tmp = "plan_call_bool_#{dest_reg}"
    box_dest = if dest == "*out", do: "out", else: dest

    cond do
      NativeReturn.value_return?(callee) ->
        """
        bool #{tmp} = #{c_name}(#{call_arg_s});
        #{rc_assign(rc?, box_dest, "elmc_new_bool", ["(#{tmp}) ? 1 : 0"])}
        """
        |> String.trim()

      not RcRequired.rc_required?(mod, name) ->
        """
        ElmcValue *#{tmp}_box = #{c_name}(#{call_arg_s});
        bool #{tmp} = elmc_as_bool(#{tmp}_box);
        elmc_release(#{tmp}_box);
        #{rc_assign(rc?, box_dest, "elmc_new_bool", ["(#{tmp}) ? 1 : 0"])}
        """
        |> String.trim()

      true ->
        """
        bool #{tmp} = false;
        #{rc_scalar_assign_call(rc?, c_name, tmp, call_arg_s, fallback: "false")}
        #{rc_assign(rc?, box_dest, "elmc_new_bool", ["(#{tmp}) ? 1 : 0"])}
        """
        |> String.trim()
    end
  end

  @spec emit_native_int_fn_call_boxed(boolean(), Types.ir_expr(), Types.ir_expr(), String.t(), Types.ir_expr(), term()) :: Types.ir_expr()

  defp emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, {mod, name} = callee) do
    tmp = "plan_call_int_#{dest_reg}"
    box_dest = if dest == "*out", do: "out", else: dest

    cond do
      NativeReturn.value_return?(callee) ->
        """
        elmc_int_t #{tmp} = #{c_name}(#{call_arg_s});
        #{rc_assign(rc?, box_dest, "elmc_new_int", [tmp])}
        """
        |> String.trim()

      not RcRequired.rc_required?(mod, name) ->
        """
        ElmcValue *#{tmp}_box = #{c_name}(#{call_arg_s});
        elmc_int_t #{tmp} = elmc_as_int(#{tmp}_box);
        elmc_release(#{tmp}_box);
        #{rc_assign(rc?, box_dest, "elmc_new_int", [tmp])}
        """
        |> String.trim()

      true ->
        """
        elmc_int_t #{tmp} = 0;
        #{rc_scalar_assign_call(rc?, c_name, tmp, call_arg_s, fallback: "0")}
        #{rc_assign(rc?, box_dest, "elmc_new_int", [tmp])}
        """
        |> String.trim()
    end
  end

  # RC callers use ambient `Rc` + CHECK_RC (inside CATCH). Non-RC hosts must not.
  @spec rc_scalar_assign_call(boolean(), String.t(), String.t(), String.t(), keyword()) :: String.t()

  defp rc_scalar_assign_call(true, c_name, out_var, call_arg_s, _opts) do
    "Rc = #{c_name}(&#{out_var}#{native_call_suffix(call_arg_s)});\nCHECK_RC(Rc);"
  end

  defp rc_scalar_assign_call(false, c_name, out_var, call_arg_s, opts) do
    fallback = Keyword.get(opts, :fallback, "0")

    """
    {
      RC __call_rc = #{c_name}(&#{out_var}#{native_call_suffix(call_arg_s)});
      if (__call_rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "plan call failed");
        #{out_var} = #{fallback};
      }
    }
    """
    |> String.trim()
  end

  @spec emit_pebble_cmd(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_pebble_cmd(%{args: %{builtin: id, kind: kind, params: params}} = instr, slots, rc?, dest, opts) do
    sym = RuntimeBuiltins.c_symbol(id) || "elmc_cmd0"
    kind_s = Map.get(kind, :c_expr, "0")
    args = Enum.join([kind_s | native_int_param_refs(params, slots, opts)], ", ")

    if rc? do
      rc_call(true, if(dest == "*out", do: "out", else: dest), sym, args)
    else
      take_sym = RcRuntimeEmit.take_wrapper_for(sym) || "#{sym}_take"
      call_expr = "#{take_sym}(#{args})"
      assign_value_return_tail(false, dest, call_expr, instr, slots, opts)
    end
  end

  @spec emit_render_cmd(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_render_cmd(%{args: %{kind: kind, params: params} = args}, slots, rc?, dest, opts) do
    if Map.get(args, :direct_scene_push) == true and Keyword.get(opts, :direct_scene_writer) do
      emit_render_cmd_scene_push(kind, params, slots, opts)
    else
      emit_render_cmd_boxed(kind, params, slots, rc?, dest, opts)
    end
  end

  @spec emit_render_cmd_boxed(atom(), Types.ir_expr(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_render_cmd_boxed(kind, params, slots, rc?, dest, opts) do
    kind_s = platform_kind_c(kind)
    args = Enum.join([kind_s | padded_param_refs(params, 6, slots, opts)], ", ")
    dest_ref = if dest == "*out", do: "out", else: dest
    rc_call(rc?, dest_ref, "elmc_render_cmd6_take", args)
  end

  @spec emit_render_text_cmd(map() | term(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_render_text_cmd(%{args: %{kind: kind, params: params, text: text}}, slots, rc?, dest, opts) do
    kind_s = platform_kind_c(kind)
    int_args = Enum.map(params, &int_operand_ref(&1, slots, opts))
    text_ref = slot_ref(text, slots, opts)
    dest_ref = if dest == "*out", do: "out", else: dest
    args = Enum.join([kind_s | int_args ++ [text_ref]], ", ")
    rc_call(rc?, dest_ref, "elmc_render_text_cmd_take", args)
  end

  defp emit_render_text_cmd(_, _slots, _rc?, _dest, _opts), do: ""

  @spec emit_render_cmd_scene_push(atom(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  @spec emit_list_cursor_map(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

    # `elmc_list_append(a, b)` concatenates two *lists* — when `a` is not a
    # proper ELMC_TAG_LIST cons chain (the `elmc_int_zero()` sentinel used to
    # start the accumulator, or a still-unwrapped scalar from a prior
    # iteration) it falls back to `*out = elmc_retain(b)`, discarding
    # everything accumulated so far. Every mapped `item` (int, string,
    # record, …) must be wrapped as a one-element list (`Cons(item, Nil)`)
    # before appending, and the accumulator must start as a real empty list,
    # or `List.map f (List.range lo hi)` silently keeps only the last mapped
    # element instead of the full list (TcoCaptureClober: `String.join`
    # over a 6-element mapped list saw only a 1-element "list").
    body = """
    ElmcValue *#{fwd_head} = elmc_list_nil();
    for (elmc_int_t #{idx} = #{start_s}; #{idx} <= #{end_s}; #{idx}++) {
      ElmcValue *#{item} = NULL;
      ElmcValue *loop_args[1];
      Rc = elmc_new_int(&loop_args[0], #{idx});
      CHECK_RC(Rc);
      Rc = #{closure}(&#{item}, loop_args, 1, NULL, 0);
      CHECK_RC(Rc);
      elmc_release(loop_args[0]);
      {
        ElmcValue *singleton = NULL;
        Rc = elmc_list_cons(&singleton, #{item}, elmc_list_nil());
        CHECK_RC(Rc);
        elmc_release(#{item});
        #{item} = NULL;
        ElmcValue *next = NULL;
        Rc = elmc_list_append(&next, #{fwd_head}, singleton);
        CHECK_RC(Rc);
        elmc_release(singleton);
        elmc_release(#{fwd_head});
        #{fwd_head} = next;
      }
    }
    """

    if rc? and dest != "*out" do
      body <> "\n#{retain_into_owned(dest_slot, fwd_head)}"
    else
      body <> "\n#{dest_slot} = #{fwd_head};"
    end
  end

  defp emit_pipe_apply_repeat(
         %{dest: dest_reg, args: %{module: mod, name: name, count: count, base: base_reg}},
         slots,
         rc?,
         dest,
         opts
       )
       when is_binary(mod) and is_binary(name) and is_integer(count) and count > 0 and
              is_integer(base_reg) do
    fn_name = Elmc.Backend.CCodegen.Util.module_fn_name(mod, name)
    dest_slot = format_dest(dest_reg, slots, opts)
    loop_id = :erlang.unique_integer([:positive])
    acc = "pipe_acc_#{loop_id}"
    idx = "pipe_i_#{loop_id}"
    next = "pipe_next_#{loop_id}"
    callee = {mod, name}

    case NativeReturn.cached_kind(callee) do
      :native_int ->
        emit_pipe_apply_repeat_native_int(
          fn_name,
          callee,
          base_reg,
          dest_reg,
          dest_slot,
          dest,
          count,
          acc,
          idx,
          next,
          slots,
          rc?,
          opts
        )

      _ ->
        emit_pipe_apply_repeat_boxed(
          fn_name,
          base_reg,
          dest_slot,
          dest,
          count,
          acc,
          idx,
          next,
          slots,
          rc?,
          opts
        )
    end
  end

  defp emit_pipe_apply_repeat_native_int(
         fn_name,
         callee,
         base_reg,
         dest_reg,
         dest_slot,
         dest,
         count,
         acc,
         idx,
         next,
         slots,
         rc?,
         opts
       ) do
    base_ref = int_operand_ref(base_reg, slots, opts)
    native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    keep_native? = is_integer(dest_reg) and MapSet.member?(native_only, dest_reg)
    value_return? = NativeReturn.value_return?(callee)

    loop_body =
      cond do
        value_return? ->
          """
          elmc_int_t #{acc} = #{base_ref};
          for (elmc_int_t #{idx} = 0; #{idx} < #{count}; #{idx}++) {
            #{acc} = #{fn_name}(#{acc});
          }
          """

        rc? ->
          """
          elmc_int_t #{acc} = #{base_ref};
          for (elmc_int_t #{idx} = 0; #{idx} < #{count}; #{idx}++) {
            elmc_int_t #{next};
            Rc = #{fn_name}(&#{next}, #{acc});
            CHECK_RC(Rc);
            #{acc} = #{next};
          }
          """

        true ->
          """
          elmc_int_t #{acc} = #{base_ref};
          for (elmc_int_t #{idx} = 0; #{idx} < #{count}; #{idx}++) {
            elmc_int_t #{next};
            {
              RC __call_rc = #{fn_name}(&#{next}, #{acc});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{fn_name}", "pipe step failed");
                #{next} = 0;
              }
            }
            #{acc} = #{next};
          }
          """
      end

    assign =
      cond do
        keep_native? and dest == "*out" ->
          "return #{acc};"

        keep_native? ->
          "plan_native_int_#{dest_reg} = #{acc};"

        dest == "*out" and rc? ->
          rc_assign(true, "out", "elmc_new_int", [acc])

        dest == "*out" ->
          "return elmc_new_int_take(#{acc});"

        rc? ->
          rc_assign(true, dest_slot, "elmc_new_int", [acc])

        true ->
          "#{dest_slot} = elmc_new_int_take(#{acc});"
      end

    String.trim(loop_body <> "\n" <> assign)
  end

  defp emit_pipe_apply_repeat_boxed(
         fn_name,
         base_reg,
         dest_slot,
         dest,
         count,
         acc,
         idx,
         next,
         slots,
         rc?,
         opts
       ) do
    base_ref = slot_ref(base_reg, slots, opts)

    # Plan-lowered unary callees use direct RC ABI: `RC fn(ElmcValue **out, ElmcValue *arg)`.
    loop_body =
      if rc? do
        """
        ElmcValue *#{acc} = #{base_ref};
        for (elmc_int_t #{idx} = 0; #{idx} < #{count}; #{idx}++) {
          ElmcValue *#{next} = NULL;
          Rc = #{fn_name}(&#{next}, #{acc});
          CHECK_RC(Rc);
          elmc_release(#{acc});
          #{acc} = #{next};
        }
        """
      else
        """
        ElmcValue *#{acc} = #{base_ref};
        for (elmc_int_t #{idx} = 0; #{idx} < #{count}; #{idx}++) {
          ElmcValue *#{next} = #{fn_name}(#{acc});
          elmc_release(#{acc});
          #{acc} = #{next};
        }
        """
      end

    assign =
      cond do
        dest == "*out" ->
          "#{dest_slot} = #{acc};"

        rc? ->
          retain_into_owned(dest_slot, acc)

        true ->
          "#{dest_slot} = #{acc};"
      end

    String.trim(loop_body <> "\n" <> assign)
  end

  @spec emit_pebble_sub(map(), Types.ir_expr(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_pebble_sub(%{args: %{kind: mask, params: params}} = instr, slots, rc?, dest, opts) do
    mask_s = platform_kind_c(mask)
    arity = length(params)
    fn_name = "elmc_sub#{arity}"
    args = Enum.join([mask_s | native_int_param_refs(params, slots, opts)], ", ")

    if rc? do
      rc_call(true, if(dest == "*out", do: "out", else: dest), fn_name, args)
    else
      take_sym = RcRuntimeEmit.take_wrapper_for(fn_name) || "#{fn_name}_take"
      call_expr = "#{take_sym}(#{args})"
      assign_value_return_tail(false, dest, call_expr, instr, slots, opts)
    end
  end

  @spec platform_kind_c(map() | term()) :: Types.ir_expr()

  defp platform_kind_c(%{c_expr: value}) when is_binary(value), do: value
  defp platform_kind_c(%{literal: value}) when is_integer(value), do: Integer.to_string(value)
  defp platform_kind_c(_), do: "0"

  @spec padded_param_refs(Types.ir_expr(), integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp padded_param_refs(params, n, slots, opts) do
    refs = native_int_param_refs(params, slots, opts)
    refs ++ List.duplicate("0", max(0, n - length(refs)))
  end

  @spec native_int_param_refs(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp native_int_param_refs(params, slots, opts) do
    Enum.map(params, fn reg -> int_operand_ref(reg, slots, opts) end)
  end

  @doc false
  @spec int_operand_ref(integer() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  def int_operand_ref(reg, slots, opts) when is_integer(reg), do: int_operand_ref_impl(reg, slots, opts)

  def int_operand_ref(dest, slots, opts) when dest in [:fn_out, :branch_out] do
    "elmc_as_int(#{slot_ref(dest, slots, opts)})"
  end

  @spec int_operand_ref_impl(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp int_operand_ref_impl(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :native_int_inline, %{}), reg) do
      expr when is_binary(expr) ->
        expr

      nil ->
        case peel_native_int_copy_ref(reg, slots, opts) do
          peeled when is_binary(peeled) ->
            peeled

          nil ->
            int_operand_ref_impl_no_copy(reg, slots, opts)
        end
    end
  end

  @spec native_int_borrow_param?(integer(), keyword()) :: boolean()

  defp native_int_borrow_param?(reg, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} ->
        Enum.at(Keyword.get(opts, :param_kinds, []), index) == :native_int

      _ ->
        false
    end
  end

  @spec int_operand_ref_impl_no_copy(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp int_operand_ref_impl_no_copy(reg, slots, opts) when is_integer(reg) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    case Map.get(Keyword.get(opts, :native_int_inline, %{}), reg) do
      expr when is_binary(expr) ->
        expr

      nil ->
        skip? = MapSet.member?(instr_skip_regs(opts), reg)

        cond do
          skip? and MapSet.member?(native_int_only, reg) ->
            skipped_native_int_operand_ref(reg, slots, opts)

          MapSet.member?(native_int_only, reg) and not skip? ->
            native_int_slot_ref(reg, slots, opts)

          MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) ->
            name = Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), reg)
            "(#{name} ? 1 : 0)"

          true ->
            case Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) do
              name when is_binary(name) ->
                name

              nil ->
                case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
                  entry when not is_nil(entry) ->
                    const_int_c_ref(entry, opts)

                  nil ->
                    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
                      %{op: :load_param, args: %{index: index}} ->
                        case Keyword.get(opts, :closure_mode) do
                          %{capture_count: cap} when is_integer(cap) ->
                            if Enum.at(Keyword.get(opts, :param_kinds, []), index) == :native_int do
                              Function.closure_native_int_param_ref(index, cap)
                            else
                              :no_native_param
                            end

                          _ ->
                            case Enum.at(Keyword.get(opts, :param_kinds, []), index) do
                              :native_int ->
                                c_arg =
                                  FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

                                if Map.has_key?(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
                                  "elmc_as_int(#{c_arg})"
                                else
                                  c_arg
                                end

                              _ ->
                                :no_native_param
                            end
                        end

                      _ ->
                        :no_native_param
                    end
                    |> case do
                      c_arg when is_binary(c_arg) ->
                        c_arg

                      _ ->
                        case peel_native_int_operand_ref(reg, slots, opts) do
                          peeled when is_binary(peeled) ->
                            peeled

                      _ ->
                        case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
                          c_arg when is_binary(c_arg) ->
                            if native_int_borrow_param?(reg, opts) do
                              c_arg
                            else
                              "elmc_as_int(#{c_arg})"
                            end

                          _ ->
                            case Map.get(slots, reg) do
                              i when is_integer(i) ->
                                "elmc_as_int(owned[#{i}])"

                              nil ->
                                case Map.get(Keyword.get(opts, :native_bool_regs, %{}), reg) do
                                  name when is_binary(name) -> "(#{name} ? 1 : 0)"
                                  nil -> int_scalar_from_boxed_ref(slot_ref(reg, slots, opts))
                                end
                            end
                        end
                    end
                    end
                end
            end
        end
    end
  end

  @doc false
  @spec switch_subject_ref(non_neg_integer() | :fn_out | :branch_out, Types.slot_map(), keyword()) ::
          String.t()
  def switch_subject_ref(:fn_out, _slots, _opts), do: "*out"
  def switch_subject_ref(:branch_out, _slots, _opts), do: "*out"

  def switch_subject_ref(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
      c_arg when is_binary(c_arg) ->
        c_arg

      _ ->
        case native_param_c_ref(reg, opts) do
          c_arg when is_binary(c_arg) ->
            c_arg

          _ ->
            native_int_regs = Keyword.get(opts, :native_int_regs, %{})
            native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

            if Map.has_key?(native_int_regs, reg) or MapSet.member?(native_int_only, reg) do
              int_operand_ref(reg, slots, opts)
            else
              slot_ref(reg, slots, opts)
            end
        end
    end
  end

  @spec native_param_c_ref(Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp native_param_c_ref(reg, opts) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} ->
        case Enum.at(Keyword.get(opts, :param_kinds, []), index) do
          :native_int ->
            FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

          :native_bool ->
            FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @spec boxed_value_ref(Types.ir_expr() | integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp boxed_value_ref(dest, slots, opts) when dest in [:fn_out, :branch_out],
    do: slot_ref(dest, slots, opts)

  defp boxed_value_ref(reg, slots, opts) when is_integer(reg) do
    if Map.has_key?(slots, reg) and is_nil(native_param_c_ref(reg, opts)) do
      slot_ref(reg, slots, opts)
    else
      case tail_inline_take_expr(reg, slots, opts) do
        expr when is_binary(expr) ->
          expr

        nil ->
          boxed_value_ref_from_const_or_plan(reg, slots, opts)
      end
    end
  end

  @spec boxed_value_ref_from_const_or_plan(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp boxed_value_ref_from_const_or_plan(reg, slots, opts) do
    case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
      entry when not is_nil(entry) ->
        if const_int_bool_lit?(entry) do
          "elmc_new_bool_take(#{const_int_value(entry)})"
        else
          "elmc_new_int_take(#{const_int_c_ref(entry, opts)})"
        end

      nil ->
        boxed_value_ref_from_native_or_defining(reg, slots, opts)
    end
  end

  @spec boxed_value_ref_from_native_or_defining(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp boxed_value_ref_from_native_or_defining(reg, slots, opts) do
    case Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) do
      name when is_binary(name) ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
          "elmc_new_int_take(#{int_operand_ref(reg, slots, opts)})"
        else
          "elmc_new_int_take(#{name})"
        end

      nil ->
        case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
          %{op: :load_param, args: %{index: index}} ->
            param_kinds = Keyword.get(opts, :param_kinds, [])

            cond do
              Enum.at(param_kinds, index, :boxed) == :native_int ->
                ref =
                  Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) ||
                    FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

                "elmc_new_int_take(#{ref})"

              Enum.at(param_kinds, index) == :native_bool ->
                ref =
                  Map.get(Keyword.get(opts, :native_bool_regs, %{}), reg) ||
                    FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

                "elmc_new_bool_take((#{ref}) ? 1 : 0)"

              true ->
                slot_ref(reg, slots, opts)
            end

          %{op: :call_runtime, args: %{builtin: :retain, view_peel: _} = _args} ->
            slot_ref(reg, slots, opts)

          %{op: :call_runtime, args: %{builtin: :retain, args: [src]}}
          when is_integer(src) ->
            boxed_value_ref(src, slots, opts)

          %{op: :const_int, args: %{value: value} = args} when is_integer(value) ->
            if Map.get(args, :bool_lit) == true do
              "elmc_new_bool_take(#{value})"
            else
              "elmc_new_int_take(#{value})"
            end

          %{op: :call_runtime, args: %{builtin: :new_int, literal: value}}
          when is_integer(value) ->
            "elmc_new_int_take(#{value})"

          %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}}
          when is_binary(expr) ->
            "elmc_new_int_take(#{expr})"

          %{op: :call_runtime, args: %{builtin: :new_int, args: [inner]}}
          when is_integer(inner) ->
            case Map.get(Keyword.get(opts, :const_int_regs, %{}), inner) do
              entry when not is_nil(entry) ->
                "elmc_new_int_take(#{const_int_c_ref(entry, opts)})"

              _ ->
                case peel_native_int_operand_ref(inner, slots, opts) do
                  peeled when is_binary(peeled) -> "elmc_new_int_take(#{peeled})"
                  _ -> slot_ref(reg, slots, opts)
                end
            end

          _ ->
            if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
              "elmc_new_int_take(#{int_operand_ref(reg, slots, opts)})"
            else
              slot_ref(reg, slots, opts)
            end
        end
    end
  end

  @spec tail_inline_take_expr(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp tail_inline_take_expr(reg, slots, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :const_int, args: %{value: value} = args} when is_integer(value) ->
        if Map.get(args, :bool_lit) == true do
          "elmc_new_bool_take(#{value})"
        else
          "elmc_new_int_take(#{value})"
        end

      %{args: %{builtin: :tuple2_ints, args: [left, right]}} ->
        "elmc_tuple2_ints_take_value(#{int_operand_ref(left, slots, opts)}, #{int_operand_ref(right, slots, opts)})"

      %{args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
        "elmc_new_int_take(#{value})"

      %{args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
        "elmc_new_int_take(#{expr})"

      %{op: :call_runtime, args: %{builtin: :retain, view_peel: _} = _args} ->
        slot_ref(reg, slots, opts)

      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        boxed_value_ref(src, slots, opts)

      _ ->
        nil
    end
  end

  @spec int_scalar_from_boxed_ref(String.t()) :: Types.ir_expr()

  defp int_scalar_from_boxed_ref(ref) when is_binary(ref) do
    cond do
      String.match?(ref, ~r/^plan_native_int_\d+$/) ->
        ref

      String.match?(ref, ~r/^plan_native_bool_\d+$/) ->
        "(#{ref} ? 1 : 0)"

      String.starts_with?(ref, "const elmc_int_t plan_native_int_") ->
        ref |> String.replace_prefix("const elmc_int_t ", "")

      String.starts_with?(ref, "const bool plan_native_bool_") ->
        name = ref |> String.replace_prefix("const bool ", "")
        "(#{name} ? 1 : 0)"

      true ->
        "elmc_as_int(#{ref})"
    end
  end

  @spec defining_plan_instr(map() | term(), integer() | term()) :: Types.ir_expr()

  defp defining_plan_instr(%{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp defining_plan_instr(_, _), do: nil

  @spec peel_native_int_operand_ref(integer() | term(), Types.ir_expr() | term(), keyword() | term(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp peel_native_int_operand_ref(reg, slots, opts) when is_integer(reg) do
    peel_native_int_operand_ref(reg, slots, opts, MapSet.new())
  end

  defp peel_native_int_operand_ref(reg, slots, opts, visited) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      nil
    else
      visited = MapSet.put(visited, reg)

      case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
        %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
          peel_native_int_operand_ref(src, slots, opts, visited)

        %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
          expr

        %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
          Integer.to_string(value)

        %{op: :call_runtime, args: %{builtin: :new_int, args: [inner]}} when is_integer(inner) ->
          peel_native_int_operand_ref(inner, slots, opts, visited)

        %{op: :load_param, args: %{index: index}} ->
          case Enum.at(Keyword.get(opts, :param_kinds, []), index) do
            :native_int -> FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))
            _ -> nil
          end

        _ ->
          nil
      end
    end
  end

  defp peel_native_int_operand_ref(_, _, _, _), do: nil

  @spec peel_native_int_copy_ref(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp peel_native_int_copy_ref(reg, slots, opts) when is_integer(reg) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    with true <- MapSet.member?(native_int_only, reg),
         %{op: :int_arith, args: args} <- defining_plan_instr(Keyword.get(opts, :parent_plan), reg),
         src when is_integer(src) <- identity_int_arith_source(args) do
      int_operand_ref(src, slots, opts)
    else
      _ -> nil
    end
  end

  @spec identity_int_arith_source(map() | term()) :: Types.ir_expr()

  defp identity_int_arith_source(%{kind: :add_const, lhs: lhs, value: 0}), do: lhs
  defp identity_int_arith_source(%{kind: :sub_const, lhs: lhs, value: 0}), do: lhs
  defp identity_int_arith_source(_), do: nil

  @spec skip_inlined_int_dest?(integer() | term(), keyword() | term()) :: boolean()

  defp skip_inlined_int_dest?(dest_reg, opts) when is_integer(dest_reg) do
    Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), dest_reg)
  end

  defp skip_inlined_int_dest?(_, _), do: false

  @spec bool_operand_ref(integer(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp bool_operand_ref(reg, slots, opts) when is_integer(reg) do
    cond do
      MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) ->
        Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), reg)

      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) ->
        case Map.fetch!(Keyword.get(opts, :const_int_regs, %{}), reg) |> const_int_value() do
          0 -> "false"
          1 -> "true"
          v -> "(#{v} != 0)"
        end

      MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) ->
        "#{int_operand_ref(reg, slots, opts)} != 0"

      true ->
        case plan_defining_instr(Keyword.get(opts, :parent_plan), reg) do
          %{op: :call_runtime, args: %{builtin: :new_bool, literal: value}} when value in [0, 1] ->
            if(value == 1, do: "true", else: "false")

          %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when value in [0, 1] ->
            if(value == 1, do: "true", else: "false")

          _ ->
            ref = slot_ref(reg, slots, opts)
            bool_ref_from_slot(ref)
        end
    end
  end

  defp bool_ref_from_slot("0"), do: "false"
  defp bool_ref_from_slot("1"), do: "true"
  defp bool_ref_from_slot(ref) when is_binary(ref), do: "elmc_as_bool(#{ref})"

  @spec native_int_direct_regs(keyword()) :: Types.ir_expr()

  defp native_int_direct_regs(opts), do: Keyword.get(opts, :native_int_regs, %{})

  @spec non_rc_value_return_symbol(Types.ir_expr()) :: Types.ir_expr()

  defp non_rc_value_return_symbol("elmc_tuple2_take"), do: "elmc_tuple2_take_value"
  defp non_rc_value_return_symbol("elmc_tuple2_ints"), do: "elmc_tuple2_ints_take_value"
  defp non_rc_value_return_symbol("elmc_result_ok_own"), do: "elmc_result_ok_take"
  defp non_rc_value_return_symbol("elmc_result_err_own"), do: "elmc_result_err_take"
  defp non_rc_value_return_symbol(sym), do: sym

  @spec emit_const_static_list(map(), Types.ir_expr(), Types.ir_expr(), boolean(), keyword()) :: Types.ir_expr()

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

  @spec emit_const_static_list_from_regs([String.t()], Types.ir_expr(), Types.ir_expr(), boolean(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_const_static_list_from_regs(args, slots, dest, rc?, values_id, prefix, callee, opts) do
    regs = Map.fetch!(args, :regs)
    count = length(regs)
    array_name = "#{prefix}_#{values_id}"

    refs =
      regs
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {reg, idx} ->
        ref = boxed_value_ref(reg, slots, opts)
        prior = Enum.take(regs, idx)
        if reg in prior, do: "elmc_retain(#{ref})", else: ref
      end)

    """
    ElmcValue *#{array_name}[#{count}] = { #{refs} };
    #{rc_assign(rc?, dest, callee, [array_name, Integer.to_string(count)])}
    """
    |> String.trim()
  end

  @spec emit_const_immortal_string(map(), Types.ir_expr(), boolean()) :: Types.ir_expr()

  defp emit_const_immortal_string(%{args: %{value: value}}, dest, rc?) when is_binary(value) do
    lit_name = "plan_str_immortal_#{System.unique_integer([:positive])}"
    decl = ImmortalStringLiteral.static_decl(lit_name, value)

    assign =
      case {rc?, dest} do
        {true, "*out"} ->
          "*out = &#{lit_name};"

        {true, dest} ->
          "#{dest} = elmc_retain(&#{lit_name});"

        {false, "*out"} ->
          "return (ElmcValue *)&#{lit_name};"

        {false, dest} ->
          "#{dest} = elmc_retain(&#{lit_name});"
      end

    decl <> "\n" <> assign
  end

  @spec emit_platform_static_int(map(), boolean(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_platform_static_int(%{args: args}, rc?, dest, _opts) do
    macro = Map.fetch!(args, :macro)
    then_val = Integer.to_string(Map.fetch!(args, :then))
    else_val = Integer.to_string(Map.fetch!(args, :else))

    """
    #if defined(#{macro})
    #{rc_assign(rc?, dest, "elmc_new_int", [then_val])}
    #else
    #{rc_assign(rc?, dest, "elmc_new_int", [else_val])}
    #endif
    """
    |> String.trim()
  end

  @spec rc_assign(Types.ir_expr(), Types.ir_expr(), String.t(), [String.t()]) :: Types.ir_expr()

  defp rc_assign(true, dest, fn_name, args) do
    dest_ref = if String.starts_with?(dest, "*"), do: "out", else: dest
    call_args = format_call_args(dest_arg(dest_ref, dest), Enum.join(args, ", "))
    "Rc = #{fn_name}(#{call_args});\nCHECK_RC(Rc);"
  end

  defp rc_assign(false, dest, fn_name, args) do
    arg_s = Enum.join(args, ", ")
    call = "#{value_return_allocator(fn_name)}(#{arg_s})"

    case dest do
      "*out" -> "return #{call};"
      _ -> "#{dest} = #{call};"
    end
  end

  @spec value_return_allocator(Types.ir_expr() | String.t()) :: Types.ir_expr()

  defp value_return_allocator("elmc_tuple2_take"), do: "elmc_tuple2_take_value"
  defp value_return_allocator("elmc_maybe_just_own"), do: "elmc_maybe_just_take"
  defp value_return_allocator("elmc_result_ok_own"), do: "elmc_result_ok_take"
  defp value_return_allocator("elmc_result_err_own"), do: "elmc_result_err_take"

  defp value_return_allocator(fn_name) do
    cond do
      fn_name in @rc_allocators_with_take -> "#{fn_name}_take"
      String.ends_with?(fn_name, "_take") -> fn_name
      String.ends_with?(fn_name, "_value") -> fn_name
      true -> "#{fn_name}_take"
    end
  end

  defp emit_load_local(%{dest: dest_reg, args: %{source: src_reg}}, slots, rc?, dest, opts)
       when is_integer(dest_reg) and is_integer(src_reg) do
    src = slot_ref(src_reg, slots, opts)

    case {Map.get(slots, dest_reg), Map.get(slots, src_reg)} do
      {dest_idx, src_idx}
      when is_integer(dest_idx) and is_integer(src_idx) and dest_idx != src_idx ->
        # Owned→owned alias without retain/transfer double-frees on epilogue release.
        if rc? do
          retain_into_owned(dest, src)
        else
          "#{dest} = elmc_retain(#{src});"
        end

      _ ->
        "#{dest} = #{src};"
    end
  end

  defp emit_load_local(%{args: %{source: src_reg}}, slots, _rc?, dest, opts) do
    src = slot_ref(src_reg, slots, opts)
    "#{dest} = #{src};"
  end

  @spec emit_owned_slot_transfer(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), boolean()) :: Types.ir_expr()

  defp emit_owned_slot_transfer(dest_reg, src_reg, slots, dest, src_s, rc?) do
    case {Map.get(slots, dest_reg), Map.get(slots, src_reg)} do
      {dest_idx, src_idx} when is_integer(dest_idx) and is_integer(src_idx) and dest_idx != src_idx ->
        """
        owned[#{dest_idx}] = owned[#{src_idx}];
        owned[#{src_idx}] = NULL;
        """

      _ ->
        assign_value_return(rc?, dest, src_s)
    end
  end

  @spec assign_value_return(Types.ir_expr() | boolean(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp assign_value_return(false, "*out", call_expr), do: "return #{call_expr};"
  defp assign_value_return(_rc?, dest, call_expr), do: "#{dest} = #{call_expr};"

  @spec assign_value_return_tail(Types.ir_expr() | boolean(), Types.ir_expr(), Types.expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp assign_value_return_tail(false, "*out", call_expr, instr, slots, opts),
    do: wrap_non_rc_fn_out_return(call_expr, instr, slots, opts)

  defp assign_value_return_tail(rc?, dest, call_expr, _instr, _slots, _opts),
    do: assign_value_return(rc?, dest, call_expr)

  @spec assign_non_rc_c_value_return(Types.ir_expr(), Types.expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp assign_non_rc_c_value_return("*out", call_expr, instr, slots, opts),
    do: wrap_non_rc_fn_out_return(call_expr, instr, slots, opts)

  defp assign_non_rc_c_value_return(dest, call_expr, _instr, _slots, _opts),
    do: "#{dest} = #{call_expr};"

  @spec wrap_non_rc_fn_out_return(Types.expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp wrap_non_rc_fn_out_return(call_expr, instr, slots, opts) do
    slot_count = Keyword.get(opts, :owned_slot_count, 0)
    cleanup = owned_consume_cleanup_lines(instr, slots, opts)
    cow_drop = non_rc_record_update_cow_drop(instr, slots, opts)

    if slot_count > 0 or cleanup != [] or cow_drop != "" do
      """
      {
        ElmcValue *__ret = #{call_expr};
        elmc_owned_null_aliases(owned, #{slot_count}, __ret);
        #{Enum.join(cleanup ++ List.wrap(cow_drop), "\n")}
        elmc_release_array_lifo(owned, #{slot_count});
        return __ret;
      }
      """
      |> String.trim()
    else
      "return #{call_expr};"
    end
  end

  @spec non_rc_record_update_cow_drop(map() | term(), Types.ir_expr() | term(), keyword() | term()) :: Types.ir_expr()

  defp non_rc_record_update_cow_drop(%{op: :record_update, args: %{base: base_reg}}, slots, _opts)
       when is_integer(base_reg) do
    case Map.get(slots, base_reg) do
      i when is_integer(i) -> "if (__ret == owned[#{i}]) { owned[#{i}] = NULL; }"
      _ -> ""
    end
  end

  defp non_rc_record_update_cow_drop(_, _, _), do: ""

  @spec owned_consume_cleanup_lines(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp owned_consume_cleanup_lines(instr, slots, opts) do
    transfer? = owned_transferring_consume_instr?(instr)

    consumes =
      case Map.get(instr, :effects) do
        %{consumes: consumes} when is_list(consumes) -> consumes
        _ -> []
      end

    deferred = Keyword.get(opts, :native_ret_deferred_regs, MapSet.new())

    consumes
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(opts, :tail_inline_skip_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(deferred, &1))
    |> Enum.uniq()
    |> Enum.map(fn reg ->
      case Map.get(slots, reg) do
        i when is_integer(i) ->
          if transfer? do
            "owned[#{i}] = NULL;"
          else
            "elmc_release(owned[#{i}]);\nowned[#{i}] = NULL;"
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec owned_transferring_consume_instr?(map() | term()) :: boolean()

  defp owned_transferring_consume_instr?(%{op: :const_static_list, args: %{kind: kind}})
       when kind in [:values, :record_array],
       do: true

  defp owned_transferring_consume_instr?(%{op: :call_runtime, args: %{builtin: id}}) do
    id in [:record_new, :record_new_take, :record_new_values_ints, :tuple2_take] or
      RuntimeBuiltins.ownership_transfer?(id)
  end

  defp owned_transferring_consume_instr?(_), do: false

  @spec assign_owned(Types.ir_expr(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

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

  @spec retain_into_owned(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp retain_into_owned(dest, src), do: "#{dest} = elmc_retain(#{src});"

  @spec emit_forward_ref_set(map(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_forward_ref_set(%{args: %{ref: ref, value: value_reg}}, slots, opts) do
    "elmc_forward_ref_set(#{ref}, #{slot_ref(value_reg, slots, opts)});"
  end

  @spec emit_forward_ref_load(map(), Types.ir_expr(), boolean(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_forward_ref_load(%{args: %{ref: ref}}, _slots, rc?, dest) do
    assign_owned(rc?, dest, "elmc_forward_ref_get(#{ref})")
  end

  @spec emit_forward_ref_capture(map(), Types.ir_expr(), boolean(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_forward_ref_capture(%{args: %{ref: ref}}, _slots, rc?, dest) do
    assign_owned(rc?, dest, "elmc_forward_ref_capture(#{ref})")
  end

  @spec emit_forward_ref_load_captured(map(), Types.ir_expr(), boolean(), Types.ir_expr()) :: Types.ir_expr()

  defp emit_forward_ref_load_captured(%{args: args}, _slots, rc?, dest) do
    idx = Map.get(args || %{}, :capture_index, 0)

    assign_owned(
      rc?,
      dest,
      "elmc_forward_ref_get((capture_count > #{idx} && captures[#{idx}] && captures[#{idx}]->tag == ELMC_TAG_FORWARD_REF && captures[#{idx}]->payload) ? *((ElmcForwardRef **)captures[#{idx}]->payload) : NULL)"
    )
  end

  @spec format_call_args(Types.ir_expr(), Types.ir_expr() | [String.t()]) :: Types.ir_expr()

  defp format_call_args(dest_arg, ""), do: dest_arg
  defp format_call_args(dest_arg, args), do: "#{dest_arg}, #{args}"

  @spec native_call_suffix(Types.ir_expr() | [String.t()]) :: Types.ir_expr()

  defp native_call_suffix(""), do: ""
  defp native_call_suffix(args), do: ", #{args}"

  @spec rc_call(Types.ir_expr(), Types.ir_expr(), String.t(), [String.t()]) :: Types.ir_expr()

  defp rc_call(true, dest_ref, fn_name, args) do
    call_args = format_call_args(dest_arg(dest_ref, dest_ref), args)
    "Rc = #{fn_name}(#{call_args});\nCHECK_RC(Rc);"
  end

  defp rc_call(false, dest_ref, fn_name, args) do
    "#{dest_ref} = #{fn_name}(#{args});"
  end

  @spec rc_callee_from_value_return(Types.ir_expr(), Types.ir_expr(), String.t(), [String.t()], keyword()) :: Types.ir_expr()

  defp rc_callee_from_value_return(dest, _dest_ref, fn_name, args, opts) do
    tail? = dest == "*out"
    tmp = rc_call_tmp_var(dest, opts)

    cond do
      not tail? and owned_slot_dest?(dest) ->
        call_args = if args == "", do: "&#{dest}", else: "&#{dest}, #{args}"

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

      tail? ->
        rc_callee_from_value_return_via_tmp(dest, fn_name, args, tmp, value_tail?: true)

      true ->
        rc_callee_from_value_return_via_tmp(dest, fn_name, args, tmp, value_tail?: false)
    end
  end

  @spec owned_slot_dest?(String.t() | term()) :: boolean()

  defp owned_slot_dest?(dest) when is_binary(dest), do: Regex.match?(~r/^owned\[\d+\]$/, dest)
  defp owned_slot_dest?(_), do: false

  @spec rc_call_tmp_var(Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp rc_call_tmp_var(dest, opts) do
    case Keyword.get(opts, :dest_reg) do
      reg when is_integer(reg) ->
        "__rc_call_#{reg}"

      _ ->
        case Regex.run(~r/^owned\[(\d+)\]$/, dest) do
          [_, idx] ->
            "__rc_call_owned_#{idx}"

          _ ->
            n = Process.get(:elmc_rc_call_tmp_counter, 0)
            Process.put(:elmc_rc_call_tmp_counter, n + 1)
            "__rc_call_#{n}"
        end
    end
  end

  @spec rc_callee_from_value_return_via_tmp(Types.ir_expr(), String.t(), [String.t()], Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp rc_callee_from_value_return_via_tmp(dest, fn_name, args, tmp, opts) do
    value_tail? = Keyword.get(opts, :value_tail?, false)
    call_args = if args == "", do: "&#{tmp}", else: "&#{tmp}, #{args}"

    publish = if value_tail?, do: "", else: "#{dest} = #{tmp};"

    fail_stmt =
      if value_tail? do
        "return elmc_int_zero();"
      else
        "#{publish}\n        #{tmp} = elmc_int_zero();"
      end

    return_stmt = if value_tail?, do: "return #{tmp};", else: ""

    """
    ElmcValue *#{tmp} = NULL;
    {
      RC __call_rc = #{fn_name}(#{call_args});
      if (__call_rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(__call_rc, "#{fn_name}", "plan call failed");
        #{fail_stmt}
      }
      #{publish}
    }
    #{return_stmt}
    """
    |> String.trim()
  end

  @spec dest_arg(Types.ir_expr(), term()) :: Types.ir_expr()

  defp dest_arg("out", _), do: "out"
  defp dest_arg(dest_ref, _), do: "&#{dest_ref}"

  @spec cow_drop_alias_null(Types.ir_expr() | term(), Types.ir_expr() | term(), boolean() | term(), Types.ir_expr() | term(), keyword() | term()) :: Types.ir_expr()

  defp cow_drop_alias_null(dest, base_reg, retain_copy?, slots, opts)
       when is_integer(base_reg) and is_boolean(retain_copy?) do
    case Map.get(slots, base_reg) do
      base_idx when is_integer(base_idx) ->
        dest_s = format_dest(dest, slots, opts)
        base_s = slot_ref(base_reg, slots, opts)

        if dest_s != base_s do
          if retain_copy? do
            """
            if (#{dest_s} == #{base_s}) {
              #{dest_s} = elmc_retain(#{dest_s});
            }
            #{base_s} = NULL;
            """
            |> String.trim()
          else
            "#{base_s} = NULL;"
          end
        else
          ""
        end

      _ ->
        ""
    end
  end

  defp cow_drop_alias_null(_, _, _, _, _), do: ""

  @spec format_dest(Types.ir_expr() | integer(), term() | Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  @spec emit_make_closure(Types.ir_expr(), Types.ir_expr(), keyword(), boolean(), Types.ir_expr()) :: Types.ir_expr()

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
      call_expr =
        "elmc_closure_new_take(#{closure_fn}, #{arity}, #{cap_count}, #{cap_arg})"

      """
      #{cap_array_code}
      #{assign_value_return_tail(false, dest, call_expr, instr, slots, opts)}
      """
      |> String.trim()
    end
  end

  @spec emit_op_only(map() | term(), Types.ir_expr(), keyword()) :: Types.ir_expr()

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

  defp emit_op_only(%Types{op: :catch_begin}, _slots, _opts), do: "CATCH_BEGIN"
  defp emit_op_only(%Types{op: :catch_end}, _slots, _opts), do: "CATCH_END"
  defp emit_op_only(_, _slots, _opts), do: ""

  @spec emit_load_param_copy(map(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp emit_load_param_copy(%Types{op: :load_param, dest: dest_reg, args: %{index: index}}, slots, opts) do
    params = Keyword.get(opts, :params, [])
    param_kinds = Keyword.get(opts, :param_kinds, [])
    dest = slot_var(dest_reg, slots)
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

          # Owned scratch for a boxed param must retain. Aliasing (`owned[i] = param`)
          # then publishing to *out makes the caller double-free / use-after-free when
          # it releases both the arg and the result (EscapeDictReturnShape identity).
          rc? ->
            retain_into_owned(dest, c_arg)

          true ->
            "#{dest} = #{c_arg};"
        end
    end
  end

  @spec publish_fn_out(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp publish_fn_out(reg, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, false)
    src = slot_ref(reg, slots, opts)
    native_int? = MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg)

    cond do
      rc? ->
        publish_fn_out_rc(reg, slots, src, opts)

      native_int? ->
        publish_native_int_return(src, opts)

      true ->
        publish_fn_out_value(reg, slots, src, opts)
    end
  end

  @spec publish_fn_out_rc(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp publish_fn_out_rc(reg, slots, src, opts) do
    case Map.get(slots, reg) do
      i when is_integer(i) ->
        "*out = #{src};\nowned[#{i}] = NULL;"

      nil ->
        # Direct borrow-param publish: *out is owned by the caller.
        if Map.has_key?(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
          "*out = elmc_retain(#{src});"
        else
          "*out = #{src};"
        end
    end
  end

  @spec publish_native_int_return(Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp publish_native_int_return(src, opts) do
    slot_count = Keyword.get(opts, :owned_slot_count, 0)

    if slot_count > 0 do
      """
      {
        ElmcValue *__ret = elmc_new_int_take(#{src});
        elmc_release_array_lifo(owned, #{slot_count});
        return __ret;
      }
      """
      |> String.trim()
    else
      "return elmc_new_int_take(#{src});"
    end
  end

  @spec publish_fn_out_value(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp publish_fn_out_value(reg, slots, src, opts) do
    slot_count = Keyword.get(opts, :owned_slot_count, 0)

    case Map.get(slots, reg) do
      i when is_integer(i) ->
        if slot_count > 0 do
          """
          {
            ElmcValue *__ret = #{src};
            owned[#{i}] = NULL;
            elmc_release_array_lifo(owned, #{slot_count});
            return __ret;
          }
          """
          |> String.trim()
        else
          "return #{src};"
        end

      nil ->
        # Borrowed param/capture/tmp: caller owns the returned value.
        if slot_count > 0 do
          """
          {
            ElmcValue *__ret = elmc_retain(#{src});
            elmc_release_array_lifo(owned, #{slot_count});
            return __ret;
          }
          """
          |> String.trim()
        else
          "return elmc_retain(#{src});"
        end
    end
  end

  @spec slot_var(integer(), Types.ir_expr()) :: Types.ir_expr()

  defp slot_var(reg, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "owned[#{i}]"
      _ -> "tmp_#{reg}"
    end
  end

  @spec slot_ref(integer() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp slot_ref(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
      c_arg when is_binary(c_arg) ->
        c_arg

      _ ->
        case Map.get(slots, reg) do
          i when is_integer(i) ->
            "owned[#{i}]"

          nil ->
            case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
              entry when not is_nil(entry) ->
                const_int_c_ref(entry, opts)

              _ ->
                case Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) do
                  name when is_binary(name) ->
                    name

                  _ ->
                    case Map.get(Keyword.get(opts, :native_bool_regs, %{}), reg) do
                      name when is_binary(name) ->
                        name

                  _ ->
                    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
                      %{op: :const_int, args: %{value: value}} when is_integer(value) ->
                        Integer.to_string(value)

                      _ ->
                        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
                          "plan_native_int_#{reg}"
                        else
                          "tmp_#{reg}"
                        end
                    end
                    end
                end
            end

          _ ->
            "tmp_#{reg}"
        end
    end
  end

  defp slot_ref(:fn_out, _slots, _opts), do: "*out"
  defp slot_ref(:branch_out, _slots, _opts), do: "*out"

  @spec record_new_suffix(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp record_new_suffix(dest_reg, instr_id) do
    base =
      cond do
        is_integer(instr_id) -> instr_id
        is_integer(dest_reg) -> dest_reg
        dest_reg in [:fn_out, :branch_out] -> 0
        true -> 0
      end

    seq = System.unique_integer([:monotonic, :positive])
    "#{base}_#{seq}"
  end

  @spec record_values_array(Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp record_values_array(field_regs, slots, opts) do
    {entries, _} =
      Enum.map_reduce(field_regs, [], fn reg, prior_refs ->
        ref = record_field_value_ref(reg, slots, opts)

        # Deduplicate by C ref (owned slot), not only by plan reg — slot packing can map
        # two field regs onto the same owned[i]; take must not steal one pointer twice.
        entry =
          if is_binary(ref) and ref in prior_refs do
            "elmc_retain(#{ref})"
          else
            ref
          end

        {entry, [ref | prior_refs]}
      end)

    Enum.join(entries, ", ")
  end

  @spec record_field_value_ref(integer() | Types.ir_expr(), Types.ir_expr(), keyword()) :: Types.ir_expr()

  defp record_field_value_ref(reg, slots, opts) when is_integer(reg) do
    # Do not peel through retain copies here: record_new_values_take consumes `reg` and the
    # values array must name that same owned slot. Peeling to the retain source would take the
    # source while emit_null only clears the dest → double-free.
    case Map.get(slots, reg) do
      i when is_integer(i) ->
        "owned[#{i}]"

      _ ->
        boxed_value_ref(reg, slots, opts)
    end
  end

  defp record_field_value_ref(reg, slots, opts),
    do: slot_ref(reg, slots, opts)

  @spec resolve_record_field_names(Types.ir_expr(), non_neg_integer(), String.t()) :: Types.ir_expr()

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

  @spec lookup_record_shape_type(String.t(), String.t()) :: Types.ir_expr()

  defp lookup_record_shape_type(type, module) when is_binary(type) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    short = type |> String.split(".") |> List.last()

    Map.get(shapes, {module, type}) ||
      Map.get(shapes, {module, short}) ||
      Enum.find_value(shapes, fn {{m, name}, fields} ->
        if m == module and name in [type, short], do: fields
      end)
  end

  @spec infer_record_shape_by_count(non_neg_integer() | integer(), Types.ir_expr() | String.t()) :: Types.ir_expr()

  defp infer_record_shape_by_count(_count, nil), do: nil

  defp infer_record_shape_by_count(count, module) when is_integer(count) and is_binary(module) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case Enum.filter(shapes, fn {{m, _name}, fields} -> m == module and length(fields) == count end) do
      [{{_, _}, fields}] -> fields
      _ -> nil
    end
  end

  @spec record_get_index_ref(String.t(), String.t()) :: Types.ir_expr()

  defp record_get_index_ref(field, index) when is_binary(field) and is_binary(index) do
    case Integer.parse(index) do
      {_, ""} -> "#{index} /* #{Util.escape_c_comment(field)} */"
      _ -> index
    end
  end

  @doc false
  @spec idiv_c_expr(String.t(), String.t()) :: String.t()
  def idiv_c_expr(lhs_s, rhs_s) when is_binary(lhs_s) and is_binary(rhs_s) do
    # Elm floor-div via helper; omit the old `(d == 0 ? 0 : n / d)` ternary.
    case parse_int_literal(String.trim(rhs_s)) do
      {:ok, 0} -> "0"
      _ -> "elmc_int_idiv(#{lhs_s}, #{rhs_s})"
    end
  end

  @doc false
  @spec elm_mod_by_c_expr(String.t(), String.t()) :: String.t()
  def elm_mod_by_c_expr(base_s, value_s) do
    value_s = parenthesize_mod_value(value_s)
    opts = Process.get(:elmc_codegen_opts, %{})
    fast? = Elmc.Backend.SizeProfile.mod_by_fast?(opts)

    case parse_int_literal(base_s) do
      {:ok, 0} ->
        "0"

      {:ok, base} when base > 0 and fast? ->
        # GNU statement-expr: last expression must be a statement (trailing ';').
        "(({ elmc_int_t __elmc_mod_v = (#{value_s}); ((__elmc_mod_v % #{base}) + #{base}) % #{base}; }))"

      {:ok, base} ->
        correction = mod_abs_addend(base)
        "({ elmc_int_t __elmc_mod_v = (#{value_s}); elmc_int_t __elmc_mod_r = __elmc_mod_v % #{base}; (__elmc_mod_r < 0 ? __elmc_mod_r + (elmc_int_t)#{correction} : __elmc_mod_r); })"

      :dynamic ->
        "(#{base_s} == 0 ? 0 : (((elmc_int_t)(#{value_s} % #{base_s})) < 0 ? ((elmc_int_t)(#{value_s} % #{base_s})) + (elmc_int_t)#{mod_abs_addend_expr(base_s)} : (elmc_int_t)(#{value_s} % #{base_s})))"
    end
  end

  @spec mod_abs_addend(integer() | Types.ir_expr()) :: Types.ir_expr()

  defp mod_abs_addend(base) when is_integer(base) and base > 0, do: Integer.to_string(base)
  defp mod_abs_addend(base) when is_integer(base) and base < 0, do: Integer.to_string(-base)
  defp mod_abs_addend(0), do: "0"

  @spec mod_abs_addend_expr(Types.ir_expr()) :: Types.ir_expr()

  defp mod_abs_addend_expr(base_s), do: "(#{base_s} < 0 ? -#{base_s} : #{base_s})"

  @spec parse_int_literal(String.t()) :: Types.ir_expr()

  defp parse_int_literal(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> {:ok, n}
      _ -> :dynamic
    end
  end

  @spec native_int_repeat_count?(integer(), keyword()) :: boolean()

  defp native_int_repeat_count?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg)
  end

  @spec parenthesize_mod_value(String.t()) :: Types.ir_expr()

  defp parenthesize_mod_value(value_s) when is_binary(value_s) do
    trimmed = String.trim(value_s)

    if trimmed != "" and not String.starts_with?(trimmed, "(") and
         String.match?(trimmed, ~r/[+\-*]/) do
      "(#{trimmed})"
    else
      trimmed
    end
  end

  @spec const_int_value(integer() | term()) :: Types.ir_expr()

  defp const_int_value(value) when is_integer(value), do: value
  defp const_int_value({value, _ctor}) when is_integer(value), do: value
  defp const_int_value({value, _ctor, _bool_lit?}) when is_integer(value), do: value
  defp const_int_value(_), do: nil

  @spec const_int_c_ref(integer() | term(), keyword()) :: Types.ir_expr()

  defp const_int_c_ref(value, opts)

  defp const_int_c_ref(value, _opts) when is_integer(value), do: Integer.to_string(value)

  defp const_int_c_ref({value, ctor}, opts) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, plan_module_from(opts))

  defp const_int_c_ref({value, ctor, _bool_lit?}, opts) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, plan_module_from(opts))

  defp const_int_bool_lit?({_value, _ctor, true}), do: true
  defp const_int_bool_lit?(_), do: false

  @spec plan_module_from(keyword()) :: Types.ir_expr()

  defp plan_module_from(opts) do
    Keyword.get(opts, :module) ||
      case Keyword.get(opts, :parent_plan) do
        %{module: mod} when is_binary(mod) -> mod
        _ -> nil
      end
  end
end
