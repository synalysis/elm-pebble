defmodule Elmc.Backend.C.Lower.Instr do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.C.Lower.{
    EphemeralBox,
    Function,
    IntListFilterPred,
    Lambda,
    ListAccumulate,
    NativeReturn,
    NativeIntFold,
    TagRefs
  }
  alias Elmc.Backend.CCodegen.{
    FunctionCallAbi,
    FunctionEmit,
    Fusion,
    Host,
    ImmortalStringLiteral,
    PlanNativeProjection,
    RecordCompile,
    RcRequired,
    RcRuntimeEmit,
    RetainOperandAlias,
    RowMajorLayout
  }
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.Plan.Lower.SpecialValues.ElmCore
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

  @spec emit(Types.t(), Types.slot_map(), keyword()) :: String.t()
  def emit(%Types{op: op} = instr, slots, opts)
      when op in [:catch_begin, :catch_end, :publish, :load_param],
      do: emit_op_only(instr, slots, opts)

  def emit(%Types{op: :phi} = instr, slots, opts), do: emit_phi(instr, slots, opts)

  def emit(%Types{dest: dest} = instr, slots, opts) when is_integer(dest) do
    emit_unless_skipped(MapSet.member?(instr_skip_regs(opts), dest), instr, slots, opts)
  end

  def emit(%Types{} = instr, slots, opts), do: emit_instr(instr, slots, opts)

  defp emit_unless_skipped(true, _instr, _slots, _opts), do: ""
  defp emit_unless_skipped(_skip?, instr, slots, opts), do: emit_instr(instr, slots, opts)

  @spec instr_skip_regs(keyword()) :: MapSet.t(Types.reg())

  defp instr_skip_regs(opts) do
    Keyword.get(opts, :fused_string_skip_regs, MapSet.new())
    |> MapSet.union(Keyword.get(opts, :tail_inline_skip_regs, MapSet.new()))
  end

  @spec emit_instr(Types.t(), Types.slot_map(), keyword()) :: String.t()

  defp emit_instr(%Types{op: op} = instr, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    dest = format_dest(instr.dest, slots, opts)

    case op do
      :const_int ->
        native_only? =
          MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest)

        fusion_skip? =
          MapSet.member?(Keyword.get(opts, :fusion_native_literal_regs, MapSet.new()), instr.dest)

        cond do
          fusion_skip? ->
            ""

          # Bool True/False must box as TAG_BOOL even if a reg was also marked
          # native-int (CommonConstCallArms / phi demotion must not win here).
          # Native-bool dests stay i32 so nested if/phi does not heap-allocate.
          Map.get(instr.args, :bool_lit) == true ->
            lit = bool_c_literal(instr.args.value)

            cond do
              MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), instr.dest) ->
                emit_native_bool_store(instr.dest, dest, lit, opts)

              dest == "*out" and Keyword.get(opts, :native_scalar_out) == :native_bool ->
                "*out = #{lit};"

              true ->
                rc_assign(rc?, dest, "elmc_new_bool", [lit])
            end

          native_only? ->
            value =
              case Map.get(instr.args, :union_ctor) do
                ctor when is_binary(ctor) ->
                  TagRefs.const_int_ref(instr.args.value, ctor, plan_module_from(opts))

                _ ->
                  Integer.to_string(instr.args.value)
              end

            emit_native_const_def(instr.dest, dest, value, opts)

          true ->
            rc_assign(rc?, dest, "elmc_new_int", [Integer.to_string(instr.args.value)])
        end

      :const_c_expr ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest) do
          emit_native_const_def(instr.dest, dest, Map.fetch!(instr.args, :value), opts)
        else
          rc_assign(rc?, dest, "elmc_new_int", [Map.fetch!(instr.args, :value)])
        end

      :platform_static_int ->
        emit_platform_static_int(instr, rc?, dest, opts)

      :platform_static_bool ->
        emit_platform_static_bool(instr, rc?, dest, opts)

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
        # Borrow into the plan-owned slot. Do not retain/mark here: retaining every
        # field get leaks 2048 list spines, and blanket borrow-marks null live
        # append intermediates. Callers that cow_drop a borrowed record base use
        # emit_record_update_borrow_base/5 instead.
        assign_value_return(rc?, dest, "elmc_record_get_index(#{base}, #{index})")

      :record_update ->
        emit_record_update(instr, slots, rc?, dest, opts)

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

      :test_list_length_gte ->
        min = Map.fetch!(instr.args, :min)

        emit_native_bool_test(instr, slots, rc?, dest, opts, fn subject ->
          "(elmc_list_length_native(#{subject}) >= #{min})"
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

      :list_walk_map ->
        emit_list_walk_map(instr, slots, rc?, dest, opts)

      :pipe_apply_repeat ->
        emit_pipe_apply_repeat(instr, slots, rc?, dest, opts)

      :pebble_sub ->
        emit_pebble_sub(instr, slots, rc?, dest, opts)

      :tuple_proj ->
        base = slot_ref(instr.args.base, slots, opts)

        base_borrowed? =
          instr
          |> Map.get(:effects, %{})
          |> Map.get(:borrows, [])
          |> then(&(instr.args.base in &1))

        {proj_fn, native_proj_fn} =
          case instr.args.which do
            :first ->
              if base_borrowed? do
                {"elmc_tuple_first_borrow", "elmc_as_int(elmc_tuple_first_borrow(#{base}))"}
              else
                {"elmc_tuple_first", "elmc_as_int(elmc_tuple_first(#{base}))"}
              end

            :second ->
              if base_borrowed? do
                {"elmc_tuple_second_borrow", "elmc_as_int(elmc_tuple_second_borrow(#{base}))"}
              else
                {"elmc_tuple_second", "elmc_as_int(elmc_tuple_second(#{base}))"}
              end
          end

        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), instr.dest) do
          emit_native_store(instr.dest, dest, native_proj_fn, opts)
        else
          # Mark after assign: assign_value_return clears stale borrow marks on slot reuse.
          assign = assign_value_return(rc?, dest, "#{proj_fn}(#{base})")

          if base_borrowed? and owned_slot_dest?(dest) do
            RecordCompile.mark_borrowed_owned_ref(dest)
          end

          assign
        end

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
  @spec branch_cond_expr(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

  def branch_cond_expr(reg, slots, opts) when is_integer(reg), do: branch_cond_expr_impl(reg, slots, opts)

  def branch_cond_expr(dest, slots, opts) when dest in [:fn_out, :branch_out] do
    "elmc_as_bool(#{slot_ref(dest, slots, opts)})"
  end

  @spec branch_cond_expr_impl(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec emit_phi(Types.t() | map(), Types.slot_map(), keyword()) :: String.t()

  defp emit_phi(%{dest: dest_reg, args: args = %{then: then_reg, else: else_reg, cond: cond_reg}}, slots, opts) do
    # Dual-out `(List Int, Int)` already wrote `*out_list`/`*out_int` on each arm.
    if MapSet.member?(
         Keyword.get(opts, :native_list_int_pair_pair_regs, MapSet.new()),
         dest_reg
       ) do
      ""
    else
      emit_phi_body(dest_reg, args, then_reg, else_reg, cond_reg, slots, opts)
    end
  end

  defp emit_phi_body(dest_reg, args, then_reg, else_reg, cond_reg, slots, opts) do
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

      # truthy_native arms may be dropped after shapes are stamped. Always reconstruct
      # from shapes when publishing to a boxed merge — including when `cond` is still a
      # boxed Bool (`elmc_as_bool(owned[…])`). Requiring native_bool_cond? left
      # `elmc_retain(tmp_N)` for dropped const/compare arms (game_jump_n_run Main.step).
      Map.get(args, :truthy_native) == true ->
        then_s = truthy_shape_boxed_c_expr(Map.fetch!(args, :then_shape), slots, opts)
        else_s = truthy_shape_boxed_c_expr(Map.fetch!(args, :else_shape), slots, opts)

        """
        if (#{cond_expr}) {
          #{phi_boxed_arm_assign(rc?, merge, then_s, opts)}
        } else {
          #{phi_boxed_arm_assign(rc?, merge, else_s, opts)}
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

  @spec phi_arm_assign(boolean(), String.t(), Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp phi_arm_assign(rc?, merge, reg, slots, opts) do
    src = phi_boxed_arm_source(reg, slots, opts)
    borrow_retain? = Map.has_key?(Keyword.get(opts, :borrow_param_regs, %{}), reg)
    phi_boxed_arm_assign(rc?, merge, src, Keyword.merge(opts, borrow_retain?: borrow_retain?))
  end

  # Native-int params / locals must be boxed when merging into an owned slot — never `elmc_retain`
  # on an `elmc_int_t` C value. Prefer an existing owned slot when the reg was already boxed
  # (e.g. native-int param with boxed phi uses).
  @spec phi_boxed_arm_source(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

  defp phi_boxed_arm_source(reg, slots, opts) when is_integer(reg) do
    native_int_regs = Keyword.get(opts, :native_int_regs, %{})
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    native_bool_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    native_bool_regs = Keyword.get(opts, :native_bool_regs, %{})
    const_int_regs = Keyword.get(opts, :const_int_regs, %{})

    cond do
      is_integer(Map.get(slots, reg)) ->
        slot_ref(reg, slots, opts)

      MapSet.member?(native_bool_only, reg) or Map.has_key?(native_bool_regs, reg) ->
        # Never `elmc_retain` a C `bool` — box into an ephemeral Bool value.
        EphemeralBox.bool(phi_truthy_arm_expr(reg, slots, opts))

      MapSet.member?(native_int_only, reg) ->
        boxed_value_ref(reg, slots, opts)

      Map.has_key?(native_int_regs, reg) ->
        boxed_value_ref(reg, slots, opts)

      Map.has_key?(const_int_regs, reg) ->
        boxed_value_ref(reg, slots, opts)

      true ->
        case slot_ref(reg, slots, opts) do
          "plan_native_bool_" <> _ = bool_ref ->
            EphemeralBox.bool(bool_ref)

          other ->
            other
        end
    end
  end

  defp phi_boxed_arm_source(reg, slots, opts), do: slot_ref(reg, slots, opts)

  @spec phi_boxed_arm_assign(boolean(), String.t(), String.t(), keyword()) :: String.t()

  defp phi_boxed_arm_assign(rc?, merge, src, opts) do
    borrow_retain? = Keyword.get(opts, :borrow_retain?, false)
    materialize_opts = Keyword.put_new(opts, :rc_required, rc?)
    {src, prep, cleanup} = materialize_ephemeral_src(src, materialize_opts)

    retain? =
      cond do
        rc? and String.contains?(src, "_take(") -> false
        rc? -> true
        borrow_retain? -> true
        assignable_owned_slot_ref?(src) and merge != src -> true
        true -> false
      end

    body = phi_owned_merge_assign(rc?, merge, src, retain: retain?, borrow_retain?: borrow_retain?)

    if prep == [] and cleanup == [] do
      body
    else
      emit_with_ephemeral_cleanup(prep, body, cleanup)
    end
  end

  @spec phi_owned_merge_assign(boolean(), String.t(), String.t(), keyword()) :: String.t()

  defp phi_owned_merge_assign(rc?, merge, src, opts) do
    retain? = Keyword.get(opts, :retain, false)
    borrow_retain? = Keyword.get(opts, :borrow_retain?, false)
    src_owned? = assignable_owned_slot_ref?(src)
    merge_dead? = phi_merge_dest_dead?(merge)
    src_live? = phi_owned_src_live?(src)

    # Transfer (move + null src) is only safe when the source slot has no further
    # uses. Otherwise keep the source live and retain into the merge (e.g. Set
    # `next = if … then remove else withInsert` followed by `Set.member … withInsert`).
    use_transfer? =
      merge_dead? and src_owned? and retain? and not borrow_retain? and merge != src and
        not src_live?

    cond do
      use_transfer? and RecordCompile.borrowed_owned_ref?(src) ->
        RecordCompile.mark_borrowed_owned_ref(merge)

      owned_slot_dest?(merge) ->
        RecordCompile.clear_borrowed_owned_ref(merge)

      true ->
        :ok
    end

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

    # Exclusive merge slots start empty (live reset per block). Previous values
    # stay for epilogue LIFO — never mid-body `elmc_release(owned[…])`.
    "#{assign}#{null_src}"
    |> String.trim()
  end

  @spec phi_merge_dest_dead?(String.t()) :: boolean()
  defp phi_merge_dest_dead?(merge), do: not phi_merge_dest_live?(merge)

  @spec phi_merge_dest_live?(String.t()) :: boolean()

  defp phi_merge_dest_live?(merge) do
    case owned_slot_index(merge) do
      idx when is_integer(idx) ->
        live = Process.get(:elmc_plan_owned_live, MapSet.new())
        MapSet.member?(live, idx)

      _ ->
        false
    end
  end

  @spec phi_owned_src_live?(String.t()) :: boolean()

  defp phi_owned_src_live?(src) do
    case owned_slot_index(src) do
      idx when is_integer(idx) ->
        live = Process.get(:elmc_plan_owned_live, MapSet.new())
        MapSet.member?(live, idx)

      _ ->
        false
    end
  end

  @spec owned_slot_index(String.t() | term()) :: integer() | nil

  defp owned_slot_index("owned[" <> rest) do
    case Integer.parse(rest) do
      {idx, "]"} -> idx
      _ -> nil
    end
  end

  defp owned_slot_index(_), do: nil

  @spec truthy_shape_boxed_c_expr(term(), Types.slot_map(), keyword()) :: String.t()

  defp truthy_shape_boxed_c_expr({:const_int, value}, _slots, _opts) when is_integer(value) do
    EphemeralBox.bool(Integer.to_string(value))
  end

  defp truthy_shape_boxed_c_expr({:compare, kind, left, right}, slots, opts) do
    cmp = compare_branch_c_expr(kind, left, right, slots, opts)
    EphemeralBox.bool(cmp)
  end

  defp truthy_shape_boxed_c_expr({:reg, reg}, slots, opts) when is_integer(reg) do
    # Native-bool locals must become ephemeral Bool boxes — never retain a C `_Bool`.
    phi_boxed_arm_source(reg, slots, opts)
  end

  defp truthy_shape_boxed_c_expr(_shape, _slots, _opts), do: EphemeralBox.bool("0")

  @spec native_int_phi_arm_exprs(map(), Types.slot_map(), keyword()) :: {String.t(), String.t()}

  defp native_int_phi_arm_exprs(args, slots, opts) do
    {
      native_int_phi_shape_c_expr(Map.fetch!(args, :then_shape), slots, opts),
      native_int_phi_shape_c_expr(Map.fetch!(args, :else_shape), slots, opts)
    }
  end

  @spec native_int_phi_shape_c_expr(term(), Types.slot_map(), keyword()) :: String.t()

  defp native_int_phi_shape_c_expr({:const_int, value}, _slots, _opts), do: Integer.to_string(value)

  defp native_int_phi_shape_c_expr({:new_int, value}, _slots, _opts) when is_integer(value),
    do: Integer.to_string(value)

  defp native_int_phi_shape_c_expr({:new_int, expr}, _slots, _opts) when is_binary(expr), do: expr

  defp native_int_phi_shape_c_expr({:int_arith, args}, slots, opts),
    do: Elmc.Backend.C.Lower.NativeIntFold.int_arith_c_expr(args, slots, opts) || "0"

  defp native_int_phi_shape_c_expr({:load_param, index}, _slots, opts) when is_integer(index),
    do: load_param_int_c_expr(index, opts)

  defp native_int_phi_shape_c_expr({:reg, reg}, slots, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} when is_integer(index) ->
        load_param_int_c_expr(index, opts)

      _ ->
        int_operand_ref(reg, slots, opts)
    end
  end

  defp native_int_phi_shape_c_expr({:record_get_int, reg}, slots, opts) when is_integer(reg),
    do: int_operand_ref(reg, slots, opts)

  defp native_int_phi_shape_c_expr({:native_int_phi, reg}, slots, opts) when is_integer(reg),
    do: int_operand_ref(reg, slots, opts)

  defp native_int_phi_shape_c_expr(_shape, _slots, _opts), do: "0"

  # Native-int ABI params are already i32. Boxed Int params must be peeled —
  # using the ElmcValue* name in a ternary is a -Wint-conversion error.
  defp load_param_int_c_expr(index, opts) when is_integer(index) do
    case Enum.at(Keyword.get(opts, :param_kinds, []), index) do
      :native_int ->
        native_int_param_c_arg(index, opts)

      _ ->
        "elmc_as_int(#{FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))})"
    end
  end

  @spec phi_truthy_arm_exprs(map(), Types.reg(), Types.reg(), Types.slot_map(), keyword()) :: {String.t(), String.t()}

  defp phi_truthy_arm_exprs(args, then_reg, else_reg, slots, opts) do
    if Map.get(args, :truthy_native) == true do
      {truthy_shape_c_expr(Map.fetch!(args, :then_shape), slots, opts),
       truthy_shape_c_expr(Map.fetch!(args, :else_shape), slots, opts)}
    else
      {phi_truthy_arm_expr(then_reg, slots, opts), phi_truthy_arm_expr(else_reg, slots, opts)}
    end
  end

  @spec truthy_shape_c_expr(term(), Types.slot_map(), keyword()) :: String.t()

  defp truthy_shape_c_expr({:const_int, 0}, _slots, _opts), do: "false"
  defp truthy_shape_c_expr({:const_int, 1}, _slots, _opts), do: "true"

  defp truthy_shape_c_expr({:compare, kind, left, right}, slots, opts) do
    compare_branch_c_expr(kind, left, right, slots, opts)
  end

  defp truthy_shape_c_expr({:reg, reg}, slots, opts) when is_integer(reg) do
    branch_cond_expr_impl(reg, slots, opts)
  end

  @spec phi_truthy_arm_expr(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec plan_defining_instr(map() | term(), Types.reg() | term()) :: Types.t() | nil

  defp plan_defining_instr(%{blocks: blocks}, reg) when is_integer(reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.find(fn %{dest: dest} -> dest == reg end)
  end

  defp plan_defining_instr(_, _), do: nil

  @spec truthy_expr(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec ternary_cond_expr(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

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

  @spec emit_compare(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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

  @spec emit_bool_and(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_bool_and(%{dest: dest_reg, args: args}, slots, rc?, dest, opts) do
    left = truthy_expr(args.left, slots, opts)
    right = truthy_expr(args.right, slots, opts)
    expr = "(#{left} && #{right})"

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      emit_native_bool_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_bool", [expr])
    end
  end

  @spec emit_native_bool_test(map(), Types.slot_map(), boolean(), String.t(), keyword(), (String.t() -> String.t())) :: String.t()

  defp emit_native_bool_test(%{dest: dest_reg, args: args}, slots, rc?, dest, opts, subject_expr) do
    subject = bool_test_subject_ref(args, slots, opts)
    expr = subject_expr.(subject)

    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) do
      emit_native_bool_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_bool", [expr])
    end
  end

  @spec bool_test_subject_ref(map() | Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp bool_test_subject_ref(%{reg: reg}, slots, opts), do: bool_test_subject_ref(reg, slots, opts)
  defp bool_test_subject_ref(%{subject: reg}, slots, opts), do: bool_test_subject_ref(reg, slots, opts)

  defp bool_test_subject_ref(reg, slots, opts) when is_integer(reg) do
    if MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg) do
      Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), reg)
    else
      slot_ref(reg, slots, opts)
    end
  end

  @spec boxed_bool_test_expr(String.t(), boolean()) :: String.t()

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

  @spec emit_native_bool_store(Types.reg(), String.t(), String.t(), keyword()) :: String.t()

  defp emit_native_bool_store(dest_reg, _dest, expr, opts) do
    name = Map.fetch!(Keyword.get(opts, :native_bool_regs, %{}), dest_reg)

    if MapSet.member?(Keyword.get(opts, :native_bool_mutable_regs, MapSet.new()), dest_reg) do
      "#{name} = #{expr};"
    else
      "const bool #{name} = #{expr};"
    end
  end

  @spec compare_native_c_expr(atom(), String.t(), String.t()) :: String.t()

  defp compare_native_c_expr(:eq, left, right), do: "(#{left} == #{right})"
  defp compare_native_c_expr(:neq, left, right), do: "(#{left} != #{right})"
  defp compare_native_c_expr(:gt, left, right), do: "(#{left} > #{right})"
  defp compare_native_c_expr(:gte, left, right), do: "(#{left} >= #{right})"
  defp compare_native_c_expr(:lt, left, right), do: "(#{left} < #{right})"
  defp compare_native_c_expr(:lte, left, right), do: "(#{left} <= #{right})"
  defp compare_native_c_expr(_, left, right), do: "(#{left} == #{right})"

  @spec compare_branch_c_expr(atom(), Types.reg(), Types.reg(), Types.slot_map(), keyword(), atom()) :: String.t()

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

      # Structural Maybe/Result/List/… equality only. Bare `:pointer` (default when
      # mode is omitted — e.g. emit_test_maybe_just's native-bool vs 0) must keep
      # the int/pointer fallthrough; elmc_value_equal requires ElmcValue*.
      kind in [:eq, :neq] and compare_mode == :value ->
        left = slot_ref(left_reg, slots, opts)
        right = slot_ref(right_reg, slots, opts)
        eq_expr = "elmc_value_equal(#{left}, #{right})"
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

  @spec compare_float_boxed_operand(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec compare_int_boxed_operand(Types.reg(), boolean(), Types.slot_map(), keyword()) :: String.t()

  defp compare_int_boxed_operand(reg, true, slots, opts),
    do: int_operand_ref(reg, slots, opts)

  defp compare_int_boxed_operand(reg, false, slots, opts) do
    case peel_native_int_operand_ref(reg, slots, opts) do
      native when is_binary(native) -> native
      _ -> "elmc_as_int(#{slot_ref(reg, slots, opts)})"
    end
  end

  @spec emit_switch_ctor_tag(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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
            assign_boxed_src_to_dest(merge, src, rc?, opts)
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
              assign_boxed_src_to_dest(merge, src, rc?, opts)
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

  @spec emit_int_arith(map() | term(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :min_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    # Full parens: `?:` binds looser than `-`/`+`, and parenthesize_int_expr treats a
    # leading `(cond)` as already wrapped.
    emit_int_result_assign(dest_reg, dest, rc?, "((#{lhs_s} <= #{rhs_s}) ? #{lhs_s} : #{rhs_s})", opts)
  end

  defp emit_int_arith(%{dest: dest_reg, args: %{kind: :max_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest, opts) do
    lhs_s = int_operand_ref(lhs, slots, opts)
    rhs_s = int_operand_ref(rhs, slots, opts)
    emit_int_result_assign(dest_reg, dest, rc?, "((#{lhs_s} >= #{rhs_s}) ? #{lhs_s} : #{rhs_s})", opts)
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

  @spec emit_int_result_assign(Types.reg(), String.t(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_int_result_assign(dest_reg, dest, _rc?, expr, opts) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(Keyword.get(opts, :rc_required, true), dest, "elmc_new_int", [expr])
    end
  end

  @spec emit_native_store(Types.reg(), String.t(), String.t(), keyword()) :: String.t()

  defp emit_native_store(dest_reg, dest, expr, opts) do
    cond do
      # Const ints / c_exprs are often mapped into native_int_regs as the literal or
      # macro text for use-site inlining (`"2"`, `ELMC_COLOR_…`). Those are not C
      # variables — emitting `const elmc_int_t 2 = 2;` is invalid.
      not plan_native_int_lvalue?(dest) ->
        ""

      Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), dest_reg) ->
        ""

      MapSet.member?(Keyword.get(opts, :native_int_mutable_regs, MapSet.new()), dest_reg) ->
        "#{dest} = #{expr};"

      true ->
        "const elmc_int_t #{dest} = #{expr};"
    end
  end

  # Only `plan_native_int_N` (and mutable assigns into that name) are valid stores.
  defp plan_native_int_lvalue?(dest) when is_binary(dest),
    do: String.match?(dest, ~r/^plan_native_int_\d+$/)

  @spec emit_native_const_def(Types.reg(), String.t(), String.t(), keyword()) :: String.t()

  defp emit_native_const_def(dest_reg, dest, expr, opts),
    do: emit_native_store(dest_reg, dest, expr, opts)

  @spec emit_record_get_int(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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

  @spec emit_record_update(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()
  defp emit_record_update(instr, slots, rc?, dest, opts) do
    base_reg = instr.args.base
    base = slot_ref(base_reg, slots, opts)
    field = Map.get(instr.args, :field)
    index = record_get_index_ref(field, Map.get(instr.args, :field_index, "0"))
    value_reg = instr.args.value

    {fn_name_drop, value} =
      case native_int_slot_ref(value_reg, opts) do
        native when is_binary(native) ->
          {"elmc_record_update_index_int_cow_drop", native}

        nil ->
          {"elmc_record_update_index_cow_drop", slot_ref(value_reg, slots, opts)}
      end

    fn_name_cow = String.replace(fn_name_drop, "_cow_drop", "_cow")

    # Borrowed params / non-owned bases must not be passed to *_cow_drop:
    # the copy path releases `record` and would free the caller's value.
    # Use cow (no drop) so a uniquely owned borrow (rc==1) mutates in place
    # instead of retain-then-copy. Owned slots that only hold a borrow (Just
    # payload peel, field view) are the same — cow_drop would free the owner.
    borrow_base? =
      is_integer(base_reg) and
        (not is_integer(Map.get(slots, base_reg)) or
           RecordCompile.borrowed_owned_ref?(base))

    fn_name = if borrow_base?, do: fn_name_cow, else: fn_name_drop

    if borrow_base? and rc? do
      emit_record_update_borrow_base(fn_name_cow, dest, base, index, value)
    else
      assign =
        if rc? do
          rc_assign(true, dest, fn_name, [base, index, value])
        else
          fn_out_tail? = instr.dest in [:fn_out, :branch_out]

          if fn_out_tail? do
            wrap_non_rc_rc_allocator_return(fn_name, [base, index, value], instr, slots, opts)
          else
            rc_assign(false, dest, fn_name, [base, index, value])
          end
        end

      alias_guard =
        if instr.dest in [:fn_out, :branch_out] and not rc? do
          ""
        else
          cow_drop_alias_null(
            instr.dest,
            base_reg,
            Map.get(instr.args, :retain_copy, false),
            slots,
            opts
          )
        end

      [assign, alias_guard]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end

  # Borrowed base: cow without an extra retain so rc==1 mutates in place.
  # Never cow_drop a borrow — the copy path would release the caller's record.
  @spec emit_record_update_borrow_base(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          String.t()

  defp emit_record_update_borrow_base(fn_name, dest, base, index, value)
       when is_binary(fn_name) and is_binary(dest) and is_binary(base) and is_binary(index) and
              is_binary(value) do
    dest_ptr = dest_arg(dest, dest)

    """
    {
      Rc = #{fn_name}(#{dest_ptr}, #{base}, #{index}, #{value});
      CHECK_RC(Rc);
      if (#{dest} == #{base}) {
        #{dest} = elmc_retain(#{dest});
      }
    }
    """
    |> String.trim()
  end

  # Prefer an already-lowered native int name; do not invent `plan_native_int_N`
  # for boxed regs that merely happen to hold Int values.
  @spec native_int_slot_ref(Types.reg() | term(), keyword()) :: String.t() | nil
  defp native_int_slot_ref(reg, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) do
      name when is_binary(name) ->
        native_int_regs_c_operand_ref(reg, name, opts)

      _ ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
          "plan_native_int_#{reg}"
        else
          nil
        end
    end
  end

  defp native_int_slot_ref(_, _), do: nil

  @spec emit_boxed_binop(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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

  @spec emit_boxed_binop_dynamic(atom(), Types.reg(), Types.reg(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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

    # Non-fdiv boxed binops are Int in practice when they reach this fallback
    # (Float arithmetic is lowered via float-specific ops / as_float paths).
    # Emitting a dead `elmc_new_float` branch broke Int helpers such as
    # integerLetArithmetic (`refute body =~ "elmc_new_float"`).
    #
    # Mixed native-int + boxed operands (e.g. `cx + round (…)`) must use
    # `int_operand_ref/3` — wrapping a native `elmc_int_t` param with
    # `elmc_as_int(cx)` is a type error and heap corruption at runtime.
    if op == :fdiv do
      left = slot_ref(lhs, slots, opts)
      right = slot_ref(rhs, slots, opts)
      float_expr = "elmc_as_float(#{left}) #{op_sym} elmc_as_float(#{right})"
      rc_assign(rc?, dest, "elmc_new_float", [float_expr])
    else
      left = int_operand_ref(lhs, slots, opts)
      right = int_operand_ref(rhs, slots, opts)
      int_expr = "#{left} #{op_sym} #{right}"
      rc_assign(rc?, dest, "elmc_new_int", [int_expr])
    end
  end

  @spec native_int_binop_operands?(Types.reg() | term(), Types.reg() | term(), keyword() | term()) :: boolean()

  defp native_int_binop_operands?(lhs, rhs, opts) when is_integer(lhs) and is_integer(rhs) do
    native_int_operand_reg?(lhs, opts) and native_int_operand_reg?(rhs, opts)
  end

  defp native_int_binop_operands?(_, _, _), do: false

  @spec native_int_operand_reg?(Types.reg(), keyword()) :: boolean()

  defp native_int_operand_reg?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), reg)
  end

  @spec float_literal_c(integer() | float()) :: String.t()

  defp float_literal_c(value) when is_integer(value), do: "#{value}.0"
  defp float_literal_c(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])

  @spec consumed_owned_transfer?(map() | term(), Types.slot_map() | term()) :: boolean()

  defp consumed_owned_transfer?(%{consumes: consumes}, src) when is_list(consumes),
    do: src in consumes

  defp consumed_owned_transfer?(_, _), do: false

  @spec assignable_owned_slot_ref?(String.t()) :: boolean()

  defp assignable_owned_slot_ref?(src) when is_binary(src),
    do: String.match?(src, ~r/^owned\[\d+\]$/)

  @spec native_int_slot_ref(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec skipped_native_int_operand_ref(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec native_int_def_c_expr(Types.reg(), Types.slot_map(), keyword()) :: String.t() | nil

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

  @spec record_int_operand_ref(Types.reg() | Types.result_slot() | term(), Types.slot_map(), keyword()) :: String.t()

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
  @spec runtime_builtin_sym(atom(), [term()], Types.slot_map(), keyword()) :: String.t() | nil

  defp runtime_builtin_sym(:list_take, _args, _slots, _opts), do: "elmc_list_take_int"

  defp runtime_builtin_sym(:list_drop, _args, _slots, _opts), do: "elmc_list_drop_int"

  defp runtime_builtin_sym(:list_range, _args, _slots, _opts), do: "elmc_list_range"

  defp runtime_builtin_sym(:list_nth_maybe, _args, _slots, _opts), do: "elmc_list_nth_maybe_int"

  defp runtime_builtin_sym(id, _args, _slots, _opts), do: RuntimeBuiltins.c_symbol(id)

  @spec emit_call_runtime(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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
    {values_prep, values_array} = record_values_array(args, slots, opts)
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
    #{Enum.join(values_prep, "\n")}
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
    # Borrow views (maybe_just_payload, union_payload, …) never allocate; retain only
    # bumps rc. NULL means "no payload", not OOM — do not emit assign_owned null checks.
    peel_sym = RuntimeBuiltins.c_symbol(peel_id) || "elmc_unknown"

    peel_args_c =
      peel_args
      |> Enum.map(&slot_ref(&1, slots, opts))

    peel_expr = "#{peel_sym}(#{Enum.join(peel_args_c, ", ")})"
    subject_reg = List.first(peel_args)
    subject_owned? = is_integer(subject_reg) and is_integer(Map.get(slots, subject_reg))
    publish? = dest in ["*out", "out"]

    # Peeling a borrowed Maybe (param / alias) must not retain: the extra rc
    # forces record COW to copy (CurrentDateTime is 104 bytes every tick).
    # Owned Maybes (List.head, etc.) still retain so the payload outlives release.
    # Publishing a peel to *out also retains so the caller owns the result.
    if subject_owned? or publish? do
      assign_value_return(rc?, dest, "elmc_retain(#{peel_expr})")
    else
      assign = assign_value_return(rc?, dest, peel_expr)

      if owned_slot_dest?(dest) do
        RecordCompile.mark_borrowed_owned_ref(dest)
      end

      assign
    end
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
          emit_owned_slot_transfer(dest_reg, src, slots, dest, src_s, rc?, opts)

        EphemeralBox.ephemeral?(src_s) ->
          {src, prep, cleanup} = materialize_ephemeral_src(src_s, opts, true)
          body = assign_value_return(rc?, dest, src)

          if prep == [] and cleanup == [] do
            body
          else
            emit_with_ephemeral_cleanup(prep, body, cleanup)
          end

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
      emit_native_store(dest_reg, dest, Integer.to_string(value), opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", [Integer.to_string(value)])
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :new_bool, literal: value}}, _slots, rc?, dest, _opts)
       when value in [0, 1] do
    rc_assign(rc?, dest, "elmc_new_bool", [bool_c_literal(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_order, literal: value}}, _slots, rc?, dest, _opts)
       when is_integer(value) do
    rc_assign(rc?, dest, "elmc_new_order", [Integer.to_string(value)])
  end

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :string_length_boxed, args: [arg]}},
         slots,
         rc?,
         dest,
         opts
       )
       when is_integer(arg) do
    src = boxed_value_ref(arg, slots, opts)
    expr = "elmc_string_length(#{src})"

    if is_integer(dest_reg) and
         MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", [expr])
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :new_float, literal: value}}, _slots, rc?, dest, _opts)
       when is_number(value) do
    rc_assign(rc?, dest, "elmc_new_float", [float_literal_c(value)])
  end

  defp emit_call_runtime(%{args: %{builtin: :new_char, literal: value}}, _slots, rc?, dest, _opts)
       when is_integer(value) do
    rc_assign(rc?, dest, "elmc_new_char", ["#{value}"])
  end

  defp emit_call_runtime(
         %{dest: dest_reg, args: %{builtin: :new_int, c_expr: expr}},
         _slots,
         rc?,
         dest,
         opts
       )
       when is_binary(expr) and is_integer(dest_reg) do
    if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) do
      emit_native_store(dest_reg, dest, expr, opts)
    else
      rc_assign(rc?, dest, "elmc_new_int", [expr])
    end
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

  defp emit_call_runtime(
         %{args: %{builtin: :tuple2, args: args}, dest: dest_reg},
         slots,
         rc?,
         dest,
         opts
       ) do
    cond do
      # Dual-out `(Int, Int)` writes *out0/*out1 on each return arm (including
      # switch/case tables). A single emit_return pair would collapse every arm
      # to the first tuple's constants.
      native_int_pair_ret_dest?(dest, dest_reg, opts) ->
        emit_native_int_pair_outs(args, slots, opts)

      # Dual-out `(List Int, Int)` writes *out_list/*out_int at each return arm.
      Keyword.get(opts, :native_scalar_out) == :native_list_int_pair and
          list_int_pair_ret_dest?(dest_reg, opts) ->
        emit_list_int_pair_outs(Enum.at(args, 0), Enum.at(args, 1), slots, opts)

      true ->
        call_opts = if rc?, do: [], else: [consume_args: true]
        {c_args, prep_lines, cleanup_lines} = build_runtime_call_args(:tuple2, args, slots, opts, call_opts)

        call_body =
          if rc? do
            rc_assign(true, dest, "elmc_tuple2", c_args)
          else
            rc_assign(false, dest, "elmc_tuple2", c_args)
          end

        emit_with_ephemeral_cleanup(prep_lines, call_body, cleanup_lines)
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :tuple2_take, args: args}}, slots, rc?, dest, opts) do
    c_args = Enum.map(args, &slot_ref(&1, slots, opts))

    if rc? do
      rc_assign(true, dest, "elmc_tuple2_take", c_args)
    else
      rc_assign(false, dest, "elmc_tuple2_take", c_args)
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
         %{dest: dest_reg, args: %{builtin: :list_nth_int_at, args: [list], index: index}} = instr,
         slots,
         rc?,
         dest,
         opts
       )
       when is_integer(list) and is_integer(index) do
    list_ref = slot_ref(list, slots, opts)
    default = Map.get(instr.args, :default, 0)
    expr = "elmc_list_nth_int_default(#{list_ref}, #{index}, #{default})"

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

  defp emit_call_runtime(
         %{args: %{builtin: :tuple2_ints, args: args}, dest: dest_reg},
         slots,
         rc?,
         dest,
         opts
       ) do
    # Dual-out `(Int, Int)` writes *out0/*out1 on each return arm.
    if native_int_pair_ret_dest?(dest, dest_reg, opts) do
      emit_native_int_pair_outs(args, slots, opts)
    else
      left = int_operand_ref(Enum.at(args, 0), slots, opts)
      right = int_operand_ref(Enum.at(args, 1), slots, opts)

      if rc? do
        rc_assign(true, dest, "elmc_tuple2_ints", [left, right])
      else
        rc_assign(false, dest, "elmc_tuple2_ints", [left, right])
      end
    end
  end

  defp emit_call_runtime(
         %{args: %{builtin: :maybe_just_own, args: [arg_reg]}} = _instr,
         slots,
         rc?,
         dest,
         opts
       )
       when is_integer(arg_reg) do
    {arg_ref, prep, cleanup} = materialize_owned_assign_src(arg_reg, slots, opts)

    sym =
      if RecordCompile.borrowed_owned_ref?(arg_ref) do
        "elmc_maybe_just"
      else
        "elmc_maybe_just_own"
      end

    body = elm_core_runtime_comment(:maybe_just_own) <> rc_assign(rc?, dest, sym, [arg_ref])
    emit_with_ephemeral_cleanup(prep, body, cleanup)
  end

  defp emit_call_runtime(%{args: %{builtin: id, args: args}} = instr, slots, rc?, dest, opts) do
    sym = runtime_builtin_sym(id, args, slots, opts) || "elmc_unknown"
    core_comment = elm_core_runtime_comment(id)

    cond do
      RuntimeBuiltins.direct_value_return?(id) ->
        {c_args, prep_lines, cleanup_lines} =
          build_runtime_call_args(id, args, slots, opts, consume_args: not rc?)

        call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"

        assign =
          boxed_value_return_into_dest(instr.dest, dest, call_expr, rc?, opts,
            style: :value_return
          )

        emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)

      RuntimeBuiltins.c_value_return?(id) and not rc? ->
        {c_args, prep_lines, cleanup_lines} =
          build_runtime_call_args(id, args, slots, opts, consume_args: true)

        assign = rc_assign(false, dest, sym, c_args)

        emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)

      true ->
        {c_args, prep_lines, cleanup_lines} = build_runtime_call_args(id, args, slots, opts)
        call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"

        cond do
          RuntimeBuiltins.c_value_return?(id) ->
            assign =
              boxed_value_return_into_dest(instr.dest, dest, call_expr, rc?, opts, style: :owned)

            emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)

          RuntimeBuiltins.value_return?(id) ->
            assign =
              cond do
                not rc? and dest == "*out" ->
                  assign_value_return_tail(false, dest, call_expr, instr, slots, opts)

                true ->
                  boxed_value_return_into_dest(instr.dest, dest, call_expr, rc?, opts,
                    style: :owned
                  )
              end

            emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)

          true ->
            {c_args, prep_lines, cleanup_lines} = build_runtime_call_args(id, args, slots, opts)

            assign =
              cond do
                # RC allocators must keep the out-pointer ABI even inside
                # `ElmcValue *`-returning (non-RC) wrappers — never `return elmc_foo(args)`.
                RcRuntimeEmit.rc_allocator?(sym) and not rc? and dest == "*out" ->
                  wrap_non_rc_rc_allocator_return(sym, c_args, instr, slots, opts)

                RcRuntimeEmit.rc_allocator?(sym) ->
                  rc_assign(rc?, dest, sym, c_args)

                not rc? and dest == "*out" ->
                  call_expr = "#{sym}(#{Enum.join(c_args, ", ")})"
                  assign_value_return_tail(false, dest, call_expr, instr, slots, opts)

                true ->
                  rc_assign(rc?, dest, sym, c_args)
              end

            emit_with_ephemeral_cleanup(prep_lines, core_comment <> assign, cleanup_lines)
        end
    end
  end

  # Boxed `ElmcValue *` runtime results must not assign into `plan_native_int_N`.
  defp boxed_value_return_into_dest(dest_reg, dest, call_expr, rc?, opts, style_opts)

  defp boxed_value_return_into_dest(dest_reg, dest, call_expr, rc?, opts, style_opts)
       when is_integer(dest_reg) do
    style = Keyword.get(style_opts, :style, :owned)

    cond do
      MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), dest_reg) ->
        tmp = "plan_box_int_#{dest_reg}"

        """
        ElmcValue *#{tmp} = #{call_expr};
        #{emit_native_store(dest_reg, "plan_native_int_#{dest_reg}", "elmc_as_int(#{tmp})", opts)}
        elmc_release(#{tmp});
        """
        |> String.trim()

      MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg) ->
        tmp = "plan_box_bool_#{dest_reg}"

        """
        ElmcValue *#{tmp} = #{call_expr};
        #{emit_native_bool_store(dest_reg, "plan_native_bool_#{dest_reg}", "elmc_as_bool(#{tmp})", opts)}
        elmc_release(#{tmp});
        """
        |> String.trim()

      style == :value_return ->
        assign_value_return(rc?, dest, call_expr)

      true ->
        assign_owned(rc?, dest, call_expr)
    end
  end

  defp boxed_value_return_into_dest(_dest_reg, dest, call_expr, rc?, _opts, style_opts) do
    if Keyword.get(style_opts, :style, :owned) == :value_return do
      assign_value_return(rc?, dest, call_expr)
    else
      assign_owned(rc?, dest, call_expr)
    end
  end

  # After record_new_values_take moves field pointers into *out, any bare `owned[i]` named as an
  # array element must be nulled. Do not null operands of `elmc_retain(owned[i])` — those are
  # borrows; the take owns the retained temporary, not the named slot.
  @spec null_owned_slots_named_in_values_array(String.t()) :: String.t()

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

  @spec elm_core_runtime_comment(atom()) :: String.t()

  defp elm_core_runtime_comment(id) when is_atom(id) do
    case Map.get(@elm_core_runtime_targets, id) do
      target when is_binary(target) -> String.trim_leading(ElmCore.comment_line(target))
      _ -> ""
    end
  end

  @spec build_runtime_call_args(atom(), [Types.reg()], Types.slot_map(), keyword(), keyword()) :: {[String.t()], [String.t()], [String.t()]}

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

      EphemeralBox.materialize(ref, prep, cleanup, opts, consume_args?)
    end)
    |> then(fn {c_args, {prep, cleanup}} -> {c_args, prep, cleanup} end)
  end

  defp materialize_ephemeral_src(src, opts, transfer_ownership? \\ false) do
    {var, {prep, cleanup}} = EphemeralBox.materialize(src, [], [], opts, transfer_ownership?)
    {var, prep, cleanup}
  end

  @spec materialize_plan_call_args([String.t()], keyword()) :: {[String.t()], [String.t()], [String.t()]}
  defp materialize_plan_call_args(c_args, opts) do
    EphemeralBox.materialize_call_args(c_args, opts, false)
  end


  defp emit_with_ephemeral_cleanup(prep_lines, call_line, cleanup_lines) do
    (prep_lines ++ List.wrap(call_line) ++ cleanup_lines)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec emit_release(map() | term(), Types.slot_map() | term()) :: String.t()

  # Plan `:release` is for Verify / EpilogueRelease bookkeeping. Owned slots are
  # cleaned by frame `elmc_release_array_lifo` — do not emit mid-body releases.
  defp emit_release(%{args: %{reg: reg}}, slots) when is_integer(reg) do
    _ = Map.get(slots, reg)
    ""
  end

  defp emit_release(_, _), do: ""

  @spec emit_call_closure(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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

  @spec emit_call_fn(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

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

  @spec missing_decl_int_builtin?(String.t(), String.t(), [term()], Types.decl_map()) :: boolean()

  defp missing_decl_int_builtin?(mod, name, args, decl_map) do
    is_nil(Map.get(decl_map, {mod, name})) and mod in ["Main", "Basics"] and
      ((name in ["max", "min"] and length(args) == 2) or (name == "not" and length(args) == 1))
  end

  @spec missing_decl_kernel_log_cmd?(String.t(), String.t(), [term()], Types.decl_map()) :: boolean()

  defp missing_decl_kernel_log_cmd?(mod, name, args, decl_map) do
    is_nil(Map.get(decl_map, {mod, name})) and mod == "Elm.Kernel.PebbleWatch" and
      name in ["logInfoCode", "logWarnCode", "logErrorCode"] and length(args) == 1
  end

  @spec emit_missing_decl_kernel_log_cmd(Types.reg() | term(), String.t(), [Types.reg()], Types.slot_map(), boolean(), String.t(), keyword(), Types.t() | map()) :: String.t()

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
      RcRuntimeEmit.non_rc_allocator_stmt(dest, "elmc_cmd1", "#{kind}, #{code_ref}",
        return_on_fail?: dest == "*out"
      )
    end
  end

  @spec emit_missing_decl_int_builtin(Types.reg() | term(), String.t(), [Types.reg()], Types.slot_map(), boolean(), String.t(), keyword(), Types.t() | map()) :: String.t()

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
            "((#{lhs} >= #{rhs}) ? #{lhs} : #{rhs})"
          else
            "((#{lhs} <= #{rhs}) ? #{lhs} : #{rhs})"
          end

        emit_int_result_assign(dest_reg, out, rc?, expr, opts)

      "not" ->
        [arg] = args
        ref = "elmc_as_bool(#{call_site_slot_ref(arg, slots, opts, borrows)})"
        rc_assign(rc?, out, "elmc_new_bool", ["!#{ref}"])
    end
  end

  @spec emit_basics_clamp_call(Types.reg() | term(), [Types.reg()], Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_basics_clamp_call(_dest_reg, args, slots, _rc?, dest, opts) do
    [low, high, value] = Enum.map(args, &slot_ref(&1, slots, opts))
    "#{dest} = elmc_basics_clamp(#{Enum.join([low, high, value], ", ")});"
  end

  @spec resolve_plan_call_target(String.t(), String.t(), Types.decl() | nil, Types.decl_map(), list()) :: {String.t(), String.t(), Types.decl() | nil, String.t()}

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

  @spec emit_call_fn_impl(Types.reg() | Types.result_slot() | term(), map(), Types.slot_map(), boolean(), String.t(), keyword(), Types.t() | map()) :: String.t()

  defp emit_call_fn_impl(dest_reg, %{module: mod, name: name, args: args}, slots, rc?, dest, opts, instr) do
    opts =
      case Map.get(instr, :args) do
        %{native_pair_out: _} ->
          Keyword.put(opts, :native_pair_unboxed, true)

        %{native_list_int_pair_out: _} ->
          Keyword.put(opts, :native_list_int_pair_unboxed, true)

        _ ->
          opts
      end

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

    # Prefer boxed out when the callee's public ABI boxes the Int/Bool result
    # (native-arg helper with `ElmcValue **out`), even if NativeReturn cached a
    # scalar kind before that path registered.
    boxed_rc_out? =
      is_map(decl) and NativeFunctionCall.native_boxed_rc_abi?(decl, mod, decl_map)

    native_ret =
      cond do
        boxed_rc_out? -> nil
        supersedes_native? -> PlanNativeProjection.native_call_return_kind(decl, mod, decl_map)
        true -> NativeReturn.cached_kind({mod, name})
      end

    list_int_pair_unpack_sroa? =
      match?(%{native_list_int_pair_out: _}, Map.get(instr, :args, %{})) and
        native_ret != :native_list_int_pair

    # Tuple2IntsUnbox may annotate native_pair_out from the callee's declared
    # `(Int, Int)` type before the callee is actually dual-out ABI. Peel the
    # boxed pair into plan_native_pair_* temps instead of calling a missing
    # `elmc_int_t *out0, *out1` signature.
    native_pair_unpack_sroa? =
      match?(%{native_pair_out: _}, Map.get(instr, :args, %{})) and
        native_ret != :native_int_pair

    # Prefer fused `_native` even for direct-entry callees: public wrappers may
    # still take `ElmcValue *` Ints (lambda-escape boxing) while `_native` has
    # `elmc_int_t` params (e.g. list_indexed_replace / setCell).
    fusion_arg_kinds = Fusion.rc_native_fusion_arg_kinds({mod, name})

    c_name =
      cond do
        plan_call_uses_native_fusion?(fusion_arg_kinds, rc?, native_ret, mod, name) ->
          "#{c_name}_native"

        supersedes_native? and not NativeReturn.value_return?({mod, name}) and
            is_map(decl) and NativeFunctionCall.return_kind(decl, mod, decl_map) != :boxed ->
          "#{c_name}_native"

        true ->
          c_name
      end

    {prefix, call_arg_s, eph_prep, eph_cleanup} =
      cond do
        fusion_arg_kinds ->
          c_args = rc_native_fusion_call_args(args, fusion_arg_kinds, slots, opts, borrows)
          finalize_materialized_call_args("", c_args, opts)

        native_ret in [:native_int, :native_bool, :native_int_pair, :native_list_int_pair] and decl ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          c_args = call_arg_refs(args, slots, opts, kinds, borrows)
          finalize_materialized_call_args("", c_args, opts)

        native_ret == :native_int ->
          c_args = Enum.map(args, &int_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", "), [], []}

        native_ret == :native_int_pair ->
          c_args = Enum.map(args, &int_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", "), [], []}

        native_ret == :native_list_int_pair and is_map(decl) ->
          kinds = NativeFunctionCall.call_site_arg_kinds(decl, mod, decl_map)

          c_args =
            args
            |> Enum.zip(kinds)
            |> Enum.map(fn {arg_reg, kind} ->
              plan_call_site_arg_ref(arg_reg, kind, false, slots, opts, borrows)
            end)

          finalize_materialized_call_args("", c_args, opts)

        native_ret == :native_list_int_pair ->
          c_args = Enum.map(args, &call_site_slot_ref(&1, slots, opts, borrows))
          finalize_materialized_call_args("", c_args, opts)

        native_ret == :native_bool ->
          c_args = Enum.map(args, &bool_operand_ref(&1, slots, opts))
          {"", Enum.join(c_args, ", "), [], []}

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

          finalize_materialized_call_args("", c_args, opts)

        decl && FunctionEmit.mixed_direct_abi?(decl, mod, decl_map) ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          c_args = call_arg_refs(args, slots, opts, kinds, borrows)
          finalize_materialized_call_args("", c_args, opts)

        decl && FunctionCallAbi.argv_abi?(decl, mod, decl_map) ->
          c_args = Enum.map(args, &call_site_slot_ref(&1, slots, opts, borrows))
          {c_args, prep, cleanup} = materialize_plan_call_args(c_args, opts)
          {setup, args_var, argc} = FunctionCallAbi.emit_argv_setup("plan", c_args)
          {setup <> "\n", "#{args_var}, #{argc}", prep, cleanup}

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

          finalize_materialized_call_args("", c_args, opts)
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

    call_body =
      cond do
        list_int_pair_unpack_sroa? ->
          emit_boxed_list_int_pair_sroa_call(rc?, dest, dest_reg, c_name, call_arg_s)

        native_pair_unpack_sroa? ->
          emit_boxed_native_int_pair_sroa_call(
            rc?,
            dest,
            dest_ref,
            dest_reg,
            c_name,
            call_arg_s,
            {mod, name},
            opts,
            decl,
            plan_rc_boxed_callee?(decl, mod, decl_map, fusion_arg_kinds, nil),
            fusion_arg_kinds
          )

        match?({:ok, _}, folded) ->
          elem(folded, 1)

        true ->
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

    prefix <>
      if eph_prep != [] or eph_cleanup != [] do
        emit_with_ephemeral_cleanup(eph_prep, call_body, eph_cleanup)
      else
        call_body
      end
  end

  @spec finalize_materialized_call_args(String.t(), [String.t()], keyword()) ::
          {String.t(), String.t(), [String.t()], [String.t()]}
  defp finalize_materialized_call_args(prefix, c_args, opts) do
    {c_args, prep, cleanup} = materialize_plan_call_args(c_args, opts)
    {prefix, Enum.join(c_args, ", "), prep, cleanup}
  end

  @spec maybe_emit_folded_union_int_call([atom()] | nil, String.t(), String.t(), [term()] | term(), boolean(), String.t(), keyword()) :: {:ok, String.t()} | :error

  defp maybe_emit_folded_union_int_call(fusion_arg_kinds, mod, name, [arg_reg], true, dest, opts)
       when is_list(fusion_arg_kinds) do
    const_int_regs = Keyword.get(opts, :const_int_regs, %{})

    case Map.get(const_int_regs, arg_reg) |> const_int_value() do
      union_tag when is_integer(union_tag) ->
        case Fusion.union_int_lut_lookup({mod, name}, union_tag) do
          {:ok, wire} ->
            dest_ref = if dest == "*out", do: "out", else: dest
            out_arg = dest_arg(dest_ref, dest)
            {:ok, "Rc = elmc_new_int(#{out_arg}, #{wire});\nCHECK_RC(Rc);"}

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

  @spec plan_rc_boxed_callee?(Types.decl(), String.t(), Types.decl_map(), [atom()] | nil, atom() | nil) :: boolean()

  defp plan_rc_boxed_callee?(decl, module, decl_map, fusion_arg_kinds, native_ret) do
    !!(
      is_map(decl) and
        is_nil(fusion_arg_kinds) and
        native_ret not in [:native_int, :native_bool, :native_int_pair] and
        (plan_boxed_direct_call_abi?(decl, module, decl_map) or
           RcRequired.rc_required?(module, Map.get(decl, :name)))
    )
  end

  @spec rc_native_fusion_call_args(
          [Types.reg()],
          [atom()],
          Types.slot_map(),
          keyword(),
          [Types.reg()]
        ) :: [String.t()]

  defp rc_native_fusion_call_args(args, kinds, slots, opts, borrows)
       when is_list(args) and is_list(kinds) do
    args
    |> Enum.zip(kinds)
    |> Enum.map(fn {reg, kind} ->
      case kind do
        :boxed_int_tag ->
          case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
            entry when not is_nil(entry) ->
              const_int_c_ref(entry, opts)

            _ ->
              native_int_regs = Keyword.get(opts, :native_int_regs, %{})
              native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

              # Multi-def enum tags (commoned switch arms) live in plan_native_int_N.
              if Map.has_key?(native_int_regs, reg) or MapSet.member?(native_only, reg) do
                int_call_site_ref(reg, slots, opts, borrows)
              else
                RowMajorLayout.union_tag_expr(call_site_slot_ref(reg, slots, opts, borrows))
              end
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

        # Mixed Int/boxed fusion helpers (e.g. TailRecursiveLoop `rangeHelp`) keep
        # some Int params as `ElmcValue *` — box native scalars at the call site.
        _ ->
          plan_call_site_arg_ref(reg, :boxed, false, slots, opts, borrows)
      end
    end)
  end

  @spec call_site_slot_ref(Types.reg(), Types.slot_map(), keyword(), [Types.reg()]) :: String.t()

  defp call_site_slot_ref(reg, slots, opts, borrows) do
    case borrow_call_param_c_ref(reg, borrows, opts) do
      c_arg when is_binary(c_arg) -> c_arg
      _ -> slot_ref(reg, slots, opts)
    end
  end

  @spec call_arg_refs([Types.reg()], Types.slot_map(), keyword(), [atom()], [Types.reg()]) :: [String.t()]

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

  @spec plan_call_site_arg_ref(Types.reg(), atom(), boolean(), Types.slot_map(), keyword(), [Types.reg()]) :: String.t()

  defp plan_call_site_arg_ref(reg, kind, box_native_int?, slots, opts, borrows) do
    case borrow_call_param_c_ref(reg, borrows, opts) do
      c_arg when is_binary(c_arg) ->
        if kind == :boxed do
          boxed_value_ref(reg, slots, opts)
        else
          case {kind, box_native_int?} do
            {:native_int, true} ->
              EphemeralBox.int(int_operand_ref(reg, slots, opts))

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

  @spec borrow_call_param_c_ref(Types.reg() | term(), [Types.reg()] | term(), keyword() | term()) :: String.t() | nil

  defp borrow_call_param_c_ref(reg, borrows, opts)
       when is_integer(reg) and is_list(borrows) do
    if Keyword.get(opts, :closure_mode) do
      nil
    else
      borrow_call_param_c_ref_impl(reg, borrows, opts)
    end
  end

  defp borrow_call_param_c_ref(_, _, _), do: nil

  @spec borrow_call_param_c_ref_impl(Types.reg(), [Types.reg()], keyword()) :: String.t() | nil

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
  @spec int_call_site_ref(Types.reg(), Types.slot_map(), keyword(), [Types.reg()]) :: String.t()

  defp int_call_site_ref(reg, slots, opts, _borrows),
    do: int_operand_ref(reg, slots, opts)

  @spec bool_call_site_ref(Types.reg(), Types.slot_map(), keyword(), [Types.reg()]) :: String.t()

  defp bool_call_site_ref(reg, slots, opts, _borrows),
    do: bool_operand_ref(reg, slots, opts)

  @spec plan_rc_call_arg_ref(Types.reg(), atom(), boolean(), Types.slot_map(), keyword()) :: String.t()

  defp plan_rc_call_arg_ref(reg, :native_int, true, slots, opts),
    do: EphemeralBox.int(int_operand_ref(reg, slots, opts))

  defp plan_rc_call_arg_ref(reg, :native_int, false, slots, opts),
    do: int_operand_ref(reg, slots, opts)

  defp plan_rc_call_arg_ref(reg, :native_bool, _boxed_rc?, slots, opts),
    do: bool_operand_ref(reg, slots, opts)

  defp plan_rc_call_arg_ref(reg, :boxed, _boxed_rc?, slots, opts),
    do: boxed_value_ref(reg, slots, opts)

  defp plan_rc_call_arg_ref(reg, _kind, _boxed_rc?, slots, opts),
    do: slot_ref(reg, slots, opts)

  @spec plan_rc_box_native_int_args?(Types.decl(), String.t(), Types.decl_map(), [atom()] | nil, atom() | nil) :: boolean()

  defp plan_rc_box_native_int_args?(decl, mod, decl_map, fusion_arg_kinds, native_ret) do
    plan_rc_boxed_callee?(decl, mod, decl_map, fusion_arg_kinds, native_ret) and
      not FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map)
  end

  @spec fusion_native_rc_callee?(String.t(), [atom()] | nil) :: boolean()

  defp fusion_native_rc_callee?(c_name, fusion_arg_kinds),
    do: not is_nil(fusion_arg_kinds) and String.ends_with?(c_name, "_native")

  @spec kernel_stub_callee?(String.t() | term(), String.t() | term(), Types.decl() | nil | term()) :: boolean()

  defp kernel_stub_callee?("Elm.Kernel", _name, nil), do: true

  defp kernel_stub_callee?(_mod, c_name, nil) when is_binary(c_name),
    do: String.starts_with?(c_name, "elmc_fn_Elm_Kernel_")

  defp kernel_stub_callee?(_, _, _), do: false

  @spec plan_call_uses_native_fusion?([atom()] | nil, boolean(), atom() | nil, String.t(), String.t()) :: boolean()

  defp plan_call_uses_native_fusion?(fusion_arg_kinds, _rc?, _native_ret, _mod, _name) do
    # Registered fusion kinds always describe the `_native` companion. The public
    # peel wrapper may still take `ElmcValue *` Ints — calling it with bare
    # native args is an ABI bug (setAt / list_indexed_replace). Do not gate on
    # caller `rc?` / `native_ret`: boxed-return RC fusions clear `native_ret`.
    not is_nil(fusion_arg_kinds)
  end

  @spec emit_fn_call(boolean(), String.t(), String.t(), Types.reg() | term(), String.t(), String.t(), {String.t(), String.t()}, atom() | nil, keyword(), Types.decl() | nil, boolean(), [atom()] | nil) :: String.t()

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

      native_ret in [:native_int, :native_bool, :native_int_pair, :native_list_int_pair] ->
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

      native_ret in [:native_int, :native_bool, :native_int_pair, :native_list_int_pair] ->
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

  @spec legacy_argv_value_callee?(Types.decl(), String.t(), atom() | nil) :: boolean()

  defp legacy_argv_value_callee?(decl, module, native_ret) do
    decl_map = Process.get(:elmc_program_decls, %{})

    is_map(decl) and
      native_ret not in [:native_int, :native_bool, :native_int_pair, :native_list_int_pair] and
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

  @spec emit_boxed_list_int_pair_sroa_call(boolean(), String.t(), Types.reg() | term(), String.t(), String.t()) ::
          String.t()
  defp emit_boxed_native_int_pair_sroa_call(
         rc?,
         dest,
         dest_ref,
         dest_reg,
         c_name,
         call_arg_s,
         callee,
         opts,
         decl,
         direct_plan_boxed?,
         fusion_arg_kinds
       ) do
    a = "plan_native_pair_#{dest_reg}_0"
    b = "plan_native_pair_#{dest_reg}_1"
    pair_ref = if dest == "*out", do: "*out", else: dest

    call =
      emit_fn_call(
        rc?,
        dest,
        dest_ref,
        dest_reg,
        c_name,
        call_arg_s,
        callee,
        nil,
        opts,
        decl,
        direct_plan_boxed?,
        fusion_arg_kinds
      )

    """
    #{call}
    elmc_int_t #{a} = elmc_as_int(elmc_tuple_first_borrow(#{pair_ref}));
    elmc_int_t #{b} = elmc_as_int(elmc_tuple_second_borrow(#{pair_ref}));
    """
    |> String.trim()
  end

  defp emit_boxed_list_int_pair_sroa_call(rc?, dest, dest_reg, c_name, call_arg_s) do
    int_var = "plan_list_int_pair_#{dest_reg}_int"
    list_out = if dest == "*out", do: "out", else: dest
    list_ptr = RcRuntimeEmit.allocator_out_arg(list_out)
    call_suffix = native_call_suffix(call_arg_s)
    pair_tmp = "plan_list_int_pair_#{dest_reg}_pair"

    call =
      if rc? do
        "Rc = #{c_name}(#{list_ptr}#{call_suffix});\nCHECK_RC(Rc);"
      else
        """
        {
          RC __call_rc = #{c_name}(#{list_ptr}#{call_suffix});
          if (__call_rc != RC_SUCCESS) {
            ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "plan call failed");
            #{RcRuntimeEmit.null_assign_stmt(list_out)}
            #{int_var} = 0;
          }
        }
        """
        |> String.trim()
      end

    # Callee returns a boxed (list, int) tuple into list_out. SROA treats list_out as
    # the list operand for later uses — peel first into list_out and keep the int in
    # a native temp (otherwise spawn/update see the tuple as a board and wipe it).
    peel =
      if dest == "*out" do
        """
        #{int_var} = elmc_as_int(elmc_tuple_second_borrow(*out));
        {
          ElmcValue *#{pair_tmp} = *out;
          *out = elmc_retain(elmc_tuple_first_borrow(#{pair_tmp}));
          elmc_release(#{pair_tmp});
        }
        """
      else
        """
        #{int_var} = elmc_as_int(elmc_tuple_second_borrow(#{list_out}));
        {
          ElmcValue *#{pair_tmp} = #{list_out};
          #{list_out} = elmc_retain(elmc_tuple_first_borrow(#{pair_tmp}));
          elmc_release(#{pair_tmp});
        }
        """
      end
      |> String.trim()

    """
    elmc_int_t #{int_var} = 0;
    #{call}
    #{peel}
    """
    |> String.trim()
  end

  @spec emit_native_scalar_fn_call(atom(), boolean(), String.t(), Types.reg() | term(), String.t(), String.t(), keyword(), {String.t(), String.t()}) :: String.t()

  defp emit_native_scalar_fn_call(:native_int_pair, rc?, dest, dest_reg, c_name, call_arg_s, opts, _callee) do
    a = "plan_native_pair_#{dest_reg}_0"
    b = "plan_native_pair_#{dest_reg}_1"
    call_suffix = native_call_suffix(call_arg_s)

    call =
      if rc? do
        "Rc = #{c_name}(&#{a}, &#{b}#{call_suffix});\nCHECK_RC(Rc);"
      else
        """
        {
          RC __call_rc = #{c_name}(&#{a}, &#{b}#{call_suffix});
          if (__call_rc != RC_SUCCESS) {
            ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "plan call failed");
            #{a} = 0;
            #{b} = 0;
          }
        }
        """
        |> String.trim()
      end

    pack =
      unless Keyword.get(opts, :native_pair_unboxed) do
        box_dest = if dest == "*out", do: "out", else: dest
        rc_assign(rc?, box_dest, "elmc_tuple2_ints", [a, b])
      else
        ""
      end

    """
    elmc_int_t #{a} = 0;
    elmc_int_t #{b} = 0;
    #{call}
    #{pack}
    """
    |> String.trim()
  end

  defp emit_native_scalar_fn_call(:native_list_int_pair, rc?, dest, dest_reg, c_name, call_arg_s, opts, _callee) do
    int_var = "plan_list_int_pair_#{dest_reg}_int"
    call_suffix = native_call_suffix(call_arg_s)
    unboxed? = Keyword.get(opts, :native_list_int_pair_unboxed)

    # Parent is also dual-out and this call is the function result: forward
    # straight into `out_list` / `out_int` (passthrough, no heap pack).
    parent_tail_dual_out? =
      Keyword.get(opts, :native_scalar_out) == :native_list_int_pair and
        (dest == "*out" or dest_reg in [:fn_out, :branch_out])

    cond do
      parent_tail_dual_out? ->
        call =
          if rc? do
            "Rc = #{c_name}(out_list, out_int#{call_suffix});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}(out_list, out_int#{call_suffix});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "plan call failed");
                *out_list = NULL;
                *out_int = 0;
              }
            }
            """
            |> String.trim()
          end

        call

      # Call-site SROA: write the list straight into the call dest owned slot and
      # keep the int as a native temp (no heap tuple pack).
      unboxed? ->
        list_out = if dest == "*out", do: "out", else: dest

        call =
          if rc? do
            "Rc = #{c_name}(#{list_out_ptr(list_out)}, &#{int_var}#{call_suffix});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}(#{list_out_ptr(list_out)}, &#{int_var}#{call_suffix});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "plan call failed");
                #{list_out_assign_null(list_out)}
                #{int_var} = 0;
              }
            }
            """
            |> String.trim()
          end

        """
        elmc_int_t #{int_var} = 0;
        #{call}
        """
        |> String.trim()

      true ->
        list_var = "plan_list_int_pair_#{dest_reg}_list"

        call =
          if rc? do
            "Rc = #{c_name}(&#{list_var}, &#{int_var}#{call_suffix});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}(&#{list_var}, &#{int_var}#{call_suffix});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "plan call failed");
                #{list_var} = NULL;
                #{int_var} = 0;
              }
            }
            """
            |> String.trim()
          end

        box_dest = if dest == "*out", do: "out", else: dest
        int_box = "plan_list_int_pair_#{dest_reg}_int_box"

        # Own list_var (from dual-out) and int_box (from elmc_new_int). Pack with
        # tuple2_take so those retains transfer into the tuple — elmc_tuple2 would
        # retain again and leave the locals as orphaned +1 refs (2048 initialModel).
        pack =
          """
          ElmcValue *#{int_box} = NULL;
          #{rc_assign(rc?, int_box, "elmc_new_int", [int_var])}
          #{rc_assign(rc?, box_dest, "elmc_tuple2_take", [list_var, int_box])}
          #{list_var} = NULL;
          #{int_box} = NULL;
          """
          |> String.trim()

        """
        ElmcValue *#{list_var} = NULL;
        elmc_int_t #{int_var} = 0;
        #{call}
        #{pack}
        """
        |> String.trim()
    end
  end

  defp emit_native_scalar_fn_call(:native_int, rc?, dest, dest_reg, c_name, call_arg_s, opts, callee) do
    value_return? = NativeReturn.value_return?(callee)
    native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())
    # Non-RC definitions with a cached native kind still return ElmcValue* (box via
    # elmc_new_int_take). Only RC callees implement the `RC fn(elmc_int_t *out, …)` ABI.
    # Also treat self-recursion inside an RC plan as out-param (unit tests seed
    # plan.rc_required without always populating `:elmc_rc_required`).
    rc_callee? = native_scalar_rc_abi?(callee, opts)
    # NativeReturn may cache :native_int while FunctionEmit still emits
    # `RC fn(ElmcValue **out, …)` (native-boxed RC). Call sites must match the
    # emitted out pointer, not the optimistic NativeReturn cache alone.
    boxed_rc_out? = rc_callee? and not value_return? and callee_boxed_rc_out?(callee)

    cond do
      value_return? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        emit_native_store(dest_reg, "plan_native_int_#{dest_reg}", "#{c_name}(#{call_arg_s})", opts)

      # A plain `return` only matches the enclosing function's own ABI when that
      # function is itself compiled without the RC/out-pointer contract. When `rc?`
      # is true, `*out` is the caller's boxed result slot and must be filled via
      # `elmc_new_int`/CHECK_RC, not returned as a raw native value in place of RC.
      value_return? and dest == "*out" and not rc? ->
        "return #{c_name}(#{call_arg_s});"

      not value_return? and not rc_callee? ->
        emit_boxed_value_callee_as_native_int(rc?, dest, dest_reg, c_name, call_arg_s, opts)

      boxed_rc_out? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        emit_boxed_rc_out_as_native_int(rc?, dest_reg, c_name, call_arg_s, opts)

      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        out = "plan_native_int_#{dest_reg}"
        rc_scalar_assign_call(rc?, c_name, out, call_arg_s, fallback: "0")

      true ->
        emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, callee, opts)
    end
  end

  defp emit_native_scalar_fn_call(:native_bool, rc?, dest, dest_reg, c_name, call_arg_s, opts, callee) do
    value_return? = NativeReturn.value_return?(callee)
    native_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    rc_callee? = native_scalar_rc_abi?(callee, opts)
    boxed_rc_out? = rc_callee? and not value_return? and callee_boxed_rc_out?(callee)

    cond do
      value_return? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        emit_native_bool_store(dest_reg, "plan_native_bool_#{dest_reg}", "#{c_name}(#{call_arg_s})", opts)

      # See the :native_int clause above: only take the raw `return` shortcut when
      # the enclosing function itself is not RC/out-pointer ABI.
      value_return? and dest == "*out" and not rc? ->
        "return #{c_name}(#{call_arg_s});"

      not value_return? and not rc_callee? ->
        emit_boxed_value_callee_as_native_bool(rc?, dest, dest_reg, c_name, call_arg_s, opts)

      boxed_rc_out? and is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        emit_boxed_rc_out_as_native_bool(rc?, dest_reg, c_name, call_arg_s, opts)

      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        out = "plan_native_bool_#{dest_reg}"
        mutable? =
          MapSet.member?(Keyword.get(opts, :native_bool_mutable_regs, MapSet.new()), dest_reg)

        if mutable? do
          # Prologue already declared `bool plan_native_bool_N = false;`
          rc_scalar_assign_call(rc?, c_name, out, call_arg_s, fallback: "false")
        else
          """
          bool #{out} = false;
          #{rc_scalar_assign_call(rc?, c_name, out, call_arg_s, fallback: "false")}
          """
          |> String.trim()
        end

      true ->
        emit_native_bool_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, callee, opts)
    end
  end

  defp list_out_ptr("out"), do: "out"
  defp list_out_ptr(dest) when is_binary(dest), do: "&#{dest}"

  defp list_out_assign_null("out"), do: "*out = NULL;"
  defp list_out_assign_null(dest) when is_binary(dest), do: "#{dest} = NULL;"

  # Matches FunctionEmit: cached native Int/Bool that is not a value-return
  # uses `RC fn(elmc_int_t *out, …)` / `RC fn(bool *out, …)` even when the
  # callee is not in the RcRequired set (union-int helpers, nested if clamps).
  defp native_scalar_rc_abi?({mod, name} = callee, opts) do
    RcRequired.rc_required?(mod, name) or
      native_scalar_rc_out_callee?(callee, opts) or
      (NativeReturn.cached_kind(callee) in [:native_int, :native_bool] and
         not NativeReturn.value_return?(callee))
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

  # True when FunctionEmit registered `RC fn(ElmcValue **out, …)` for this
  # callee (native-arg / fusion helpers with a boxed return).
  defp callee_boxed_rc_out?({mod, name}) do
    Process.get(:elmc_native_boxed_rc_abi, %{}) |> Map.get({mod, name}) == true
  end

  defp emit_boxed_rc_out_as_native_int(rc?, dest_reg, c_name, call_arg_s, opts) do
    tmp = "plan_box_out_#{dest_reg}"

    """
    ElmcValue *#{tmp} = NULL;
    #{rc_assign_call(rc?, c_name, tmp, call_arg_s)}
    #{emit_native_store(dest_reg, "plan_native_int_#{dest_reg}", "elmc_as_int(#{tmp})", opts)}
    elmc_release(#{tmp});
    """
    |> String.trim()
  end

  defp emit_boxed_rc_out_as_native_bool(rc?, dest_reg, c_name, call_arg_s, opts) do
    tmp = "plan_box_out_#{dest_reg}"

    """
    ElmcValue *#{tmp} = NULL;
    #{rc_assign_call(rc?, c_name, tmp, call_arg_s)}
    #{emit_native_bool_store(dest_reg, "plan_native_bool_#{dest_reg}", "elmc_as_bool(#{tmp})", opts)}
    elmc_release(#{tmp});
    """
    |> String.trim()
  end

  defp rc_assign_call(true, c_name, out_var, call_arg_s) do
    "Rc = #{c_name}(&#{out_var}#{native_call_suffix(call_arg_s)});\nCHECK_RC(Rc);"
  end

  defp rc_assign_call(_false_arm, c_name, out_var, call_arg_s) do
    "#{out_var} = NULL;\nif (#{c_name}(&#{out_var}#{native_call_suffix(call_arg_s)}) != RC_SUCCESS) #{out_var} = NULL;"
  end

  # Callee is `ElmcValue *fn(...)` but the caller wants a native scalar result.
  defp emit_boxed_value_callee_as_native_int(rc?, dest, dest_reg, c_name, call_arg_s, opts) do
    native_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    cond do
      is_integer(dest_reg) and MapSet.member?(native_only, dest_reg) ->
        tmp = "plan_box_int_#{dest_reg}"

        """
        ElmcValue *#{tmp} = #{c_name}(#{call_arg_s});
        #{emit_native_store(dest_reg, "plan_native_int_#{dest_reg}", "elmc_as_int(#{tmp})", opts)}
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
        #{emit_native_bool_store(dest_reg, "plan_native_bool_#{dest_reg}", "elmc_as_bool(#{tmp})", opts)}
        elmc_release(#{tmp});
        """
        |> String.trim()

      true ->
        assign_value_return(rc?, dest, "#{c_name}(#{call_arg_s})")
    end
  end

  @spec emit_native_bool_fn_call_boxed(
          boolean(),
          String.t(),
          Types.reg() | term(),
          String.t(),
          String.t(),
          {String.t(), String.t()},
          keyword()
        ) :: String.t()

  defp emit_native_bool_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, {mod, name} = callee, opts) do
    tmp = "plan_call_bool_#{dest_reg}"

    box = fn bool_src ->
      box_native_scalar_into_dest(rc?, dest, "elmc_new_bool", bool_src, opts)
    end

    cond do
      NativeReturn.value_return?(callee) ->
        """
        bool #{tmp} = #{c_name}(#{call_arg_s});
        #{box.(tmp)}
        """
        |> String.trim()

      not RcRequired.rc_required?(mod, name) ->
        """
        ElmcValue *#{tmp}_box = #{c_name}(#{call_arg_s});
        bool #{tmp} = elmc_as_bool(#{tmp}_box);
        elmc_release(#{tmp}_box);
        #{box.(tmp)}
        """
        |> String.trim()

      true ->
        """
        bool #{tmp} = false;
        #{rc_scalar_assign_call(rc?, c_name, tmp, call_arg_s, fallback: "false")}
        #{box.(tmp)}
        """
        |> String.trim()
    end
  end

  @spec emit_native_int_fn_call_boxed(
          boolean(),
          String.t(),
          Types.reg() | term(),
          String.t(),
          String.t(),
          {String.t(), String.t()},
          keyword()
        ) :: String.t()

  defp emit_native_int_fn_call_boxed(rc?, dest, dest_reg, c_name, call_arg_s, {mod, name} = callee, opts) do
    tmp = "plan_call_int_#{dest_reg}"

    box = fn int_src ->
      box_native_scalar_into_dest(rc?, dest, "elmc_new_int", int_src, opts)
    end

    cond do
      NativeReturn.value_return?(callee) ->
        """
        elmc_int_t #{tmp} = #{c_name}(#{call_arg_s});
        #{box.(tmp)}
        """
        |> String.trim()

      not RcRequired.rc_required?(mod, name) ->
        """
        ElmcValue *#{tmp}_box = #{c_name}(#{call_arg_s});
        elmc_int_t #{tmp} = elmc_as_int(#{tmp}_box);
        elmc_release(#{tmp}_box);
        #{box.(tmp)}
        """
        |> String.trim()

      true ->
        """
        elmc_int_t #{tmp} = 0;
        #{rc_scalar_assign_call(rc?, c_name, tmp, call_arg_s, fallback: "0")}
        #{box.(tmp)}
        """
        |> String.trim()
    end
  end

  # Value-returning (`ElmcValue *fn(...)`) bodies have no `out` parameter — never
  # emit `*out` / `&out` there. RC bodies box into the real `out` pointer.
  @spec box_native_scalar_into_dest(boolean(), String.t(), String.t(), String.t(), keyword()) ::
          String.t()

  defp box_native_scalar_into_dest(false, "*out", alloc_fn, scalar_src, opts)
       when is_binary(alloc_fn) and is_binary(scalar_src) do
    EphemeralBox.non_rc_scalar_return(
      alloc_fn,
      scalar_src,
      Keyword.get(opts, :owned_slot_count, 0)
    )
  end

  defp box_native_scalar_into_dest(rc?, dest, alloc_fn, scalar_src, _opts)
       when is_binary(dest) and is_binary(alloc_fn) and is_binary(scalar_src) do
    box_dest = if dest == "*out", do: "out", else: dest
    rc_assign(rc?, box_dest, alloc_fn, [scalar_src])
  end

  # RC callers use ambient `Rc` + CHECK_RC (inside CATCH). Non-RC hosts must not.
  @spec rc_scalar_assign_call(boolean(), String.t(), String.t(), String.t(), keyword()) :: String.t()

  defp rc_scalar_assign_call(true, c_name, out_var, call_arg_s, _opts) do
    "Rc = #{c_name}(&#{out_var}#{native_call_suffix(call_arg_s)});\nCHECK_RC(Rc);"
  end

  defp rc_scalar_assign_call(_false_arm, c_name, out_var, call_arg_s, opts) do
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

  @spec emit_pebble_cmd(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_pebble_cmd(%{args: %{kind: kind, params: [key, text]}} = instr, slots, rc?, dest, opts)
       when is_map(kind) do
    kind_s = Map.get(kind, :c_expr, "0")
    builtin = Map.get(Map.get(instr, :args, %{}), :builtin)

    if storage_write_string_cmd?(kind_s, builtin) do
      emit_storage_write_string_cmd(kind_s, key, text, slots, rc?, dest, opts)
    else
      emit_pebble_cmd_ints(instr, slots, rc?, dest, opts)
    end
  end

  defp emit_pebble_cmd(instr, slots, rc?, dest, opts),
    do: emit_pebble_cmd_ints(instr, slots, rc?, dest, opts)

  defp emit_pebble_cmd_ints(%{args: %{builtin: id, kind: kind, params: params}} = _instr, slots, rc?, dest, opts) do
    sym = RuntimeBuiltins.c_symbol(id) || "elmc_cmd0"
    kind_s = Map.get(kind, :c_expr, "0")
    params = params || []

    if sym == "elmc_cmd0" and params == [] and cmd_none_kind?(kind_s) do
      assign_value_return(rc?, dest, "elmc_cmd_none()")
    else
      args = Enum.join([kind_s | native_int_param_refs(params, slots, opts)], ", ")
      emit_pebble_cmd_call(sym, args, rc?, dest)
    end
  end

  defp emit_storage_write_string_cmd(kind_s, key, text, slots, rc?, dest, opts) do
    key_s = int_operand_ref(key, slots, opts)
    text_s = boxed_string_c_arg(text, slots, opts)
    args = Enum.join([kind_s, key_s, text_s], ", ")
    emit_pebble_cmd_call("elmc_cmd1_string", args, rc?, dest)
  end

  defp emit_pebble_cmd_call(sym, args, rc?, dest) do
    if rc? do
      rc_call(true, if(dest == "*out", do: "out", else: dest), sym, args)
    else
      dest_out = if(dest == "*out", do: "*out", else: dest)
      RcRuntimeEmit.non_rc_allocator_stmt(dest_out, sym, args, return_on_fail?: dest == "*out")
    end
  end

  defp storage_write_string_cmd?("ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING", _builtin), do: true
  defp storage_write_string_cmd?(_kind_s, :cmd1_string), do: true
  defp storage_write_string_cmd?(_kind_s, _builtin), do: false

  defp boxed_string_c_arg(reg, slots, opts) do
    ref = slot_ref(reg, slots, opts)

    "((#{ref} && #{ref}->tag == ELMC_TAG_STRING && #{ref}->payload) ? (const char *)#{ref}->payload : \"\")"
  end

  defp cmd_none_kind?("0"), do: true
  defp cmd_none_kind?("ELMC_PEBBLE_CMD_NONE"), do: true
  defp cmd_none_kind?(_), do: false

  @spec emit_render_cmd(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_render_cmd(%{args: %{kind: kind, params: params} = args}, slots, rc?, dest, opts) do
    if Map.get(args, :direct_scene_push) == true and Keyword.get(opts, :direct_scene_writer) do
      emit_render_cmd_scene_push(kind, params, slots, opts)
    else
      emit_render_cmd_boxed(kind, params, slots, rc?, dest, opts)
    end
  end

  @spec emit_render_cmd_boxed(term(), [Types.reg()], Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_render_cmd_boxed(kind, params, slots, rc?, dest, opts) do
    kind_s = platform_kind_c(kind)
    args = Enum.join([kind_s | padded_param_refs(params, 6, slots, opts)], ", ")
    dest_ref = if dest == "*out", do: "out", else: dest
    rc_call(rc?, dest_ref, "elmc_render_cmd6_take", args)
  end

  @spec emit_render_text_cmd(map() | term(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_render_text_cmd(%{args: %{kind: kind, params: params, text: text} = args}, slots, rc?, dest, opts) do
    if Map.get(args, :direct_scene_push) == true and Keyword.get(opts, :direct_scene_writer) do
      emit_render_text_cmd_scene_push(kind, params, text, slots, opts)
    else
      kind_s = platform_kind_c(kind)
      int_args = Enum.map(params, &int_operand_ref(&1, slots, opts))
      text_ref = slot_ref(text, slots, opts)
      dest_ref = if dest == "*out", do: "out", else: dest
      args_s = Enum.join([kind_s | int_args ++ [text_ref]], ", ")
      rc_call(rc?, dest_ref, "elmc_render_text_cmd_take", args_s)
    end
  end

  defp emit_render_text_cmd(_, _slots, _rc?, _dest, _opts), do: ""

  @spec emit_render_text_cmd_scene_push(term(), [Types.reg()], Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp emit_render_text_cmd_scene_push(kind, params, text, slots, opts) do
    kind_s = platform_kind_c(kind)
    text_ref = slot_ref(text, slots, opts)
    writer = Keyword.get(opts, :scene_writer_var, "writer")

    """
  elmc_draw_cmd_init(&scene_cmd, #{kind_s});
  scene_cmd.text = #{text_ref};
  #{emit_text_cmd_int_assignments(params, slots, opts)}
  if (elmc_scene_writer_push_cmd(#{writer}, &scene_cmd) != 0) {
    Rc = RC_ERR_OUT_OF_MEMORY;
    CHECK_RC(Rc);
  }
  """
    |> String.trim()
  end

  defp emit_text_cmd_int_assignments(params, slots, opts) do
    params
    |> Enum.with_index()
    |> Enum.map_join("\n  ", fn {param, index} ->
      "scene_cmd.p#{index} = #{int_operand_ref(param, slots, opts)};"
    end)
  end

  @spec emit_render_cmd_scene_push(term(), [Types.reg()], Types.slot_map(), keyword()) :: String.t()

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

  @spec emit_list_cursor_map(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_list_cursor_map(%{dest: dest_reg, args: args}, slots, _rc?, _dest, opts) do
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

    # Cons onto a uniquely owned reverse spine, then reverse in place. Do not
    # call `elmc_list_append` here — that pulls the boxed-append runtime into
    # every fused `List.range |> map`.
    #
    # Result list is uniquely owned by #{fwd_head} — transfer into dest (no
    # retain). Retaining without releasing the local leaks the spine and every
    # mapped element (YES drawOuterScale TickSpec Int/Record orphans).
    """
    ElmcValue *#{fwd_head} = elmc_list_nil();
    for (elmc_int_t #{idx} = #{start_s}; #{idx} <= #{end_s}; #{idx}++) {
      ElmcValue *#{item} = NULL;
      ElmcValue *loop_args[1];
      Rc = elmc_new_int(&loop_args[0], #{idx});
      CHECK_RC(Rc);
      Rc = #{closure}(&#{item}, loop_args, 1, NULL, 0);
      CHECK_RC(Rc);
      elmc_release(loop_args[0]);
      #{ListAccumulate.cons_front(fwd_head, item)}
    }
    #{ListAccumulate.inplace_reverse(fwd_head)}
    #{owned_slot_take_assign(dest_slot, fwd_head)}
    """
    |> String.trim()
  end

  @spec emit_list_walk_foldl(map(), Types.slot_map(), keyword()) :: String.t()
  defp emit_list_walk_foldl(%{dest: dest_reg, args: args}, slots, opts) do
    list_ref = slot_ref(args.list, slots, opts)
    acc_ref = slot_ref(args.acc, slots, opts)
    loop_id = Map.get(args, :lambda_idx, 0)
    captures = Map.get(args, :captures, [])
    parent = Keyword.get(opts, :parent_plan)
    closure = Elmc.Backend.C.Lower.Lambda.closure_fn_name(parent, loop_id)
    acc_var = "list_walk_foldl_acc_#{loop_id}"
    cursor = "list_walk_foldl_cursor_#{loop_id}"
    node = "list_walk_foldl_node_#{loop_id}"
    dest_slot = format_dest(dest_reg, slots, opts)
    cap_count = length(captures)

    {caps_decl, caps_arg, caps_count_arg} =
      if cap_count == 0 do
        {"", "NULL", "0"}
      else
        cap_refs = Enum.map(captures, &slot_ref(&1, slots, opts))
        init = Enum.join(cap_refs, ", ")

        {
          "ElmcValue *list_walk_foldl_caps_#{loop_id}[#{cap_count}] = { #{init} };\n",
          "list_walk_foldl_caps_#{loop_id}",
          Integer.to_string(cap_count)
        }
      end

    step = fn head_expr ->
      """
        {
          ElmcValue *__fold_next__ = NULL;
          ElmcValue *loop_args[2] = { #{head_expr}, #{acc_var} };
          Rc = #{closure}(&__fold_next__, loop_args, 2, #{caps_arg}, #{caps_count_arg});
          CHECK_RC(Rc);
          elmc_release(#{acc_var});
          #{acc_var} = __fold_next__;
        }
      """
    end

    """
    #{caps_decl}ElmcValue *#{acc_var} = elmc_retain(#{acc_ref});
    if (#{list_ref} && #{list_ref}->tag == ELMC_TAG_LAZY_MAP) {
      int list_walk_llen_#{loop_id} = elmc_lazy_map_length(#{list_ref});
      for (int list_walk_ii_#{loop_id} = 0;
           Rc == RC_SUCCESS && list_walk_ii_#{loop_id} < list_walk_llen_#{loop_id};
           list_walk_ii_#{loop_id}++) {
        ElmcValue *list_walk_nth_#{loop_id} = NULL;
        Rc = elmc_lazy_map_nth(&list_walk_nth_#{loop_id}, #{list_ref}, list_walk_ii_#{loop_id});
        CHECK_RC(Rc);
    #{step.("list_walk_nth_#{loop_id}")}
        elmc_release(list_walk_nth_#{loop_id});
        list_walk_nth_#{loop_id} = NULL;
      }
    } else {
      ElmcValue *list_walk_src_#{loop_id} = NULL;
      Rc = elmc_list_materialize_cons(&list_walk_src_#{loop_id}, #{list_ref});
      CHECK_RC(Rc);
      ElmcValue *#{cursor} = list_walk_src_#{loop_id};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
    #{step.("#{node}->head")}
        #{cursor} = #{node}->tail;
      }
      elmc_release(list_walk_src_#{loop_id});
    }
    #{owned_slot_take_assign(dest_slot, acc_var)}
    """
  end

  @spec emit_list_walk_map(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()
  defp emit_list_walk_map(%{args: %{kind: :foldl}} = instr, slots, _rc?, _dest, opts) do
    emit_list_walk_foldl(instr, slots, opts)
  end

  defp emit_list_walk_map(%{dest: dest_reg, args: args}, slots, _rc?, _dest, opts) do
    list_ref = slot_ref(args.list, slots, opts)
    loop_id = Map.get(args, :lambda_idx, 0)
    captures = Map.get(args, :captures, [])
    parent = Keyword.get(opts, :parent_plan)
    closure = Elmc.Backend.C.Lower.Lambda.closure_fn_name(parent, loop_id)
    fwd_head = "list_walk_map_head_#{loop_id}"
    cursor = "list_walk_map_cursor_#{loop_id}"
    node = "list_walk_map_node_#{loop_id}"
    item = "list_walk_map_item_#{loop_id}"
    dest_slot = format_dest(dest_reg, slots, opts)
    kind = Map.get(args, :kind, :map)
    cap_count = length(captures)

    {caps_decl, caps_arg, caps_count_arg} =
      if cap_count == 0 do
        {"", "NULL", "0"}
      else
        cap_refs = Enum.map(captures, &slot_ref(&1, slots, opts))
        init = Enum.join(cap_refs, ", ")

        {
          "ElmcValue *list_walk_map_caps_#{loop_id}[#{cap_count}] = { #{init} };\n",
          "list_walk_map_caps_#{loop_id}",
          Integer.to_string(cap_count)
        }
      end

    # Compact INT_LIST spines (e.g. elmc_list_from_int_array permutation tables)
    # must be walked; a cons-only loop silently maps them to [].
    # Stored `List.map` results may be ELMC_TAG_LAZY_MAP — walk with nth so the
    # second map is not empty (hour ticks) and we do not cons the whole source.
    # Result list is uniquely owned by #{fwd_head} — transfer into dest (no retain).
    {int_step, cons_step, nth_step} =
      list_walk_step_blocks(kind, loop_id, item, node, closure, caps_arg, caps_count_arg)

    idx_init = if kind == :indexed_map, do: "int list_walk_idx_#{loop_id} = 0;\n      ", else: ""
    int_items? = list_walk_int_items?(parent, loop_id, kind)

    int_list_branch =
      cond do
        not int_items? ->
          nil

        kind == :filter ->
          pred_c =
            IntListFilterPred.c_expr(
              Enum.at(parent.lambdas || [], loop_id),
              "direct_ilp_#{loop_id}->values[direct_ii_#{loop_id}]"
            )

          compact_int_list_filter_branch(
            loop_id,
            list_ref,
            fwd_head,
            item,
            closure,
            caps_arg,
            caps_count_arg,
            pred_c
          )

        kind == :map ->
          """
            Rc = elmc_lazy_map(&#{fwd_head}, #{list_ref}, #{closure}, #{caps_arg}, #{caps_count_arg});
            CHECK_RC(Rc);
          """

        true ->
          """
            ElmcIntListPayload *direct_ilp_#{loop_id} = (ElmcIntListPayload *)#{list_ref}->payload;
            int direct_ilen_#{loop_id} = direct_ilp_#{loop_id} ? direct_ilp_#{loop_id}->length : 0;
            for (int direct_ii_#{loop_id} = 0;
                 Rc == RC_SUCCESS && direct_ii_#{loop_id} < direct_ilen_#{loop_id};
                 direct_ii_#{loop_id}++) {
              ElmcValue *__map_head_box__ = NULL;
              Rc = elmc_new_int(&__map_head_box__, direct_ilp_#{loop_id}->values[direct_ii_#{loop_id}]);
              CHECK_RC(Rc);
              #{int_step}
              elmc_release(__map_head_box__);
              __map_head_box__ = NULL;
            }
          """
      end

    reverse_guard =
      if kind in [:filter, :map] do
        "if (list_walk_need_reverse_#{loop_id}) "
      else
        ""
      end

    need_reverse_init =
      if kind in [:filter, :map], do: "int list_walk_need_reverse_#{loop_id} = 1;\n    ", else: ""

    set_no_reverse =
      if kind in [:filter, :map] do
        "      list_walk_need_reverse_#{loop_id} = 0;\n"
      else
        ""
      end

    int_list_prefix =
      if is_binary(int_list_branch) do
        """
        if (#{list_ref} && #{list_ref}->tag == ELMC_TAG_INT_LIST) {
        #{int_list_branch}#{set_no_reverse}    } else \
        """
      else
        ""
      end

    # Nested `List.map` over a stored lazy map must compose another lazy map —
    # walking with nth + cons materializes the whole spine (size regression).
    lazy_map_branch =
      if kind == :map do
        """
        if (#{list_ref} && #{list_ref}->tag == ELMC_TAG_LAZY_MAP) {
          Rc = elmc_lazy_map(&#{fwd_head}, #{list_ref}, #{closure}, #{caps_arg}, #{caps_count_arg});
          CHECK_RC(Rc);
        #{set_no_reverse}    } else {
        """
      else
        """
        if (#{list_ref} && #{list_ref}->tag == ELMC_TAG_LAZY_MAP) {
          int list_walk_llen_#{loop_id} = elmc_lazy_map_length(#{list_ref});
          #{idx_init}for (int list_walk_ii_#{loop_id} = 0;
               Rc == RC_SUCCESS && list_walk_ii_#{loop_id} < list_walk_llen_#{loop_id};
               list_walk_ii_#{loop_id}++) {
            ElmcValue *list_walk_nth_#{loop_id} = NULL;
            Rc = elmc_lazy_map_nth(&list_walk_nth_#{loop_id}, #{list_ref}, list_walk_ii_#{loop_id});
            CHECK_RC(Rc);
            #{nth_step}
            elmc_release(list_walk_nth_#{loop_id});
            list_walk_nth_#{loop_id} = NULL;
          }
        } else {
        """
      end

    body = """
    #{caps_decl}#{need_reverse_init}ElmcValue *#{fwd_head} = elmc_list_nil();
    #{int_list_prefix}#{lazy_map_branch}
      ElmcValue *list_walk_src_#{loop_id} = NULL;
      Rc = elmc_list_materialize_cons(&list_walk_src_#{loop_id}, #{list_ref});
      CHECK_RC(Rc);
      ElmcValue *#{cursor} = list_walk_src_#{loop_id};
      #{idx_init}while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        #{cons_step}
        #{cursor} = #{node}->tail;
      }
      elmc_release(list_walk_src_#{loop_id});
    }
    #{reverse_guard}#{ListAccumulate.inplace_reverse(fwd_head)}
    #{owned_slot_take_assign(dest_slot, fwd_head)}
    """

    body
  end

  # Compact INT_LIST walks only apply to `List Int` (and Color ints). Mapping
  # records or strings must not emit that backend — it is dead and large.
  # Lambda `Param.type` is often nil (`List.map : (a -> b) -> …` erases `a`),
  # so a non-int use of the item param is also enough to drop the walk.
  defp list_walk_int_items?(parent, loop_id, kind) do
    lambda = Enum.at((parent && parent.lambdas) || [], loop_id)

    case item_param_int_kind(lambda, kind) do
      :native_int -> true
      :non_int -> false
      :unknown -> not lambda_item_used_as_non_int?(lambda, kind)
    end
  end

  defp item_param_int_kind(lambda, kind) do
    params = (lambda && lambda.params) || []
    item = Enum.at(params, item_param_index(kind))

    case item do
      %{type: ty} when is_binary(ty) ->
        if Host.color_type?(ty) or Host.signature_param_kind(ty) == :native_int do
          :native_int
        else
          :non_int
        end

      _ ->
        :unknown
    end
  end

  defp item_param_index(:indexed_map), do: 1
  defp item_param_index(_), do: 0

  defp lambda_item_used_as_non_int?(nil, _), do: false

  defp lambda_item_used_as_non_int?(lambda, kind) do
    regs = item_param_alias_regs(lambda, item_param_index(kind))

    regs != [] and
      Enum.any?(lambda_instrs(lambda), fn instr ->
        non_int_item_use?(instr, regs)
      end)
  end

  defp item_param_alias_regs(lambda, index) do
    instrs = lambda_instrs(lambda)

    loaded =
      Enum.flat_map(instrs, fn
        %{op: :load_param, dest: dest, args: %{index: ^index}} when is_integer(dest) ->
          [dest]

        _ ->
          []
      end)

    Enum.reduce(instrs, MapSet.new(loaded), fn
      %{op: :call_runtime, dest: dest, args: %{builtin: :retain, args: [src]}}, acc
      when is_integer(dest) and is_integer(src) ->
        if MapSet.member?(acc, src), do: MapSet.put(acc, dest), else: acc

      _, acc ->
        acc
    end)
  end

  defp lambda_instrs(%{blocks: blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, fn
      %{instrs: instrs} when is_list(instrs) -> instrs
      _ -> []
    end)
  end

  defp lambda_instrs(_), do: []

  defp non_int_item_use?(%{op: :call_runtime, args: %{builtin: builtin, args: args}}, regs)
       when builtin in [
              :string_append,
              :string_concat,
              :string_length,
              :string_length_boxed,
              :record_new,
              :record_new_take,
              :record_get
            ] do
    Enum.any?(List.wrap(args), &MapSet.member?(regs, &1))
  end

  defp non_int_item_use?(%{op: op, args: args}, regs)
       when op in [:record_get, :record_get_int] and is_map(args) do
    Enum.any?([args[:record], args[:base], args[:subject]], &MapSet.member?(regs, &1))
  end

  defp non_int_item_use?(_, _), do: false

  defp compact_int_list_filter_branch(
         loop_id,
         list_ref,
         fwd_head,
         item,
         closure,
         caps_arg,
         caps_count_arg,
         pred_c
       ) do
    keep_test =
      if is_binary(pred_c) do
        """
            if (#{pred_c}) {
              list_walk_kept_#{loop_id}[list_walk_kept_n_#{loop_id}++] = direct_ilp_#{loop_id}->values[direct_ii_#{loop_id}];
            }
        """
      else
        """
            ElmcValue *__map_head_box__ = NULL;
            Rc = elmc_new_int(&__map_head_box__, direct_ilp_#{loop_id}->values[direct_ii_#{loop_id}]);
            if (Rc != RC_SUCCESS) break;
            ElmcValue *#{item} = NULL;
            ElmcValue *loop_args[1] = { __map_head_box__ };
            Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
            elmc_release(__map_head_box__);
            __map_head_box__ = NULL;
            if (Rc != RC_SUCCESS) {
              elmc_release(#{item});
              break;
            }
            if (elmc_as_int(#{item}) != 0) {
              list_walk_kept_#{loop_id}[list_walk_kept_n_#{loop_id}++] = direct_ilp_#{loop_id}->values[direct_ii_#{loop_id}];
            }
            elmc_release(#{item});
            #{item} = NULL;
        """
      end

    """
          ElmcIntListPayload *direct_ilp_#{loop_id} = (ElmcIntListPayload *)#{list_ref}->payload;
          int direct_ilen_#{loop_id} = direct_ilp_#{loop_id} ? direct_ilp_#{loop_id}->length : 0;
          elmc_int_t *list_walk_kept_#{loop_id} = NULL;
          int list_walk_kept_n_#{loop_id} = 0;
          if (direct_ilen_#{loop_id} > 0) {
            list_walk_kept_#{loop_id} = (elmc_int_t *)elmc_malloc((size_t)direct_ilen_#{loop_id} * sizeof(elmc_int_t), "list_walk_filter");
            if (!list_walk_kept_#{loop_id}) {
              Rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(Rc);
            }
          }
          for (int direct_ii_#{loop_id} = 0;
               Rc == RC_SUCCESS && direct_ii_#{loop_id} < direct_ilen_#{loop_id};
               direct_ii_#{loop_id}++) {
    #{keep_test}          }
          if (Rc == RC_SUCCESS) {
            Rc = elmc_list_from_int_array(&#{fwd_head}, list_walk_kept_#{loop_id}, list_walk_kept_n_#{loop_id});
          }
          if (list_walk_kept_#{loop_id}) elmc_free(list_walk_kept_#{loop_id});
          CHECK_RC(Rc);
    """
  end

  defp list_walk_step_blocks(:filter, loop_id, item, node, closure, caps_arg, caps_count_arg) do
    fwd = "list_walk_map_head_#{loop_id}"

    int_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *loop_args[1] = { __map_head_box__ };
        Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
        CHECK_RC(Rc);
        if (elmc_as_int(#{item}) != 0) {
          #{ListAccumulate.cons_front_keep_item(fwd, "__map_head_box__")}
        }
        elmc_release(#{item});
        #{item} = NULL;
    """

    cons_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *loop_args[1] = { #{node}->head };
        Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
        CHECK_RC(Rc);
        if (elmc_as_int(#{item}) != 0) {
          #{ListAccumulate.cons_front_keep_item(fwd, "#{node}->head")}
        }
        elmc_release(#{item});
        #{item} = NULL;
    """

    nth_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *loop_args[1] = { list_walk_nth_#{loop_id} };
        Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
        CHECK_RC(Rc);
        if (elmc_as_int(#{item}) != 0) {
          #{ListAccumulate.cons_front_keep_item(fwd, "list_walk_nth_#{loop_id}")}
        }
        elmc_release(#{item});
        #{item} = NULL;
    """

    {int_step, cons_step, nth_step}
  end

  defp list_walk_step_blocks(:indexed_map, loop_id, item, node, closure, caps_arg, caps_count_arg) do
    fwd = "list_walk_map_head_#{loop_id}"
    idx = "list_walk_idx_#{loop_id}"

    int_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *__idx_box__ = NULL;
        Rc = elmc_new_int(&__idx_box__, direct_ii_#{loop_id});
        CHECK_RC(Rc);
        ElmcValue *loop_args[2] = { __idx_box__, __map_head_box__ };
        Rc = #{closure}(&#{item}, loop_args, 2, #{caps_arg}, #{caps_count_arg});
        elmc_release(__idx_box__);
        CHECK_RC(Rc);
        #{ListAccumulate.cons_front(fwd, item)}
    """

    cons_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *__idx_box__ = NULL;
        Rc = elmc_new_int(&__idx_box__, #{idx});
        CHECK_RC(Rc);
        ElmcValue *loop_args[2] = { __idx_box__, #{node}->head };
        Rc = #{closure}(&#{item}, loop_args, 2, #{caps_arg}, #{caps_count_arg});
        elmc_release(__idx_box__);
        CHECK_RC(Rc);
        #{ListAccumulate.cons_front(fwd, item)}
        #{idx} += 1;
    """

    nth_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *__idx_box__ = NULL;
        Rc = elmc_new_int(&__idx_box__, #{idx});
        CHECK_RC(Rc);
        ElmcValue *loop_args[2] = { __idx_box__, list_walk_nth_#{loop_id} };
        Rc = #{closure}(&#{item}, loop_args, 2, #{caps_arg}, #{caps_count_arg});
        elmc_release(__idx_box__);
        CHECK_RC(Rc);
        #{ListAccumulate.cons_front(fwd, item)}
        #{idx} += 1;
    """

    {int_step, cons_step, nth_step}
  end

  defp list_walk_step_blocks(_kind, loop_id, item, node, closure, caps_arg, caps_count_arg) do
    fwd = "list_walk_map_head_#{loop_id}"

    int_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *loop_args[1] = { __map_head_box__ };
        Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
        CHECK_RC(Rc);
        #{ListAccumulate.cons_front(fwd, item)}
    """

    cons_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *loop_args[1] = { #{node}->head };
        Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
        CHECK_RC(Rc);
        #{ListAccumulate.cons_front(fwd, item)}
    """

    nth_step = """
        ElmcValue *#{item} = NULL;
        ElmcValue *loop_args[1] = { list_walk_nth_#{loop_id} };
        Rc = #{closure}(&#{item}, loop_args, 1, #{caps_arg}, #{caps_count_arg});
        CHECK_RC(Rc);
        #{ListAccumulate.cons_front(fwd, item)}
    """

    {int_step, cons_step, nth_step}
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
          emit_native_store(dest_reg, "plan_native_int_#{dest_reg}", acc, opts)

        dest == "*out" and rc? ->
          rc_assign(true, "out", "elmc_new_int", [acc])

        dest == "*out" ->
          EphemeralBox.non_rc_scalar_return("elmc_new_int", acc, Keyword.get(opts, :owned_slot_count, 0))

        rc? ->
          rc_assign(true, dest_slot, "elmc_new_int", [acc])

        true ->
          EphemeralBox.non_rc_scalar_assign(dest_slot, "elmc_new_int", acc)
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
          owned_slot_take_assign(dest_slot, acc)
      end

    String.trim(loop_body <> "\n" <> assign)
  end

  @spec emit_pebble_sub(map(), Types.slot_map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_pebble_sub(%{args: %{kind: mask, params: params}} = _instr, slots, rc?, dest, opts) do
    mask_s = platform_kind_c(mask)
    arity = length(params)
    fn_name = "elmc_sub#{arity}"
    args = Enum.join([mask_s | native_int_param_refs(params, slots, opts)], ", ")

    if rc? do
      rc_call(true, if(dest == "*out", do: "out", else: dest), fn_name, args)
    else
      dest_out = if(dest == "*out", do: "*out", else: dest)
      RcRuntimeEmit.non_rc_allocator_stmt(dest_out, fn_name, args, return_on_fail?: dest == "*out")
    end
  end

  @spec platform_kind_c(map() | term()) :: String.t()

  defp platform_kind_c(%{c_expr: value}) when is_binary(value), do: value
  defp platform_kind_c(%{literal: value}) when is_integer(value), do: Integer.to_string(value)
  defp platform_kind_c(_), do: "0"

  @spec padded_param_refs([Types.reg()], integer(), Types.slot_map(), keyword()) :: [String.t()]

  defp padded_param_refs(params, n, slots, opts) do
    refs = native_int_param_refs(params, slots, opts)
    refs ++ List.duplicate("0", max(0, n - length(refs)))
  end

  @spec native_int_param_refs([Types.reg()], Types.slot_map(), keyword()) :: [String.t()]

  defp native_int_param_refs(params, slots, opts) do
    Enum.map(params, fn reg -> int_operand_ref(reg, slots, opts) end)
  end

  @doc false
  @spec int_operand_ref(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

  def int_operand_ref(reg, slots, opts) when is_integer(reg), do: int_operand_ref_impl(reg, slots, opts)

  def int_operand_ref(dest, slots, opts) when dest in [:fn_out, :branch_out] do
    "elmc_as_int(#{slot_ref(dest, slots, opts)})"
  end

  @spec int_operand_ref_impl(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec native_int_borrow_param?(Types.reg(), keyword()) :: boolean()

  defp native_int_borrow_param?(reg, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} ->
        Enum.at(Keyword.get(opts, :param_kinds, []), index) == :native_int

      _ ->
        false
    end
  end

  @spec int_operand_ref_impl_no_copy(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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
                native_int_regs_c_operand_ref(reg, name, opts)

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
                                native_int_param_c_arg(index, opts)

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
                              case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
                                %{op: :load_param, args: %{index: index}} ->
                                  native_int_param_c_arg(index, opts)

                                _ ->
                                  c_arg
                              end
                            else
                              if boxed_direct_scene_argv_active?(opts) do
                                "elmc_as_int_number(#{c_arg})"
                              else
                                "elmc_as_int(#{c_arg})"
                              end
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
  @spec switch_subject_ref(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()
  def switch_subject_ref(:fn_out, _slots, _opts), do: "*out"
  def switch_subject_ref(:branch_out, _slots, _opts), do: "*out"

  def switch_subject_ref(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
      c_arg when is_binary(c_arg) ->
        c_arg

      _ ->
        case native_int_param_c_ref(reg, opts) do
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

  @spec native_int_param_c_ref(Types.reg(), keyword()) :: String.t() | nil

  defp native_int_param_c_ref(reg, opts) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} ->
        case Enum.at(Keyword.get(opts, :param_kinds, []), index) do
          :native_int ->
            native_int_param_c_arg(index, opts)

          :native_bool ->
            FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @spec native_int_regs_c_operand_ref(Types.reg(), String.t(), keyword()) :: String.t()

  @spec boxed_direct_scene_argv_active?(keyword()) :: boolean()

  defp boxed_direct_scene_argv_active?(opts) do
    Keyword.get(opts, :boxed_direct_scene_argv?, false) or
      (Process.get(:elmc_direct_scene_writer) == true and
         Process.get(:elmc_direct_scene_boxed_argv) == true)
  end

  defp native_int_regs_c_operand_ref(_reg, name, opts) when is_binary(name) do
    if boxed_direct_scene_argv_active?(opts) do
      "elmc_as_int_number(#{name})"
    else
      name
    end
  end

  @spec native_int_param_c_arg(non_neg_integer(), keyword()) :: String.t()

  defp native_int_param_c_arg(index, opts) do
    c_arg = FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

    if boxed_direct_scene_argv_active?(opts) do
      "elmc_as_int_number(#{c_arg})"
    else
      c_arg
    end
  end

  @spec boxed_value_ref(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

  defp boxed_value_ref(dest, slots, opts) when dest in [:fn_out, :branch_out],
    do: slot_ref(dest, slots, opts)

  defp boxed_value_ref(reg, slots, opts) when is_integer(reg) do
    if Map.has_key?(slots, reg) and is_nil(native_int_param_c_ref(reg, opts)) do
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

  @spec boxed_value_ref_from_const_or_plan(Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp boxed_value_ref_from_const_or_plan(reg, slots, opts) do
    case Map.get(Keyword.get(opts, :const_int_regs, %{}), reg) do
      entry when not is_nil(entry) ->
        if const_int_bool_lit?(entry) do
          EphemeralBox.bool(Integer.to_string(const_int_value(entry)))
        else
          EphemeralBox.int(const_int_c_ref(entry, opts))
        end

      nil ->
        boxed_value_ref_from_native_or_defining(reg, slots, opts)
    end
  end

  @spec boxed_value_ref_from_native_or_defining(Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp boxed_value_ref_from_native_or_defining(reg, slots, opts) do
    native_bool_only = Keyword.get(opts, :native_bool_only_regs, MapSet.new())
    native_bool_regs = Keyword.get(opts, :native_bool_regs, %{})

    cond do
      MapSet.member?(native_bool_only, reg) or Map.has_key?(native_bool_regs, reg) ->
        EphemeralBox.bool(phi_truthy_arm_expr(reg, slots, opts))

      true ->
        boxed_value_ref_from_native_int_or_defining(reg, slots, opts)
    end
  end

  defp boxed_value_ref_from_native_int_or_defining(reg, slots, opts) do
    case Map.get(Keyword.get(opts, :native_int_regs, %{}), reg) do
      name when is_binary(name) ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
          EphemeralBox.int(int_operand_ref(reg, slots, opts))
        else
          EphemeralBox.int(name)
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

                EphemeralBox.int(ref)

              Enum.at(param_kinds, index) == :native_bool ->
                ref =
                  Map.get(Keyword.get(opts, :native_bool_regs, %{}), reg) ||
                    FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

                EphemeralBox.bool(ref)

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
              EphemeralBox.bool(Integer.to_string(value))
            else
              EphemeralBox.int(Integer.to_string(value))
            end

          %{op: :call_runtime, args: %{builtin: :new_int, literal: value}}
          when is_integer(value) ->
            EphemeralBox.int(Integer.to_string(value))

          %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}}
          when is_binary(expr) ->
            EphemeralBox.int(expr)

          %{op: :call_runtime, args: %{builtin: :new_int, args: [inner]}}
          when is_integer(inner) ->
            case Map.get(Keyword.get(opts, :const_int_regs, %{}), inner) do
              entry when not is_nil(entry) ->
                EphemeralBox.int(const_int_c_ref(entry, opts))

              _ ->
                case peel_native_int_operand_ref(inner, slots, opts) do
                  peeled when is_binary(peeled) -> EphemeralBox.int(peeled)
                  _ -> slot_ref(reg, slots, opts)
                end
            end

          _ ->
            if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
              EphemeralBox.int(int_operand_ref(reg, slots, opts))
            else
              slot_ref(reg, slots, opts)
            end
        end
    end
  end

  @spec tail_inline_take_expr(Types.reg(), Types.slot_map(), keyword()) :: String.t() | nil

  defp tail_inline_take_expr(reg, slots, opts) when is_integer(reg) do
    case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :const_int, args: %{value: value} = args} when is_integer(value) ->
        if Map.get(args, :bool_lit) == true do
          EphemeralBox.bool(Integer.to_string(value))
        else
          EphemeralBox.int(Integer.to_string(value))
        end

      %{args: %{builtin: :tuple2_ints, args: [left, right]}} ->
        EphemeralBox.tuple2_ints(
          int_operand_ref(left, slots, opts),
          int_operand_ref(right, slots, opts)
        )

      %{args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
        EphemeralBox.int(Integer.to_string(value))

      %{args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
        EphemeralBox.int(expr)

      %{op: :call_runtime, args: %{builtin: :retain, view_peel: _} = _args} ->
        slot_ref(reg, slots, opts)

      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        boxed_value_ref(src, slots, opts)

      _ ->
        nil
    end
  end

  @spec int_scalar_from_boxed_ref(String.t()) :: String.t()

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

  @spec defining_plan_instr(map() | term(), Types.reg() | term()) :: Types.t() | nil

  defp defining_plan_instr(%{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp defining_plan_instr(_, _), do: nil

  @spec peel_native_int_operand_ref(Types.reg() | term(), Types.slot_map() | term(), keyword() | term(), MapSet.t() | term()) :: String.t() | nil

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
            :native_int -> native_int_param_c_arg(index, opts)
            _ -> nil
          end

        _ ->
          nil
      end
    end
  end

  @spec peel_native_int_copy_ref(Types.reg(), Types.slot_map(), keyword()) :: String.t() | nil

  defp peel_native_int_copy_ref(reg, slots, opts) when is_integer(reg) do
    native_int_only = Keyword.get(opts, :native_int_only_regs, MapSet.new())

    # Avoid `with true <- MapSet.member?` — when membership is success-typed `true`,
    # Dialyzer reports Pattern false / Type true on the generated failure arm.
    case MapSet.member?(native_int_only, reg) do
      true ->
        case defining_plan_instr(Keyword.get(opts, :parent_plan), reg) do
          %{op: :int_arith, args: args} ->
            case identity_int_arith_source(args) do
              src when is_integer(src) -> int_operand_ref(src, slots, opts)
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @spec identity_int_arith_source(map() | term()) :: Types.reg() | nil

  defp identity_int_arith_source(%{kind: :add_const, lhs: lhs, value: 0}), do: lhs
  defp identity_int_arith_source(%{kind: :sub_const, lhs: lhs, value: 0}), do: lhs
  defp identity_int_arith_source(_), do: nil

  @spec skip_inlined_int_dest?(Types.reg() | term(), keyword() | term()) :: boolean()

  defp skip_inlined_int_dest?(dest_reg, opts) when is_integer(dest_reg) do
    Map.has_key?(Keyword.get(opts, :native_int_inline, %{}), dest_reg)
  end

  defp skip_inlined_int_dest?(_, _), do: false

  @spec bool_operand_ref(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec native_int_direct_regs(keyword()) :: %{optional(Types.reg()) => String.t()}

  defp native_int_direct_regs(opts), do: Keyword.get(opts, :native_int_regs, %{})

  @spec emit_const_static_list(map(), Types.slot_map(), String.t(), boolean(), keyword()) :: String.t()

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
        emit_const_static_list_from_regs(args, slots, dest, rc?, values_id, "plan_list_items", "elmc_list_from_values", opts)

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

  @spec emit_const_static_list_from_regs(map(), Types.slot_map(), String.t(), boolean(), term(), String.t(), String.t(), keyword()) :: String.t()

  defp emit_const_static_list_from_regs(args, slots, dest, rc?, values_id, prefix, callee, opts) do
    regs = Map.fetch!(args, :regs)
    count = length(regs)
    array_name = "#{prefix}_#{values_id}"

    {refs, prep} =
      regs
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {reg, idx}, prep_acc ->
        ref = boxed_value_ref(reg, slots, opts)
        {ref, {prep_acc, _}} = EphemeralBox.materialize(ref, prep_acc, [], opts, true)
        prior = Enum.take(regs, idx)

        ref =
          if reg in prior do
            "elmc_retain(#{ref})"
          else
            ref
          end

        {ref, prep_acc}
      end)

    refs_s = Enum.join(refs, ", ")

    """
    #{Enum.join(prep, "\n")}
    ElmcValue *#{array_name}[#{count}] = { #{refs_s} };
    #{rc_assign(rc?, dest, callee, [array_name, Integer.to_string(count)])}
    """
    |> String.trim()
  end

  @spec emit_const_immortal_string(map(), String.t(), boolean()) :: String.t()

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

  @spec emit_platform_static_int(map(), boolean(), String.t(), keyword()) :: String.t()

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

  @spec emit_platform_static_bool(map(), boolean(), String.t(), keyword()) :: String.t()

  defp emit_platform_static_bool(%{dest: dest_reg, args: args}, rc?, dest, opts) do
    macro = Map.fetch!(args, :macro)
    then_val = bool_c_literal(Map.fetch!(args, :then))
    else_val = bool_c_literal(Map.fetch!(args, :else))

    native_bool? =
      is_integer(dest_reg) and
        MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), dest_reg)

    if native_bool? do
      """
      #if defined(#{macro})
      #{emit_native_bool_store(dest_reg, dest, then_val, opts)}
      #else
      #{emit_native_bool_store(dest_reg, dest, else_val, opts)}
      #endif
      """
      |> String.trim()
    else
      """
      #if defined(#{macro})
      #{rc_assign(rc?, dest, "elmc_new_bool", [then_val])}
      #else
      #{rc_assign(rc?, dest, "elmc_new_bool", [else_val])}
      #endif
      """
      |> String.trim()
    end
  end

  defp bool_c_literal(true), do: "true"
  defp bool_c_literal(false), do: "false"
  defp bool_c_literal(1), do: "true"
  defp bool_c_literal(0), do: "false"

  @spec rc_assign(boolean(), String.t(), String.t(), [String.t()]) :: String.t()

  defp rc_assign(true, dest, fn_name, args) do
    if owned_slot_dest?(dest), do: RecordCompile.clear_borrowed_owned_ref(dest)
    dest_ref = if String.starts_with?(dest, "*"), do: "out", else: dest
    call_args = format_call_args(dest_arg(dest_ref, dest), Enum.join(args, ", "))
    "Rc = #{fn_name}(#{call_args});\nCHECK_RC(Rc);"
  end

  defp rc_assign(_false_arm, dest, fn_name, args) do
    if owned_slot_dest?(dest), do: RecordCompile.clear_borrowed_owned_ref(dest)
    arg_s = Enum.join(args, ", ")
    RcRuntimeEmit.non_rc_allocator_stmt(dest, fn_name, arg_s, return_on_fail?: dest == "*out")
  end

  defp emit_load_local(%{dest: dest_reg, args: %{source: src_reg}}, slots, rc?, dest, opts)
       when is_integer(dest_reg) and is_integer(src_reg) do
    {src, prep, cleanup} = materialize_owned_assign_src(src_reg, slots, opts)

    body =
      case {Map.get(slots, dest_reg), Map.get(slots, src_reg)} do
        {dest_idx, src_idx}
        when is_integer(dest_idx) and is_integer(src_idx) and dest_idx != src_idx ->
          # Owned→owned alias without retain/transfer double-frees on epilogue release.
          if rc? do
            retain_into_owned(dest, src)
          else
            RecordCompile.clear_borrowed_owned_ref(dest)
            "#{dest} = elmc_retain(#{src});"
          end

        _ ->
          # Propagate or clear borrow marks when aliasing into an owned slot.
          if owned_slot_dest?(dest) do
            if RecordCompile.borrowed_owned_ref?(src) do
              RecordCompile.mark_borrowed_owned_ref(dest)
            else
              RecordCompile.clear_borrowed_owned_ref(dest)
            end
          end

          "#{dest} = #{src};"
      end

    emit_with_ephemeral_cleanup(prep, body, cleanup)
  end

  defp emit_load_local(%{args: %{source: src_reg}}, slots, _rc?, dest, opts) do
    {src, prep, cleanup} = materialize_owned_assign_src(src_reg, slots, opts)

    body =
      if owned_slot_dest?(dest) do
        if RecordCompile.borrowed_owned_ref?(src) do
          RecordCompile.mark_borrowed_owned_ref(dest)
        else
          RecordCompile.clear_borrowed_owned_ref(dest)
        end

        "#{dest} = #{src};"
      else
        "#{dest} = #{src};"
      end

    emit_with_ephemeral_cleanup(prep, body, cleanup)
  end

  @spec materialize_owned_assign_src(Types.reg(), Types.slot_map(), keyword()) ::
          {String.t(), [String.t()], [String.t()]}
  defp materialize_owned_assign_src(src_reg, slots, opts) do
    ref =
      case Map.get(slots, src_reg) do
        i when is_integer(i) ->
          "owned[#{i}]"

        _ ->
          boxed_value_ref(src_reg, slots, opts)
      end

    if EphemeralBox.ephemeral?(ref) do
      materialize_opts = Keyword.put_new(opts, :rc_required, Keyword.get(opts, :rc_required, true))
      {var, {prep, cleanup}} = EphemeralBox.materialize(ref, [], [], materialize_opts, true)
      {var, prep, cleanup}
    else
      {ref, [], []}
    end
  end

  @spec emit_owned_slot_transfer(Types.reg(), Types.reg(), Types.slot_map(), String.t(), String.t(), boolean(), keyword()) ::
          String.t()
  defp emit_owned_slot_transfer(dest_reg, src_reg, slots, dest, src_s, rc?, opts) do
    case {Map.get(slots, dest_reg), Map.get(slots, src_reg)} do
      {idx, idx} when is_integer(idx) ->
        # Same physical slot after coalescing — transfer is a no-op.
        ""

      {dest_idx, src_idx} when is_integer(dest_idx) and is_integer(src_idx) and dest_idx != src_idx ->
        src_ref = "owned[#{src_idx}]"
        dest_ref = "owned[#{dest_idx}]"

        if RecordCompile.borrowed_owned_ref?(src_ref) do
          RecordCompile.mark_borrowed_owned_ref(dest_ref)
        else
          RecordCompile.clear_borrowed_owned_ref(dest_ref)
        end

        """
        #{dest_ref} = #{src_ref};
        #{src_ref} = NULL;
        """

      _ ->
        if EphemeralBox.ephemeral?(src_s) do
          materialize_opts = Keyword.put_new(opts, :rc_required, rc?)
          {src, prep, cleanup} = materialize_ephemeral_src(src_s, materialize_opts, true)
          emit_with_ephemeral_cleanup(prep, assign_value_return(rc?, dest, src), cleanup)
        else
          assign_value_return(rc?, dest, src_s)
        end
    end
  end

  @spec assign_value_return(boolean(), String.t(), String.t()) :: String.t()

  # Non-RC `ElmcValue *` ABI: function result is a returned pointer.
  # RC ABI: `*out` is the result slot — never `return` a pointer from an RC function.
  defp assign_value_return(false, "*out", call_expr), do: "return #{call_expr};"

  defp assign_value_return(_rc?, dest, call_expr) do
    # Slot reuse: a later owned write must clear a stale borrow mark or epilogue
    # will null-without-release a real owned value (2048 list leaks).
    if owned_slot_dest?(dest), do: RecordCompile.clear_borrowed_owned_ref(dest)
    "#{dest} = #{call_expr};"
  end

  @spec assign_value_return_tail(boolean(), String.t(), String.t(), Types.t() | map(), Types.slot_map(), keyword()) :: String.t()

  defp assign_value_return_tail(false, "*out", call_expr, instr, slots, opts),
    do: wrap_non_rc_fn_out_return(call_expr, instr, slots, opts)

  defp assign_value_return_tail(rc?, dest, call_expr, _instr, _slots, _opts),
    do: assign_value_return(rc?, dest, call_expr)

  @spec wrap_non_rc_rc_allocator_return(String.t(), [String.t()], Types.t() | map(), Types.slot_map(), keyword()) :: String.t()

  defp wrap_non_rc_rc_allocator_return(sym, c_args, instr, slots, opts)
       when is_binary(sym) and is_list(c_args) do
    slot_count = Keyword.get(opts, :owned_slot_count, 0)
    cleanup = owned_consume_cleanup_lines(instr, slots, opts)
    cow_drop = non_rc_record_update_cow_drop(instr, slots, opts, "__rc_ret")
    call_args = Enum.join(c_args, ", ")

    alloc_call =
      if call_args == "" do
        "#{sym}(&__rc_ret)"
      else
        "#{sym}(&__rc_ret, #{call_args})"
      end

    failure_cleanup =
      if slot_count > 0 do
        "elmc_release_array_lifo(owned, #{slot_count});"
      else
        ""
      end

    # Drop retain-operand result aliases against `__rc_ret` inside this block.
    # Post-instr RetainOperandAlias on `*out` is unreachable here (ElmcValue* ABI)
    # and does not compile.
    alias_drop = non_rc_result_alias_drop(instr, slots, opts, "__rc_ret")

    alias_or_null =
      cond do
        alias_drop != "" ->
          alias_drop

        slot_count > 0 ->
          "elmc_owned_null_aliases(owned, #{slot_count}, __rc_ret);"

        true ->
          nil
      end

    success_epilogue =
      [
        alias_or_null,
        Enum.join(cleanup ++ List.wrap(cow_drop), "\n"),
        if(slot_count > 0, do: "elmc_release_array_lifo(owned, #{slot_count});", else: nil)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")

    """
    {
      ElmcValue *__rc_ret = NULL;
      RC __alloc_rc = #{alloc_call};
      if (__alloc_rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(__alloc_rc, "#{sym}", "allocation failed");
        #{failure_cleanup}
        return NULL;
      }
      #{success_epilogue}
      return __rc_ret;
    }
    """
    |> String.trim()
  end

  @spec non_rc_result_alias_drop(Types.t() | map(), Types.slot_map(), keyword(), String.t()) ::
          String.t()

  defp non_rc_result_alias_drop(%{effects: %{result_aliases: aliases}}, slots, _opts, ret_var)
       when is_list(aliases) and aliases != [] and is_binary(ret_var) do
    alias_refs =
      aliases
      |> Enum.filter(&is_integer/1)
      |> Enum.map(fn reg ->
        case Map.get(slots, reg) do
          i when is_integer(i) -> "owned[#{i}]"
          _ -> nil
        end
      end)
      |> Enum.filter(&is_binary/1)

    RetainOperandAlias.emit(ret_var, alias_refs, drop_result_retain?: true)
  end

  defp non_rc_result_alias_drop(_, _, _, _), do: ""

  @spec wrap_non_rc_fn_out_return(String.t(), Types.t() | map(), Types.slot_map(), keyword()) :: String.t()

  defp wrap_non_rc_fn_out_return(call_expr, instr, slots, opts) do
    slot_count = Keyword.get(opts, :owned_slot_count, 0)
    cleanup = owned_consume_cleanup_lines(instr, slots, opts)
    cow_drop = non_rc_record_update_cow_drop(instr, slots, opts, "__ret")
    alias_drop = non_rc_result_alias_drop(instr, slots, opts, "__ret")

    alias_or_null =
      cond do
        alias_drop != "" -> alias_drop
        slot_count > 0 -> "elmc_owned_null_aliases(owned, #{slot_count}, __ret);"
        true -> ""
      end

    if slot_count > 0 or cleanup != [] or cow_drop != "" or alias_drop != "" do
      """
      {
        ElmcValue *__ret = #{call_expr};
        #{alias_or_null}
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

  @spec non_rc_record_update_cow_drop(map() | term(), Types.slot_map() | term(), keyword() | term(), String.t()) ::
          String.t()

  defp non_rc_record_update_cow_drop(%{op: :record_update, args: %{base: base_reg}}, slots, opts, ret_var)
       when is_integer(base_reg) and is_binary(ret_var) do
    case Map.get(slots, base_reg) do
      i when is_integer(i) ->
        "if (#{ret_var} == owned[#{i}]) { owned[#{i}] = NULL; }"

      _ ->
        base = slot_ref(base_reg, slots, opts)
        "if (#{ret_var} == #{base}) { #{ret_var} = elmc_retain(#{ret_var}); }"
    end
  end

  defp non_rc_record_update_cow_drop(_, _, _, _), do: ""

  @spec owned_consume_cleanup_lines(Types.t() | map(), Types.slot_map(), keyword()) :: [String.t()]

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
            # Borrow/retain-style consume: leave the pointer for epilogue LIFO.
            ""
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  @spec owned_transferring_consume_instr?(map() | term()) :: boolean()

  defp owned_transferring_consume_instr?(%{op: :call_runtime, args: %{builtin: id}}) do
    id in [:record_new, :record_new_take, :record_new_values_ints, :tuple2_take] or
      RuntimeBuiltins.ownership_transfer?(id)
  end

  defp owned_transferring_consume_instr?(_), do: false

  @spec assign_owned(boolean(), String.t(), String.t()) :: String.t()

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
  defp assign_owned(_rc?, dest, call_expr), do: "#{dest} = #{call_expr};"

  @spec assign_boxed_src_to_dest(String.t(), String.t(), boolean(), keyword()) :: String.t()
  defp assign_boxed_src_to_dest(dest, src_expr, rc?, opts) do
    {src, prep, cleanup} =
      if EphemeralBox.ephemeral?(src_expr) do
        materialize_ephemeral_src(src_expr, Keyword.put_new(opts, :rc_required, rc?))
      else
        {src_expr, [], []}
      end

    body =
      if rc? do
        retain_into_owned(dest, src)
      else
        "#{dest} = #{src};"
      end

    emit_with_ephemeral_cleanup(prep, body, cleanup)
  end

  @spec retain_into_owned(String.t(), String.t()) :: String.t()

  defp retain_into_owned(dest, src) do
    if owned_slot_dest?(dest), do: RecordCompile.clear_borrowed_owned_ref(dest)
    "#{dest} = elmc_retain(#{src});"
  end

  @spec emit_forward_ref_set(map(), Types.slot_map(), keyword()) :: String.t()

  defp emit_forward_ref_set(%{args: %{ref: ref, value: value_reg}}, slots, opts) do
    "elmc_forward_ref_set(#{ref}, #{boxed_value_ref(value_reg, slots, opts)});"
  end

  @spec emit_forward_ref_load(map(), Types.slot_map(), boolean(), String.t()) :: String.t()

  defp emit_forward_ref_load(%{args: %{ref: ref}}, _slots, rc?, dest) do
    # elmc_forward_ref_get only retains (or returns immortal zero); never allocates.
    assign_value_return(rc?, dest, "elmc_forward_ref_get(#{ref})")
  end

  @spec emit_forward_ref_capture(map(), Types.slot_map(), boolean(), String.t()) :: String.t()

  defp emit_forward_ref_capture(%{args: %{ref: ref}}, _slots, rc?, dest) do
    assign_owned(rc?, dest, "elmc_forward_ref_capture(#{ref})")
  end

  @spec emit_forward_ref_load_captured(map(), Types.slot_map(), boolean(), String.t()) :: String.t()

  defp emit_forward_ref_load_captured(%{args: args}, _slots, rc?, dest) do
    idx = Map.get(args || %{}, :capture_index, 0)

    assign_owned(
      rc?,
      dest,
      "elmc_forward_ref_get((capture_count > #{idx} && captures[#{idx}] && captures[#{idx}]->tag == ELMC_TAG_FORWARD_REF && captures[#{idx}]->payload) ? *((ElmcForwardRef **)captures[#{idx}]->payload) : NULL)"
    )
  end

  @spec format_call_args(String.t(), String.t() | [String.t()]) :: String.t()

  defp format_call_args(dest_arg, ""), do: dest_arg
  defp format_call_args(dest_arg, args), do: "#{dest_arg}, #{args}"

  @spec native_call_suffix(String.t()) :: String.t()

  defp native_call_suffix(""), do: ""
  defp native_call_suffix(args), do: ", #{args}"

  @spec rc_call(boolean(), String.t(), String.t(), String.t() | [String.t()]) :: String.t()

  defp rc_call(true, dest_ref, fn_name, args) do
    call_args = format_call_args(dest_arg(dest_ref, dest_ref), args)
    "Rc = #{fn_name}(#{call_args});\nCHECK_RC(Rc);"
  end

  defp rc_call(_false_arm, dest_ref, fn_name, args) do
    "#{dest_ref} = #{fn_name}(#{args});"
  end

  @spec rc_callee_from_value_return(String.t(), String.t(), String.t(), String.t(), keyword()) :: String.t()

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

  # Transfer ownership of a uniquely owned local into an owned[] dest. Clears any
  # stale borrow mark so epilogue LIFO will release the new value (list map heads).
  @spec owned_slot_take_assign(String.t(), String.t()) :: String.t()

  defp owned_slot_take_assign(dest, src)
       when is_binary(dest) and is_binary(src) do
    if owned_slot_dest?(dest), do: RecordCompile.clear_borrowed_owned_ref(dest)
    "#{dest} = #{src};"
  end

  @spec rc_call_tmp_var(String.t(), keyword()) :: String.t()

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

  @spec rc_callee_from_value_return_via_tmp(String.t(), String.t(), String.t(), String.t(), keyword()) :: String.t()

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

  @spec dest_arg(String.t(), term()) :: String.t()

  defp dest_arg("out", _), do: "out"
  defp dest_arg("*out", _), do: "out"
  defp dest_arg(dest_ref, _), do: "&#{dest_ref}"

  @spec cow_drop_alias_null(Types.reg() | Types.result_slot() | term(), Types.reg() | term(), boolean() | term(), Types.slot_map() | term(), keyword() | term()) :: String.t()

  defp cow_drop_alias_null(dest, base_reg, retain_copy?, slots, opts)
       when is_integer(base_reg) and is_boolean(retain_copy?) do
    dest_s = format_dest(dest, slots, opts)
    base_s = slot_ref(base_reg, slots, opts)

    cond do
      dest_s == "" or dest_s == base_s ->
        ""

      is_integer(Map.get(slots, base_reg)) ->
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

      true ->
        # Borrowed param / non-owned base: in-place cow_drop aliases `dest` to
        # `base` without a retain. Epilogue LIFO would then steal a retain and
        # free the caller's model while the result tuple still points at it.
        """
        if (#{dest_s} == #{base_s}) {
          #{dest_s} = elmc_retain(#{dest_s});
        }
        """
        |> String.trim()
    end
  end

  defp cow_drop_alias_null(_, _, _, _, _), do: ""

  @spec format_dest(Types.reg() | Types.result_slot() | integer(), Types.slot_map() | term(), keyword()) :: String.t()

  defp format_dest(:stream_void, _, _opts), do: ""
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

  @spec emit_make_closure(Types.t() | map(), Types.slot_map(), keyword(), boolean(), String.t()) :: String.t()

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
      dest_out = if(dest == "*out", do: "*out", else: dest)

      assign =
        RcRuntimeEmit.non_rc_allocator_stmt(
          dest_out,
          "elmc_closure_new",
          "#{closure_fn}, #{arity}, #{cap_count}, #{cap_arg}",
          return_on_fail?: dest == "*out"
        )

      """
      #{cap_array_code}
      #{assign}
      """
      |> String.trim()
    end
  end

  @spec emit_op_only(map() | term(), Types.slot_map(), keyword()) :: String.t()

  defp emit_op_only(%Types{op: :publish, dest: :fn_out, args: %{source: reg}}, slots, opts)
       when is_integer(reg) do
    if Keyword.get(opts, :native_scalar_out) in [:native_int, :native_bool, :native_int_pair] do
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

  @spec emit_load_param_copy(map(), Types.slot_map(), keyword()) :: String.t()

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
            rc_assign(rc?, dest, "elmc_new_bool", [c_arg])

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

  @spec publish_fn_out(Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp publish_fn_out(reg, slots, opts) do
    if MapSet.member?(
         Keyword.get(opts, :native_list_int_pair_pair_regs, MapSet.new()),
         reg
       ) do
      ""
    else
      publish_fn_out_body(reg, slots, opts)
    end
  end

  defp publish_fn_out_body(reg, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, false)
    src = slot_ref(reg, slots, opts)
    native_int? = MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg)
    native_bool? = MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), reg)

    cond do
      rc? ->
        publish_fn_out_rc(reg, slots, src, opts)

      native_int? ->
        publish_native_int_return(src, opts)

      native_bool? ->
        publish_native_bool_return(src, opts)

      true ->
        publish_fn_out_value(reg, slots, src, opts)
    end
  end

  @spec publish_fn_out_rc(Types.reg(), Types.slot_map(), String.t(), keyword()) :: String.t()

  defp publish_fn_out_rc(reg, slots, src, opts) do
    case Map.get(slots, reg) do
      i when is_integer(i) ->
        # Tuple/record peels mark the dest as borrowed. Publishing that pointer as
        # the function result must retain: the base tuple is released in the
        # epilogue (compose `foldl >> Tuple.first` otherwise use-after-frees to []).
        if RecordCompile.borrowed_owned_ref?(src) do
          RecordCompile.clear_borrowed_owned_ref(src)
          "*out = elmc_retain(#{src});\nowned[#{i}] = NULL;"
        else
          "*out = #{src};\nowned[#{i}] = NULL;"
        end

      nil ->
        # Direct borrow-param publish: *out is owned by the caller.
        if Map.has_key?(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
          "*out = elmc_retain(#{src});"
        else
          "*out = #{src};"
        end
    end
  end

  @spec publish_native_int_return(String.t(), keyword()) :: String.t()

  defp publish_native_int_return(src, opts) do
    EphemeralBox.non_rc_scalar_return("elmc_new_int", src, Keyword.get(opts, :owned_slot_count, 0))
  end

  @spec publish_native_bool_return(String.t(), keyword()) :: String.t()

  defp publish_native_bool_return(src, opts) do
    EphemeralBox.non_rc_scalar_return("elmc_new_bool", src, Keyword.get(opts, :owned_slot_count, 0))
  end

  @spec publish_fn_out_value(Types.reg(), Types.slot_map(), String.t(), keyword()) :: String.t()

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

  @spec slot_var(Types.reg(), Types.slot_map()) :: String.t()

  defp slot_var(reg, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "owned[#{i}]"
      _ -> "tmp_#{reg}"
    end
  end

  @spec slot_ref(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

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

                      # Skipped borrow load_param / alias: resolve to the C param or source
                      # reg instead of an undeclared `tmp_N`.
                      %{op: :load_param, args: %{index: index}} when is_integer(index) ->
                        FunctionCallAbi.param_c_arg(index, Keyword.get(opts, :params, []))

                      %{op: :load_local, args: %{source: src}} when is_integer(src) ->
                        slot_ref(src, slots, opts)

                      %{op: :transfer, args: %{source: src}} when is_integer(src) ->
                        slot_ref(src, slots, opts)

                      %{op: :call_runtime, args: %{builtin: :maybe_just_payload, args: [src]}}
                      when is_integer(src) ->
                        "elmc_maybe_or_tuple_just_payload_borrow(#{slot_ref(src, slots, opts)})"

                      %{
                        op: :call_runtime,
                        args: %{builtin: :retain, view_peel: :maybe_just_payload, view_peel_args: [src]}
                      }
                      when is_integer(src) ->
                        "elmc_maybe_or_tuple_just_payload_borrow(#{slot_ref(src, slots, opts)})"

                      %{op: :record_get, args: %{base: base, field: field} = rec_args}
                      when is_integer(base) ->
                        index = record_get_index_ref(field, Map.get(rec_args, :field_index, "0"))
                        "ELMC_RECORD_GET_INDEX(#{slot_ref(base, slots, opts)}, #{index})"

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

  @spec record_new_suffix(Types.reg() | Types.result_slot() | term(), term()) :: String.t()

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

  @spec record_values_array([Types.reg()], Types.slot_map(), keyword()) :: {[String.t()], String.t()}

  defp record_values_array(field_regs, slots, opts) do
    {entries, _prior_refs, prep} =
      Enum.reduce(field_regs, {[], [], []}, fn reg, {entries, prior_refs, prep} ->
        ref = record_field_value_ref(reg, slots, opts)
        {ref, {prep, _cleanup}} = EphemeralBox.materialize(ref, prep, [], opts, true)

        entry =
          cond do
            ref in prior_refs ->
              "elmc_retain(#{ref})"

            RecordCompile.borrowed_owned_ref?(ref) ->
              "elmc_retain(#{ref})"

            true ->
              ref
          end

        {entries ++ [entry], [ref | prior_refs], prep}
      end)

    {prep, Enum.join(entries, ", ")}
  end

  @spec record_field_value_ref(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

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

  @spec resolve_record_field_names([String.t()] | String.t() | nil, non_neg_integer(), String.t()) :: [String.t()] | nil

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

  @spec lookup_record_shape_type(String.t(), String.t()) :: [String.t()] | nil

  defp lookup_record_shape_type(type, module) when is_binary(type) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    short = type |> String.split(".") |> List.last()

    Map.get(shapes, {module, type}) ||
      Map.get(shapes, {module, short}) ||
      Enum.find_value(shapes, fn {{m, name}, fields} ->
        if m == module and name in [type, short], do: fields
      end)
  end

  @spec infer_record_shape_by_count(non_neg_integer() | integer(), String.t() | nil) :: [String.t()] | nil

  defp infer_record_shape_by_count(_count, nil), do: nil

  defp infer_record_shape_by_count(count, module) when is_integer(count) and is_binary(module) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case Enum.filter(shapes, fn {{m, _name}, fields} -> m == module and length(fields) == count end) do
      [{{_, _}, fields}] -> fields
      _ -> nil
    end
  end

  @spec record_get_index_ref(String.t(), String.t()) :: String.t()

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

    case parse_int_literal(base_s) do
      {:ok, 0} ->
        "0"

      _ ->
        "elmc_int_mod_by(#{base_s}, #{value_s})"
    end
  end

  @spec parse_int_literal(String.t()) :: {:ok, integer()} | :dynamic

  defp parse_int_literal(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> {:ok, n}
      _ -> :dynamic
    end
  end

  @spec native_int_repeat_count?(Types.reg(), keyword()) :: boolean()

  defp native_int_repeat_count?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :const_int_regs, %{}), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg)
  end

  @spec parenthesize_mod_value(String.t()) :: String.t()

  defp parenthesize_mod_value(value_s) when is_binary(value_s) do
    trimmed = String.trim(value_s)

    if trimmed != "" and not String.starts_with?(trimmed, "(") and
         String.match?(trimmed, ~r/[+\-*]/) do
      "(#{trimmed})"
    else
      trimmed
    end
  end

  @spec const_int_value(integer() | term()) :: integer() | nil

  defp const_int_value(value) when is_integer(value), do: value
  defp const_int_value({value, _ctor}) when is_integer(value), do: value
  defp const_int_value({value, _ctor, _bool_lit?}) when is_integer(value), do: value
  defp const_int_value(_), do: nil

  @spec const_int_c_ref(integer() | term(), keyword()) :: String.t()

  defp const_int_c_ref(value, opts)

  defp const_int_c_ref(value, _opts) when is_integer(value), do: Integer.to_string(value)

  defp const_int_c_ref({value, ctor}, opts) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, plan_module_from(opts))

  defp const_int_c_ref({value, ctor, _bool_lit?}, opts) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, plan_module_from(opts))

  defp const_int_bool_lit?({_value, _ctor, true}), do: true
  defp const_int_bool_lit?(_), do: false

  @spec plan_module_from(keyword()) :: String.t() | nil

  defp plan_module_from(opts) do
    Keyword.get(opts, :module) ||
      case Keyword.get(opts, :parent_plan) do
        %{module: mod} when is_binary(mod) -> mod
        _ -> nil
      end
  end

  @doc false
  @spec emit_list_int_pair_outs(term(), term(), Types.slot_map(), keyword()) :: String.t()
  def emit_list_int_pair_outs(list_reg, int_reg, slots, opts) do
    list_ref = slot_ref(list_reg, slots, opts)
    int_ref = int_operand_ref(int_reg, slots, opts)

    null_list =
      case list_reg do
        reg when is_integer(reg) ->
          case Map.get(slots, reg) do
            idx when is_integer(idx) -> "owned[#{idx}] = NULL;"
            _ -> ""
          end

        _ ->
          ""
      end

    """
    *out_list = #{list_ref};
    #{null_list}
    *out_int = #{int_ref};
    """
    |> String.trim()
  end

  defp list_int_pair_ret_dest?(dest_reg, opts) do
    dest_reg in [:fn_out, :branch_out] or
      MapSet.member?(
        Keyword.get(opts, :native_list_int_pair_pair_regs, MapSet.new()),
        dest_reg
      )
  end

  @spec native_int_pair_ret_dest?(String.t(), Types.reg() | term(), keyword()) :: boolean()
  defp native_int_pair_ret_dest?(_dest, _dest_reg, opts) do
    # Every `tuple2` in a dual-out `(Int, Int)` helper is a return arm (or is
    # overwritten by a later arm). Matching only `:fn_out` / `native_ret_reg`
    # misses phi/switch dests and collapses a 60-arm table to one pair.
    Keyword.get(opts, :native_scalar_out) == :native_int_pair
  end

  @spec emit_native_int_pair_outs([term()], Types.slot_map(), keyword()) :: String.t()
  defp emit_native_int_pair_outs(args, slots, opts) do
    left = int_operand_ref(Enum.at(args, 0), slots, opts)
    right = int_operand_ref(Enum.at(args, 1), slots, opts)
    "*out0 = #{left};\n*out1 = #{right};"
  end
end
