defmodule Elmc.Backend.C.Lower.Instr do
  @moduledoc false

  alias Elmc.Backend.C.Lower.Lambda
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
    elmc_record_new
    elmc_record_new_take
    elmc_record_new_values_take
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

  def emit(%Types{op: op} = instr, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    dest = format_dest(instr.dest, slots)

    case op do
      :const_int ->
        rc_assign(rc?, dest, "elmc_new_int", [Integer.to_string(instr.args.value)])

      :const_immortal_string ->
        escaped = Util.escape_c_string(instr.args.value)
        rc_assign(rc?, dest, "elmc_new_string", ["\"#{escaped}\""])

      :load_local ->
        src = slot_ref(instr.args.source, slots)
        "#{dest} = #{src};"

      :call_runtime ->
        emit_call_runtime(instr, slots, rc?, dest, opts)

      :call_fn ->
        emit_call_fn(instr, slots, rc?, dest, opts)

      :call_closure ->
        emit_call_closure(instr, slots, rc?, dest)

      :release ->
        emit_release(instr, slots)

      :record_get ->
        base = slot_ref(instr.args.base, slots)
        field = instr.args.field
        index = record_get_index_ref(field, Map.get(instr.args, :field_index, "0"))
        assign_value_return(rc?, dest, "elmc_record_get_index(#{base}, #{index})")

      :record_update ->
        base = slot_ref(instr.args.base, slots)
        value = slot_ref(instr.args.value, slots)
        index = Map.get(instr.args, :field_index, "0")

        assign =
          assign_value_return(
            rc?,
            dest,
            "elmc_record_update_index_cow_drop(#{base}, #{index}, #{value})"
          )

        alias_guard = cow_drop_alias_null(instr.dest, instr.args.base, slots)

        [assign, alias_guard]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      :compare ->
        left = slot_ref(instr.args.left, slots)
        right = slot_ref(instr.args.right, slots)
        cmp = compare_c_expr(instr.args.kind, left, right)
        rc_assign(rc?, dest, "elmc_new_bool", [cmp])

      :int_arith ->
        emit_int_arith(instr, slots, rc?, dest)

      :boxed_binop ->
        emit_boxed_binop(instr, slots, rc?, dest)

      :test_maybe_nothing ->
        subject = slot_ref(instr.args.reg, slots)
        rc_assign(rc?, dest, "elmc_new_int", ["elmc_maybe_is_nothing(#{subject}) ? 1 : 0"])

      :test_list_empty ->
        subject = slot_ref(instr.args.reg, slots)
        rc_assign(rc?, dest, "elmc_new_int", ["elmc_as_int(elmc_list_is_empty(#{subject}))"])

      :test_ctor_tag ->
        subject = slot_ref(instr.args.subject, slots)
        tag = instr.args.tag
        rc_assign(rc?, dest, "elmc_new_int", ["elmc_union_tag_matches(#{subject}, #{tag}) ? 1 : 0"])

      :bool_and ->
        left = slot_ref(instr.args.left, slots)
        right = slot_ref(instr.args.right, slots)
        rc_assign(rc?, dest, "elmc_new_int", ["(elmc_as_int(#{left}) && elmc_as_int(#{right})) ? 1 : 0"])

      :switch_ctor_tag ->
        emit_switch_ctor_tag(instr, slots, rc?, dest)

      :pebble_cmd ->
        emit_pebble_cmd(instr, slots, rc?, dest)

      :render_cmd ->
        emit_render_cmd(instr, slots, rc?, dest)

      :pebble_sub ->
        emit_pebble_sub(instr, slots, rc?, dest)

      :tuple_proj ->
        base = slot_ref(instr.args.base, slots)

        call =
          case instr.args.which do
            :first -> "elmc_tuple_first(#{base})"
            :second -> "elmc_tuple_second(#{base})"
          end

        assign_owned(rc?, dest, call)

      :make_closure ->
        emit_make_closure(instr, slots, opts, rc?, dest)

      :forward_ref_set ->
        emit_forward_ref_set(instr, slots)

      :forward_ref_load ->
        emit_forward_ref_load(instr, slots, rc?, dest)

      :forward_ref_capture ->
        emit_forward_ref_capture(instr, slots, rc?, dest)

      :forward_ref_load_captured ->
        emit_forward_ref_load_captured(instr, slots, rc?, dest)

      :maybe_is_nothing ->
        "elmc_maybe_is_nothing(#{slot_ref(instr.args.reg, slots)})"

      _ ->
        "/* plan op #{op} unlowered */"
    end
  end

  defp emit_phi(%{dest: dest, args: %{then: then_reg, else: else_reg, cond: cond_reg}}, slots, opts) do
    rc? = Keyword.get(opts, :rc_required, true)
    merge = slot_var(dest, slots)
    then_s = slot_ref(then_reg, slots)
    else_s = slot_ref(else_reg, slots)
    cond_s = slot_ref(cond_reg, slots)

    if rc? do
      """
      if (elmc_as_int(#{cond_s}) != 0) {
        #{retain_into_owned(merge, then_s)}
      } else {
        #{retain_into_owned(merge, else_s)}
      }
      """
      |> String.trim()
    else
      """
      if (elmc_as_int(#{cond_s}) != 0) {
        #{merge} = #{then_s};
      } else {
        #{merge} = #{else_s};
      }
      """
      |> String.trim()
    end
  end

  defp compare_c_expr(:eq, left, right), do: "(elmc_as_int(#{left}) == elmc_as_int(#{right})) ? 1 : 0"
  defp compare_c_expr(:neq, left, right), do: "(elmc_as_int(#{left}) != elmc_as_int(#{right})) ? 1 : 0"
  defp compare_c_expr(:gt, left, right), do: "(elmc_as_int(#{left}) > elmc_as_int(#{right})) ? 1 : 0"
  defp compare_c_expr(:gte, left, right), do: "(elmc_as_int(#{left}) >= elmc_as_int(#{right})) ? 1 : 0"
  defp compare_c_expr(:lt, left, right), do: "(elmc_as_int(#{left}) < elmc_as_int(#{right})) ? 1 : 0"
  defp compare_c_expr(:lte, left, right), do: "(elmc_as_int(#{left}) <= elmc_as_int(#{right})) ? 1 : 0"
  defp compare_c_expr(_, left, right), do: "(elmc_as_int(#{left}) == elmc_as_int(#{right})) ? 1 : 0"

  defp emit_switch_ctor_tag(%{args: args}, slots, rc?, merge) do
    subject = slot_ref(args.subject, slots)

    arm_lines =
      Enum.map(args.arms, fn %{tag: tag, reg: reg} ->
        src = slot_ref(reg, slots)
        cond_line = "if (elmc_union_tag_matches(#{subject}, #{tag}))"

        if rc? do
          """
          #{cond_line} {
            #{retain_into_owned(merge, src)}
          }
          """
        else
          "#{cond_line} { #{merge} = #{src}; }\n"
        end
      end)

    default_line =
      case Map.get(args, :default) do
        reg when is_integer(reg) ->
          src = slot_ref(reg, slots)

          if rc? do
            """
            else {
              #{retain_into_owned(merge, src)}
            }
            """
          else
            "else { #{merge} = #{src}; }\n"
          end

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

  defp emit_int_arith(%{args: %{kind: :add_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest) do
    lhs_s = slot_ref(lhs, slots)
    rhs_s = slot_ref(rhs, slots)
    rc_assign(rc?, dest, "elmc_new_int", ["elmc_as_int(#{lhs_s}) + elmc_as_int(#{rhs_s})"])
  end

  defp emit_int_arith(%{args: %{kind: :mul_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest) do
    lhs_s = slot_ref(lhs, slots)
    rhs_s = slot_ref(rhs, slots)
    rc_assign(rc?, dest, "elmc_new_int", ["elmc_as_int(#{lhs_s}) * elmc_as_int(#{rhs_s})"])
  end

  defp emit_int_arith(%{args: %{kind: :sub_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest) do
    lhs_s = slot_ref(lhs, slots)
    rhs_s = slot_ref(rhs, slots)
    rc_assign(rc?, dest, "elmc_new_int", ["elmc_as_int(#{lhs_s}) - elmc_as_int(#{rhs_s})"])
  end

  defp emit_int_arith(%{args: %{kind: :idiv_vars, lhs: lhs, rhs: rhs}}, slots, rc?, dest) do
    lhs_s = slot_ref(lhs, slots)
    rhs_s = slot_ref(rhs, slots)
    rc_assign(rc?, dest, "elmc_new_int", ["(elmc_as_int(#{rhs_s}) == 0 ? 0 : elmc_as_int(#{lhs_s}) / elmc_as_int(#{rhs_s}))"])
  end

  defp emit_int_arith(%{args: %{kind: :add_const, lhs: lhs, value: value}}, slots, rc?, dest) do
    lhs_s = slot_ref(lhs, slots)
    rc_assign(rc?, dest, "elmc_new_int", ["elmc_as_int(#{lhs_s}) + #{value}"])
  end

  defp emit_int_arith(%{args: %{kind: :sub_const, lhs: lhs, value: value}}, slots, rc?, dest) do
    lhs_s = slot_ref(lhs, slots)
    rc_assign(rc?, dest, "elmc_new_int", ["elmc_as_int(#{lhs_s}) - #{value}"])
  end

  defp emit_int_arith(_, _slots, _rc?, _dest), do: "/* int_arith unlowered */"

  defp emit_boxed_binop(%{args: %{op: op, lhs: lhs, rhs: rhs}}, slots, rc?, dest) do
    op_sym =
      case op do
        :add -> "+"
        :sub -> "-"
        :mul -> "*"
        :idiv -> "/"
        :fdiv -> "/"
        other -> raise ArgumentError, "unknown boxed_binop #{inspect(other)}"
      end

    left = slot_ref(lhs, slots)
    right = slot_ref(rhs, slots)

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

  defp float_literal_c(value) when is_integer(value), do: "#{value}.0"
  defp float_literal_c(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])

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
    values_array = record_values_array(args, slots)
    values_decl = "ElmcValue *rec_values_#{suffix}[#{max(count, 1)}] = { #{values_array} };"

    {names_decl, sym, call_args} =
      if is_list(field_names) and field_names != [] do
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

  defp emit_call_runtime(%{args: %{builtin: :string_from_int, args: [arg]}}, slots, rc?, dest, _opts) do
    sym = RuntimeBuiltins.c_symbol(:string_from_int)
    native = "elmc_as_int(#{slot_ref(arg, slots)})"
    rc_assign(rc?, dest, sym, [native])
  end

  defp emit_call_runtime(%{args: %{builtin: :tuple2, args: args}}, slots, rc?, dest, _opts) do
    c_args = Enum.map(args, &slot_ref(&1, slots))

    if rc? do
      rc_assign(true, dest, "elmc_tuple2", c_args)
    else
      assign_owned(false, dest, "elmc_tuple2_take_value(#{Enum.join(c_args, ", ")})")
    end
  end

  defp emit_call_runtime(%{args: %{builtin: :tuple2_take, args: args}}, slots, rc?, dest, _opts) do
    c_args = Enum.map(args, &slot_ref(&1, slots))

    if rc? do
      rc_assign(true, dest, "elmc_tuple2_take", c_args)
    else
      assign_owned(false, dest, "elmc_tuple2_take_value(#{Enum.join(c_args, ", ")})")
    end
  end

  defp emit_call_runtime(%{args: %{builtin: id, args: args}}, slots, rc?, dest, _opts) do
    sym = RuntimeBuiltins.c_symbol(id) || "elmc_unknown"

    c_args =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        ref = slot_ref(arg, slots)

        if RuntimeBuiltins.native_int_arg?(id, index) do
          "elmc_as_int(#{ref})"
        else
          ref
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

  defp emit_call_closure(%{args: %{callee: callee, args: args}}, slots, true, dest) do
    callee_s = slot_ref(callee, slots)
    c_args = Enum.map(args, &slot_ref(&1, slots))
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

  defp emit_call_closure(%{args: %{callee: callee, args: args}}, slots, false, dest) do
    callee_s = slot_ref(callee, slots)
    c_args = Enum.map(args, &slot_ref(&1, slots))
    argc = length(c_args)
    args_var = "plan_closure_argv_#{System.unique_integer([:positive])}"

    """
    ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{Enum.join(c_args, ", ")} };
    #{dest} = elmc_closure_call(#{callee_s}, #{args_var}, #{argc});
    """
    |> String.trim()
  end

  defp emit_call_fn(%{args: %{module: mod, name: name, args: args}}, slots, rc?, dest, _opts) do
    c_name = Util.module_fn_name(mod, name)
    dest_ref = if dest == "*out", do: "out", else: dest
    decl_map = Process.get(:elmc_program_decls, %{})
    decl = Map.get(decl_map, {mod, name})

    {prefix, call_arg_s} =
      cond do
        decl && FunctionCallAbi.argv_abi?(decl, mod, decl_map) ->
          c_args = Enum.map(args, &slot_ref(&1, slots))
          {setup, args_var, argc} = FunctionCallAbi.emit_argv_setup("plan", c_args)
          {setup <> "\n", "#{args_var}, #{argc}"}

        decl && FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map) &&
            FunctionEmit.mixed_direct_abi?(decl, mod, decl_map) ->
          kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)

          c_args =
            args
            |> Enum.zip(kinds)
            |> Enum.map(fn {arg_reg, kind} ->
              direct_call_arg(slot_ref(arg_reg, slots), kind)
            end)

          {"", Enum.join(c_args, ", ")}

        true ->
          c_args = Enum.map(args, &slot_ref(&1, slots))
          {"", Enum.join(c_args, ", ")}
      end

    prefix <>
      emit_fn_call(rc?, dest, dest_ref, c_name, call_arg_s, {mod, name})
  end

  defp emit_fn_call(true, dest, _dest_ref, c_name, call_arg_s, {mod, name}) do
    if RcRequired.rc_required?(mod, name) do
      rc_call(true, if(dest == "*out", do: "out", else: dest), c_name, call_arg_s)
    else
      "#{dest} = #{c_name}(#{call_arg_s});"
    end
  end

  defp emit_fn_call(false, dest, dest_ref, c_name, call_arg_s, {mod, name}) do
    if RcRequired.rc_required?(mod, name) do
      rc_callee_from_value_return(dest, dest_ref, c_name, call_arg_s)
    else
      "#{dest} = #{c_name}(#{call_arg_s});"
    end
  end

  defp direct_call_arg(ref, :native_int), do: "elmc_as_int(#{ref})"
  defp direct_call_arg(ref, :native_bool), do: "elmc_as_bool(#{ref})"
  defp direct_call_arg(ref, _), do: ref

  defp emit_pebble_cmd(%{args: %{builtin: id, kind: kind, params: params}}, slots, rc?, dest) do
    sym = RuntimeBuiltins.c_symbol(id) || "elmc_cmd0"
    kind_s = Map.get(kind, :c_expr, "0")
    args = Enum.join([kind_s | native_int_param_refs(params, slots)], ", ")
    rc_call(rc?, if(dest == "*out", do: "out", else: dest), sym, args)
  end

  defp emit_render_cmd(%{args: %{kind: kind, params: params}}, slots, rc?, dest) do
    kind_s = platform_kind_c(kind)
    args = Enum.join([kind_s | padded_param_refs(params, 6, slots)], ", ")

    if rc? do
      dest_ref = if dest == "*out", do: "(*out)", else: dest

      """
      #{dest} = elmc_render_cmd6(#{args});
      if (!#{dest_ref}) {
        Rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(Rc);
      }
      """
      |> String.trim()
    else
      "#{dest} = elmc_render_cmd6(#{args});"
    end
  end

  defp emit_pebble_sub(%{args: %{kind: mask, params: params}}, slots, rc?, dest) do
    mask_s = platform_kind_c(mask)
    arity = length(params)
    fn_name = "elmc_sub#{arity}"
    args = Enum.join([mask_s | native_int_param_refs(params, slots)], ", ")
    rc_call(rc?, if(dest == "*out", do: "out", else: dest), fn_name, args)
  end

  defp platform_kind_c(%{c_expr: value}) when is_binary(value), do: value
  defp platform_kind_c(%{literal: value}) when is_integer(value), do: Integer.to_string(value)
  defp platform_kind_c(_), do: "0"

  defp padded_param_refs(params, n, slots) do
    refs = native_int_param_refs(params, slots)
    refs ++ List.duplicate("0", max(0, n - length(refs)))
  end

  defp native_int_param_refs(params, slots) do
    Enum.map(params, fn reg -> "elmc_as_int(#{slot_ref(reg, slots)})" end)
  end

  defp non_rc_value_return_symbol("elmc_tuple2_take"), do: "elmc_tuple2_take_value"
  defp non_rc_value_return_symbol(sym), do: sym

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

  defp assign_owned(false, dest, call_expr), do: "#{dest} = #{call_expr};"

  defp retain_into_owned(dest, src), do: "#{dest} = elmc_retain(#{src});"

  defp emit_forward_ref_set(%{args: %{ref: ref, value: value_reg}}, slots) do
    "elmc_forward_ref_set(#{ref}, #{slot_ref(value_reg, slots)});"
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

  defp cow_drop_alias_null(dest, base_reg, slots) when is_integer(base_reg) do
    dest_s = format_dest(dest, slots)
    base_s = slot_ref(base_reg, slots)

    if dest_s != base_s do
      "if (#{dest_s} == #{base_s}) { #{base_s} = NULL; }"
    else
      ""
    end
  end

  defp cow_drop_alias_null(_, _, _), do: ""

  defp format_dest(nil, _), do: "_"
  defp format_dest(:fn_out, _), do: "*out"
  defp format_dest(:branch_out, _), do: "*out"
  defp format_dest(reg, slots) when is_integer(reg), do: slot_var(reg, slots)

  defp emit_make_closure(instr, slots, opts, rc?, dest) do
    idx = Map.get(instr.args, :index, 0)
    arity = Map.get(instr.args, :arity, 0)
    captures = Map.get(instr.args, :captures, [])
    parent = Keyword.fetch!(opts, :parent_plan)
    closure_fn = Lambda.closure_fn_name(parent, idx)
    cap_refs = Enum.map(captures, &slot_ref(&1, slots))
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

  defp emit_op_only(%Types{op: :publish, dest: :fn_out, args: %{source: reg}}, slots, _opts)
       when is_integer(reg) do
    idx = Map.get(slots, reg, reg)
    src = slot_ref(reg, slots)
    "*out = #{src};\nowned[#{idx}] = NULL;"
  end

  defp emit_op_only(%Types{op: :load_param, dest: dest_reg, args: %{index: index}}, slots, opts) do
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

  defp emit_op_only(%Types{op: :publish, dest: :fn_out}, _slots, _opts), do: ""
  defp emit_op_only(%Types{op: :catch_begin}, _slots, _opts), do: "CATCH_BEGIN"
  defp emit_op_only(%Types{op: :catch_end}, _slots, _opts), do: "CATCH_END;"
  defp emit_op_only(_, _slots, _opts), do: ""

  defp slot_var(reg, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "owned[#{i}]"
      _ -> "tmp_#{reg}"
    end
  end

  defp slot_ref(reg, slots) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "owned[#{i}]"
      nil -> "arg#{reg}"
      _ -> "tmp_#{reg}"
    end
  end

  defp slot_ref(:fn_out, _slots), do: "*out"
  defp slot_ref(:branch_out, _slots), do: "*out"

  defp record_new_suffix(dest_reg) when is_integer(dest_reg), do: Integer.to_string(dest_reg)
  defp record_new_suffix(:fn_out), do: "out"
  defp record_new_suffix(_), do: "0"

  defp record_values_array(field_regs, slots) do
    field_regs
    |> Enum.with_index()
    |> Enum.map_join(", ", fn {reg, idx} ->
      ref = slot_ref(reg, slots)
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
end
