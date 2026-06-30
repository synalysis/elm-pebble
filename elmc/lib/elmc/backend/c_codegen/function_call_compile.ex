defmodule Elmc.Backend.CCodegen.FunctionCallCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinOperators
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LayoutCoerceEmit
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.OwnershipCompile
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @type closure_signature ::
          {:top_level_ref, String.t(), String.t(), non_neg_integer()}
          | {:partial_ref, String.t(), String.t(), non_neg_integer(), non_neg_integer()}
          | {:partial_union, String.t(), integer(), non_neg_integer(), non_neg_integer()}

  @spec partial_union_constructor(
          String.t(),
          integer(),
          [Types.ir_expr()],
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def partial_union_constructor(target, tag, bound_args, full_arity, env, counter) do
    env = RcRuntimeEmit.strip_function_tail_scope(env)
    bound_count = length(bound_args)
    remaining = max(full_arity - bound_count, 0)

    {tag_code, tag_var, counter} =
      Host.compile_expr(%{op: :int_literal, value: tag}, env, counter)

    {args_code, bound_vars, counter} =
      Enum.reduce(bound_args, {tag_code, [tag_var], counter}, fn arg_expr,
                                                                {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    {out, next} = CaseCompile.fresh_var(counter, env)

    signature = {:partial_union, target, tag, full_arity, bound_count}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_partial_union")

    if new? do
      merge_lines =
        if bound_count > 0 do
          Enum.map_join(0..(bound_count - 1), "\n    ", fn index ->
            "all_args[#{index}] = captures[#{index + 1}];"
          end)
        else
          ""
        end

      arg_lines =
        if remaining > 0 do
          Enum.map_join(0..(remaining - 1), "\n    ", fn index ->
            "all_args[#{bound_count + index}] = (argc > #{index}) ? args[#{index}] : NULL;"
          end)
        else
          ""
        end

      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)capture_count;
        ElmcValue *result = NULL;
        RC Rc = RC_SUCCESS;
        CATCH_BEGIN
          ElmcValue *all_args[#{max(full_arity, 1)}] = {0};
          #{merge_lines}
          #{arg_lines}
          ElmcValue *payload = elmc_build_constructor_payload(all_args, #{full_arity});
          ElmcValue *tag = captures[0] ? elmc_retain(captures[0]) : elmc_int_zero();
          Rc = elmc_tuple2_take(&result, tag, payload);
          CHECK_RC(Rc);
        CATCH_END
        return result;
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    capture_list =
      case bound_vars do
        [] -> "NULL"
        vars -> Enum.join(vars, ", ")
      end

    code = """
    #{args_code}
    ElmcValue *cap_#{next}[#{max(bound_count + 1, 1)}] = { #{capture_list} };
      #{boxed_out_decl(env, out, "elmc_closure_new(#{closure_fn_name}, #{remaining}, #{bound_count + 1}, cap_#{next})")}
    """

    {code, out, next}
  end

  @spec value_source(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.value_source_result()
  def value_source(env, name, counter) do
    cond do
      is_binary(EnvBindings.native_int_binding(env, name)) ->
        {"", EnvBindings.native_int_binding(env, name), counter}

      is_binary(EnvBindings.native_bool_binding(env, name)) ->
        {"", EnvBindings.native_bool_binding(env, name), counter}

      is_binary(EnvBindings.native_float_binding(env, name)) ->
        {"", EnvBindings.native_float_binding(env, name), counter}

      true ->
        case Map.fetch(env, name) do
          {:ok, {:native_record, fields}} when is_map(fields) ->
            compile_native_record_box("tmp_src", name, fields, env, counter)
            |> then(fn {code, var, next} -> {code, var, next} end)

          {:ok, {:direct_fragment, fragment}} ->
            {code, var, next} = Host.compile_expr(fragment, env, counter)
            {code, var, next}

          {:ok, source} when is_binary(source) ->
            {"", source, counter}

          :error ->
            module_name = Map.get(env, :__module__, "Main")
            arity = EnvBindings.function_arity(env, module_name, name, [])

            if arity > 0 do
              {closure_code, tmp, next} = top_level_closure(module_name, name, arity, env, counter)
              {closure_code, tmp, next}
            else
              {var, next} = CaseCompile.fresh_var(counter, env)
              c_name = Util.module_fn_name(module_name, name)
              if caller_rc?(env), do: ValueSlots.track(var)

              code = zero_arg_call_code(env, module_name, name, c_name, var)
              {code <> "\n", var, next}
            end
        end
    end
  end

  @spec compile_call_operand(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter(),
          keyword()
        ) :: Types.compile_result()
  def compile_call_operand(expr, env, counter, opts \\ []) do
    {code, var, next, _passthrough?} = compile_call_operand_inner(expr, env, counter, opts)
    {code, var, next}
  end

  @spec compile_call_operand_inner(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter(),
          keyword()
        ) :: Types.compile_operand_inner_result()
  def compile_call_operand_inner(%{op: :var, name: name}, env, counter, opts) do
    borrow_args? = Keyword.get(opts, :borrow_args?, false)

    case Map.get(env, name) do
      source when is_binary(source) ->
        c_ref = RcRuntimeEmit.value_expr(source)

        if borrow_args? or EnvBindings.borrowed_arg_ref?(env, source) do
          {"", c_ref, counter, true}
        else
          {code, var, next} = Host.compile_expr(%{op: :var, name: name}, env, counter)
          {code, var, next, false}
        end

      _ ->
        {code, var, next} = Host.compile_expr(%{op: :var, name: name}, env, counter)
        {code, var, next, false}
    end
  end

  def compile_call_operand_inner(%{op: :field_access} = expr, env, counter, opts) do
    if Keyword.get(opts, :borrow_args?, false) do
      case Host.record_get_borrow_expr(expr, env) do
        ref when is_binary(ref) ->
          {"", ref, counter, true}

        nil ->
          {code, var, next} = Host.compile_expr(expr, env, counter)
          {code, var, next, false}
      end
    else
      {code, var, next} = Host.compile_expr(expr, env, counter)
      {code, var, next, false}
    end
  end

  def compile_call_operand_inner(expr, env, counter, _opts) do
    {code, var, next} = Host.compile_expr(expr, env, counter)
    {code, var, next, false}
  end

  @spec compile_retaining_call_operand(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_operand_inner_result()
  def compile_retaining_call_operand(%{op: :var, name: name}, env, counter) do
    case Map.get(env, name) do
      source when is_binary(source) ->
        {"", source, counter, true}

      _ ->
        {code, var, c} = Host.compile_expr(%{op: :var, name: name}, env, counter)
        {code, var, c, false}
    end
  end

  def compile_retaining_call_operand(expr, env, counter) do
    {code, var, c} = Host.compile_expr(expr, env, counter)
    {code, var, c, false}
  end

  @spec compile(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def compile(module_name, name, args, env, counter) do
    case port_call_expr(module_name, name, args, env) do
      {:ok, expr} ->
        Host.compile_expr(expr, env, counter)

      :error ->
        arity = EnvBindings.function_arity(env, module_name, name, args)
        c_name = Util.module_fn_name(module_name, name)

        case ConstantInt.compile_boxed_call(module_name, name, args, env, counter) do
          {:ok, code, out, c} ->
            {code, out, c}

          :error ->
            compile_function_call(module_name, name, args, env, counter, arity, c_name)
        end
    end
  end

  defp port_call_expr(module_name, name, args, env) do
    with true <- port_signature?(env, module_name, name),
         {:ok, expr} <- port_call_ir(module_name, name, args) do
      {:ok, expr}
    else
      _ -> :error
    end
  end

  defp port_signature?(env, module_name, name) do
    case Map.get(Map.get(env, :__program_decls__, %{}), {module_name, name}) do
      decl when is_map(decl) -> Map.get(decl, :expr) == nil
      _ -> false
    end
  end

  defp port_call_ir(module_name, "outgoing", [payload]) do
    {:ok,
     %{
       op: :runtime_call,
       function: "elmc_port_outgoing",
       args: [
         %{op: :string_literal, value: "#{module_name}.outgoing"},
         payload
       ]
     }}
  end

  defp port_call_ir(module_name, "incoming", [callback]) do
    {:ok,
     %{
       op: :runtime_call,
       function: "elmc_port_incoming_sub",
       args: [
         %{op: :string_literal, value: "#{module_name}.incoming"},
         callback
       ]
     }}
  end

  defp port_call_ir(_module_name, _name, _args), do: :error

  defp compile_function_call(module_name, name, args, env, counter, arity, c_name) do
    if length(args) == arity and NativeFunctionCall.call?({module_name, name}, env) do
      NativeFunctionCall.compile(module_name, name, args, env, counter)
    else
      compile_boxed(module_name, name, args, env, counter, arity, c_name)
    end
  end

  @spec compile_closure(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def compile_closure(closure_var, args, env, counter) do
    {arg_code, arg_vars, arg_passthrough, counter} =
      Enum.reduce(args, {"", [], [], counter}, fn arg_expr,
                                                  {code_acc, vars_acc, passthrough_acc, c} ->
        {code, var, c2, passthrough?} =
          compile_call_operand_inner(arg_expr, env, c, borrow_args?: true)

        {code_acc <> "\n  " <> code, vars_acc ++ [var], passthrough_acc ++ [passthrough?], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    argc = length(arg_vars)
    args_array = "call_args_#{next}"
    arg_list = call_arg_list(arg_vars)

    releases = release_borrowed_call_operands(env, arg_vars, arg_passthrough)

    code = """
    #{arg_code}
      ElmcValue *#{args_array}[#{max(argc, 1)}] = { #{arg_list} };
      ElmcValue *#{out} = elmc_closure_call(#{closure_var}, #{args_array}, #{argc});
      #{releases}
    """

    {code, out, next}
  end

  @spec compile_var(String.t(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile_var(name, env, counter) do
    case EnvBindings.native_string_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {var, next} = CaseCompile.fresh_var(counter, env)

        {RcRuntimeEmit.assign_call(env, var, "elmc_new_string", native_ref) <> "\n", var,
         next}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            if Map.get(env, :__transfer_operand__, false) and ValueSlots.owned_ref?(source) and
                 not ValueSlots.transferred?(source) do
              {"", source, counter}
            else
              {var, next} = CaseCompile.fresh_var(counter, env)
              compile_var_native_or_boxed(name, env, counter, var, next)
            end

          _ ->
            {var, next} = CaseCompile.fresh_var(counter, env)
            compile_var_native_or_boxed(name, env, counter, var, next)
        end
    end
  end

  defp compile_var_native_or_boxed(name, env, _counter, var, next) do
    case {EnvBindings.native_int_binding(env, name), EnvBindings.native_bool_binding(env, name),
          EnvBindings.native_float_binding(env, name)} do
      {native_ref, _, _} when is_binary(native_ref) ->
        {RcRuntimeEmit.assign_call(env, var, "elmc_new_int", native_ref) <> "\n", var, next}

      {_, native_ref, _} when is_binary(native_ref) ->
        {RcRuntimeEmit.assign_call(env, var, "elmc_new_bool", native_ref) <> "\n", var, next}

      {_, _, native_ref} when is_binary(native_ref) ->
        {RcRuntimeEmit.assign_call(env, var, "elmc_new_float", "(double)#{native_ref}") <> "\n", var, next}

      {nil, nil, nil} ->
        case Map.fetch(env, name) do
          {:ok, {:native_record, fields}} when is_map(fields) ->
            compile_native_record_box(var, name, fields, env, next)

          {:ok, {:forward_ref, ref}} when is_binary(ref) ->
            {"ElmcValue *#{var} = elmc_forward_ref_get(#{ref});", var, next}

          {:ok, {:forward_ref_slot, slot}} when is_binary(slot) ->
            {"ElmcValue *#{var} = elmc_forward_ref_get(#{slot});", var, next}

          {:ok, {:direct_fragment, fragment}} ->
            {frag_code, frag_var, next2} = Host.compile_expr(fragment, env, next)
            retain_next = next2 + 1
            retain_var = "tmp_#{retain_next}"

            {"#{frag_code}  ElmcValue *#{retain_var} = elmc_retain(#{frag_var});\n  #{ValueSlots.release_stmt(frag_var)}",
             retain_var, retain_next}

          {:ok, source} when is_binary(source) ->
            c_source = RcRuntimeEmit.value_expr(source)

            case OwnershipCompile.retain_owned_expr(env, name, source) do
              {:list_copy, src} ->
                copy_code = RcRuntimeEmit.fusion_assign(var, "elmc_list_copy", src, env)
                {copy_code, var, next}

              retain_expr ->
                expr =
                  if is_binary(retain_expr) do
                    retain_expr
                  else
                    cond do
                      ValueSlots.owned_ref?(source) ->
                        "elmc_retain(#{c_source})"

                      EnvBindings.boxed_int_binding?(env, name) or
                          EnvBindings.boxed_string_binding?(env, name) or
                          EnvBindings.direct_param_ref?(env, source) ->
                        "elmc_retain(#{c_source})"

                      true ->
                        "#{c_source} ? elmc_retain(#{c_source}) : elmc_int_zero()"
                    end
                  end

                {ValueSlots.boxed_decl(var, expr), var, next}
            end

          :error ->
            case BuiltinOperators.call(name, [], env, next) do
              nil ->
                module_name = Map.get(env, :__module__, "Main")
                arity = EnvBindings.function_arity(env, module_name, name, [])

                if arity > 0 do
                  top_level_closure(module_name, name, arity, env, next)
                else
                  compile_zero_arg_constant(module_name, name, env, next, var, next)
                end

              result ->
                result
            end
        end
    end
  end

  @spec compile_zero_arg_constant(
          String.t(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter(),
          String.t(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_zero_arg_constant(module_name, name, env, counter, var, next) do
    case ConstantInt.compile_boxed_call(module_name, name, [], env, counter) do
      {:ok, code, out, c} ->
        {code, out, c}

      :error ->
        c_name = Util.module_fn_name(module_name, name)
        if caller_rc?(env), do: ValueSlots.track(var)

        {zero_arg_call_code(env, module_name, name, c_name, var) <> "\n", var, next}
    end
  end

  @spec top_level_closure(
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def top_level_closure(module_name, name, arity, env, counter) do
    env = closure_env(env)
    {out, next} = CaseCompile.fresh_var(counter, env)
    c_name = Util.module_fn_name(module_name, name)
    signature = {:top_level_ref, module_name, name, arity}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_top_level_ref")

    if new? do
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)captures;
        (void)capture_count;
        #{rc_closure_return_body(module_name, name, c_name, "args, argc", env)}
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    code = """
    ElmcValue *cap_#{next}[1] = { NULL };
      #{boxed_out_decl(env, out, "elmc_closure_new(#{closure_fn_name}, #{arity}, 0, cap_#{next})")}
    """

    {code, out, next}
  end

  defp partial_closure(module_name, name, arity, arg_vars, env, counter, out) when is_binary(out) do
    env = closure_env(env)
    {cap_index, next} = CaseCompile.fresh_tmp_var(counter, env)
    c_name = Util.module_fn_name(module_name, name)
    bound_count = length(arg_vars)
    remaining = max(arity - bound_count, 0)
    signature = {:partial_ref, module_name, name, arity, bound_count}
    {closure_fn_name, new?} = closure_function_name(signature, "elmc_partial_ref")

    call_bindings =
      0..(arity - 1)
      |> Enum.map_join("\n  ", fn index ->
        cond do
          index < bound_count ->
            "call_args[#{index}] = (capture_count > #{index}) ? captures[#{index}] : NULL;"

          true ->
            rest_index = index - bound_count
            "call_args[#{index}] = (argc > #{rest_index}) ? args[#{rest_index}] : NULL;"
        end
      end)

    if new? do
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)args;
        (void)argc;
        (void)captures;
        (void)capture_count;
        ElmcValue *call_args[#{max(arity, 1)}] = {0};
        #{call_bindings}
        #{partial_rc_closure_return_body(module_name, name, c_name, arity, env)}
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])
    end

    capture_list =
      case arg_vars do
        [] -> "NULL"
        vars -> Enum.join(vars, ", ")
      end

    code = """
    ElmcValue *cap_#{cap_index}[#{max(bound_count, 1)}] = { #{capture_list} };
      #{boxed_out_decl(env, out, "elmc_closure_new(#{closure_fn_name}, #{remaining}, #{bound_count}, cap_#{cap_index})")}
    """

    {code, out, next}
  end

  @spec compile_native_record_box(
          String.t(),
          String.t(),
          %{String.t() => String.t()},
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  @spec capture_native_record(Types.compile_env(), String.t(), %{String.t() => String.t()}) ::
          String.t()
  def capture_native_record(env, name, fields) when is_map(fields) do
    field_names = native_record_field_names(env, name, fields)
    env = ensure_native_record_var_type(env, name, field_names)

    if native_record_all_int_fields?(env, name, field_names) do
      count = length(field_names)

      call_args =
        field_names
        |> Enum.map_join(", ", fn field -> Map.fetch!(fields, field) end)

      if Process.get(:elmc_generic_helper_defs) != nil do
        helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
        Process.put(:elmc_generic_helper_counter, helper_id)

        helper_name =
          "elmc_native_record_capture_#{Util.safe_c_suffix(Map.get(env, :__module__, "Main"))}_#{Util.safe_c_suffix(name)}_#{helper_id}"

        params =
          field_names
          |> Enum.with_index()
          |> Enum.map(fn {_field, index} -> "field_#{index}" end)

        param_decls = Enum.map_join(params, ", ", &"elmc_int_t #{&1}")
        values_array = Enum.join(params, ", ")

        helper_def = """
        static RC #{helper_name}(ElmcValue **out, #{param_decls}) {
          elmc_int_t rec_values[#{count}] = { #{values_array} };
          RC Rc = RC_SUCCESS;
          CATCH_BEGIN
            Rc = elmc_record_new_values_ints(out, #{count}, rec_values);
            CHECK_RC(Rc);
          CATCH_END
          return Rc;
        }
        """

        Process.put(
          :elmc_generic_helper_defs,
          [helper_def | Process.get(:elmc_generic_helper_defs, [])]
        )

        "#{helper_name}(#{call_args})"
      else
        "elmc_record_new_values_ints(#{count}, (elmc_int_t[]){ #{call_args} })"
      end
    else
      raise ArgumentError,
            "cannot capture native record #{inspect(name)} with non-Int fields in a closure; pass fields individually"
    end
  end

  defp compile_native_record_box(var, name, fields, env, next) when is_map(fields) do
    field_names = native_record_field_names(env, name, fields)
    env = ensure_native_record_var_type(env, name, field_names)

    if field_names == [] or
         not Enum.all?(field_names, fn field ->
           ref = Map.get(fields, field)
           is_binary(ref) and ref != ""
         end) do
      raise ArgumentError,
            "cannot box native record #{inspect(name)} for runtime calls: #{inspect(fields)}"
    end

    if native_record_all_int_fields?(env, name, field_names) do
      compile_native_record_box_ints(var, field_names, fields, env, next)
    else
      compile_native_record_box_mixed(var, name, field_names, fields, env, next)
    end
  end

  defp native_record_all_int_fields?(env, name, field_names) do
    case RecordFields.record_type_name(env, name) do
      nil ->
        Enum.all?(field_names, fn field ->
          case RecordFields.field_type(env, name, field) do
            nil -> true
            "Int" -> true
            _ -> false
          end
        end)

      _type ->
        Enum.all?(field_names, fn field ->
          RecordFields.field_type(env, name, field) in [nil, "Int"]
        end) and
          Enum.any?(field_names, fn field ->
            RecordFields.field_type(env, name, field) == "Int"
          end)
    end
  end

  defp ensure_native_record_var_type(env, name, field_names) do
    case RecordFields.record_type_name(env, name) do
      type when is_binary(type) ->
        EnvBindings.put_var_type(env, name, type)

      _ ->
        case Expr.record_type_for_field_names(field_names, env) do
          nil -> env
          type -> EnvBindings.put_var_type(env, name, type)
        end
    end
  end

  defp compile_native_record_box_ints(var, field_names, fields, env, next) do
    count = length(field_names)
    rec_suffix = RecordCompile.fresh_rec_values_suffix()

    values_array =
      field_names
      |> Enum.map_join(", ", fn field -> Map.fetch!(fields, field) end)

    code = """
    elmc_int_t rec_values_#{rec_suffix}[#{count}] = { #{values_array} };
      #{ValueSlots.boxed_decl(var, "elmc_record_new_values_ints(#{count}, rec_values_#{rec_suffix})", env)}
    """

    {code, var, next + 1}
  end

  defp compile_native_record_box_mixed(var, name, field_names, fields, env, next) do
    count = length(field_names)
    rec_suffix = RecordCompile.fresh_rec_values_suffix()

    {field_code, value_vars, next} =
      Enum.reduce(field_names, {"", [], next}, fn field, {code_acc, vars_acc, c} ->
        ref = Map.fetch!(fields, field)
        box = native_record_field_box_expr(env, name, field, ref)
        tmp = "rec_field_#{c}"
        code = "  #{ValueSlots.boxed_decl(tmp, box, env)}\n"
        {code_acc <> code, vars_acc ++ [tmp], c + 1}
      end)

    values_array = value_vars |> Enum.map(&RcRuntimeEmit.value_expr/1) |> Enum.join(", ")

    code = """
    #{field_code}
      ElmcValue *rec_values_#{rec_suffix}[#{count}] = { #{values_array} };
      #{RcRuntimeEmit.fusion_assign(var, "elmc_record_new_values", "#{count}, rec_values_#{rec_suffix}", env)}
    """

    {code, var, next + 1}
  end

  defp native_record_field_box_expr(env, record_name, field, ref) do
    case RecordFields.field_kind_from_env(env, record_name, field) ||
           RecordFields.field_type(env, record_name, field) do
      "Bool" -> "elmc_new_bool(#{ref})"
      "Float" -> "elmc_new_float((double)#{ref})"
      "String" -> "elmc_new_string(#{ref})"
      _ -> "elmc_new_int(#{ref})"
    end
  end

  @spec native_record_field_names(Types.compile_env(), String.t(), %{String.t() => String.t()}) ::
          [String.t()]
  defp native_record_field_names(env, name, fields) do
    shapes = Map.get(env, :__record_shapes__, %{})

    field_order =
      case Map.get(shapes, name) do
        names when is_list(names) ->
          names

        _ ->
          case Map.get(env, :__var_types__, %{}) |> Map.get(name) do
            type when is_binary(type) -> Expr.record_shape_for_type(type, env)
            _ -> nil
          end
      end

    case field_order do
      names when is_list(names) ->
        Enum.filter(names, &Map.has_key?(fields, &1))

      _ ->
        fields
        |> Map.keys()
        |> Enum.sort()
    end
  end

  @spec closure_function_name(closure_signature(), String.t()) :: {String.t(), boolean()}
  defp closure_function_name(signature, prefix) do
    defs = Process.get(:elmc_lambda_defs, %{})

    case Map.fetch(defs, signature) do
      {:ok, name} ->
        {name, false}

      :error ->
        closure_id = Process.get(:elmc_lambda_counter, 0) + 1
        Process.put(:elmc_lambda_counter, closure_id)
        name = "#{prefix}_#{closure_id}"
        Process.put(:elmc_lambda_defs, Map.put(defs, signature, name))
        {name, true}
    end
  end

  defp compile_callee_operands(args, callee_mod, callee_fun, env, operand_env, counter, operand_opts) do
    decl_map = Map.get(env, :__program_decls__, %{})

    param_names =
      case Map.get(decl_map, {callee_mod, callee_fun}) do
        %{args: names} when is_list(names) -> names
        _ -> []
      end

    decl = Map.get(decl_map, {callee_mod, callee_fun})

    direct_mixed? =
      is_map(decl) and
        EnvBindings.direct_call_target?(env, callee_mod, callee_fun) and
        FunctionEmit.mixed_direct_abi?(decl, callee_mod, decl_map)

    arg_kinds =
      if direct_mixed?, do: NativeFunctionCall.arg_kinds(decl, callee_mod, decl_map), else: []

    Enum.reduce(Enum.with_index(args), {"", [], [], counter}, fn {arg_expr, idx},
                                                                 {code_acc, vars_acc,
                                                                  passthrough_acc, c} ->
      kind = if direct_mixed?, do: Enum.at(arg_kinds, idx, :boxed), else: :boxed

      {code, var, c2, passthrough?} =
        case kind do
          :native_int ->
            {arg_code, native_ref, c3} = Host.compile_native_int_expr(arg_expr, operand_env, c)
            {arg_code, native_ref, c3, true}

          :native_bool ->
            {arg_code, native_ref, c3} = Host.compile_native_bool_expr(arg_expr, operand_env, c)
            {arg_code, native_ref, c3, true}

          :boxed ->
            compile_call_operand_inner(arg_expr, operand_env, c, operand_opts)
        end

      param = Enum.at(param_names, idx)

      {coerce_code, coerced_var, c3, coerced_temp?} =
        if kind == :boxed do
          LayoutCoerceEmit.coerce_call_operand(var, arg_expr, callee_mod, callee_fun, param, env, c2)
        else
          {"", var, c2, false}
        end

      final_var = coerced_var
      final_passthrough = passthrough? and not coerced_temp?

      {
        code_acc <> "\n  " <> code <> coerce_code,
        vars_acc ++ [final_var],
        passthrough_acc ++ [final_passthrough],
        c3
      }
    end)
  end

  defp compile_boxed(module_name, name, args, env, counter, arity, c_name) do
    rc_callee? = RcRequired.rc_required?(module_name, name)
    caller_rc? =
      Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
        Map.get(env, :__native_rc_out__, false)

    before_args_probe =
      DebugProbes.call_probe(env, module_name, name, :before_args) |> DebugProbes.region()

    borrow_args? = EnvBindings.callee_borrow_args?(env, module_name, name)
    operand_opts = [borrow_args?: borrow_args?]

    operand_env = RcRuntimeEmit.strip_function_tail_scope(env)

    {arg_code, arg_vars, arg_passthrough, counter} =
      compile_callee_operands(
        args,
        module_name,
        name,
        env,
        operand_env,
        counter,
        operand_opts
      )

    {default_out, next} = CaseCompile.fresh_var(counter, env)
    call_args_id = counter + 1

    out =
      case RcRuntimeEmit.tail_call_out_target(env) || RcRuntimeEmit.nested_out_target(env) do
        into_out when is_binary(into_out) -> into_out
        _ -> default_out
      end

    if caller_rc? and not RcRuntimeEmit.function_out_ref?(out), do: ValueSlots.track(out)
    argc = length(arg_vars)

    after_args_probe =
      DebugProbes.call_probe(env, module_name, name, :after_args) |> DebugProbes.region()

    after_call_probe =
      DebugProbes.call_probe(env, module_name, name, :after_call) |> DebugProbes.region()

    releases =
      if borrow_args? do
        release_borrowed_call_operands(env, arg_vars, arg_passthrough)
      else
        release_call_operands(env, arg_vars, arg_passthrough)
      end

    code =
      cond do
        arity > 0 and argc < arity ->
          {closure_code, _partial_out, _partial_next} =
            partial_closure(module_name, name, arity, arg_vars, env, counter, out)

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            #{closure_code}
            #{after_call_probe}
            #{releases}
          """

        arity > 0 and argc > arity ->
          {first_vars, rest_vars} = Enum.split(arg_vars, arity)
          rest_exprs = Enum.drop(args, arity)
          first_args = Enum.join(first_vars, ", ")
          rest_args = Enum.join(rest_vars, ", ")
          head_var = "head_#{call_args_id}"
          first_args_var = "call_args_#{call_args_id}"
          rest_args_var = "extra_args_#{next}"

          head_shape =
            Expr.record_shape_for_function_return({module_name, name}, env, arity) ||
              Expr.function_decl_return_shape(env, module_name, name)

          field_accessor_field =
            case rest_exprs do
              [%{op: :lambda, body: body} | _] ->
                field_accessor_field(body)

              _ ->
                nil
            end

          apply_expr =
            if is_binary(field_accessor_field) and is_list(head_shape) do
              index_ref =
                Expr.record_field_index_ref(field_accessor_field, head_shape, nil, env)

              "elmc_record_get_index(#{head_var}, #{index_ref})"
            else
              "elmc_apply_extra(#{head_var}, #{rest_args_var}, #{length(rest_vars)})"
            end

          head_call =
            if rc_callee? do
              if caller_rc? do
                """
                ElmcValue *#{head_var} = NULL;
                Rc = #{c_name}(&#{head_var}, #{first_args_var}, #{length(first_vars)});
                CHECK_RC(Rc);
                """
              else
                failure_return = RcRuntimeEmit.failure_return(env)

                """
                ElmcValue *#{head_var} = NULL;
                {
                  RC __call_rc = #{c_name}(&#{head_var}, #{first_args_var}, #{length(first_vars)});
                  if (__call_rc != RC_SUCCESS) {
                  #{ValueSlots.release_stmt(head_var)};
                  #{head_var} = NULL;
                  #{failure_return}
                }
                }
                """
              end
              |> String.trim()
            else
              "ElmcValue *#{head_var} = #{c_name}(#{first_args_var}, #{length(first_vars)});"
            end

          field_accessor_inline? =
            is_binary(field_accessor_field) and is_list(head_shape)

          apply_block =
            if field_accessor_inline? do
              rest_releases = Enum.map_join(rest_vars, "\n  ", &ValueSlots.release_stmt/1)

              """
              #{head_call}
              #{boxed_out_decl(env, out, apply_expr)}
              #{rest_releases}
              """
            else
              """
              #{head_call}
              ElmcValue *#{rest_args_var}[#{max(length(rest_vars), 1)}] = { #{rest_args} };
              #{boxed_out_decl(env, out, apply_expr)}
              """
            end

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            ElmcValue *#{first_args_var}[#{max(length(first_vars), 1)}] = { #{first_args} };
            #{apply_block}
            #{after_call_probe}
            #{ValueSlots.release_stmt(head_var)};
            #{releases}
          """

        arity == 0 and argc > 0 ->
          head_var = "head_#{call_args_id}"
          args_var = "call_args_#{call_args_id}"
          arg_list = call_arg_list(arg_vars)
          head_init = zero_arg_call_code(env, module_name, name, c_name, head_var)

          """
          #{before_args_probe}
          #{arg_code}
            #{after_args_probe}
            #{head_init}
            ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
            #{boxed_out_decl(env, out, "elmc_closure_call(#{head_var}, #{args_var}, #{argc})")}
            #{after_call_probe}
            #{ValueSlots.release_stmt(head_var)};
            #{releases}
          """

        true ->
          if EnvBindings.direct_call_target?(env, module_name, name) do
            direct_call = direct_boxed_call_expr(c_name, arg_vars, out, rc_callee?)

            """
            #{before_args_probe}
            #{arg_code}
              #{after_args_probe}
              #{rc_call_assignment(env, out, direct_call, rc_callee?, caller_rc?)}
              #{after_call_probe}
              #{releases}
            """
          else
            args_var = "call_args_#{call_args_id}"
            arg_list = call_arg_list(arg_vars)

            call_expr =
              if rc_callee? do
                "#{c_name}(#{RcRuntimeEmit.allocator_out_arg(out)}, #{args_var}, #{argc})"
              else
                "#{c_name}(#{args_var}, #{argc})"
              end

            """
            #{before_args_probe}
            #{arg_code}
              #{after_args_probe}
              ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };
              #{rc_call_assignment(env, out, call_expr, rc_callee?, caller_rc?)}
              #{after_call_probe}
              #{releases}
            """
          end
      end

    {code, out, max(next, call_args_id + 1)}
  end

  defp rc_call_assignment(env, out, call_expr, true, _caller_rc_flag) do
    if caller_rc?(env) do
      unless RcRuntimeEmit.function_out_ref?(out), do: ValueSlots.track(out)

      if predeclared_out?(env, out) or ValueSlots.owned_ref?(out) or
           RcRuntimeEmit.function_out_ref?(out) do
        """
        Rc = #{call_expr};
        CHECK_RC(Rc);
        """
        |> String.trim()
      else
        """
        ElmcValue *#{out} = NULL;
        Rc = #{call_expr};
        CHECK_RC(Rc);
        """
        |> String.trim()
      end
    else
      if predeclared_out?(env, out) or ValueSlots.owned_ref?(out) or
           RcRuntimeEmit.function_out_ref?(out) do
        """
        #{ValueSlots.boxed_decl(out, "NULL")}
        {
          RC __call_rc = #{call_expr};
          if (__call_rc != RC_SUCCESS) {
            #{ValueSlots.abandon_stmt(out)}
            #{rc_call_failure_return(env)}
          }
        }
        """
        |> String.trim()
      else
        """
        ElmcValue *#{out} = NULL;
        {
          RC __call_rc = #{call_expr};
          if (__call_rc != RC_SUCCESS) {
            #{ValueSlots.abandon_stmt(out)}
            #{rc_call_failure_return(env)}
          }
        }
        """
        |> String.trim()
      end
    end
  end

  defp rc_call_assignment(env, out, call_expr, false, _caller_rc?) do
    boxed_out_decl(env, out, call_expr)
  end

  defp rc_call_failure_return(env) do
    cond do
      Map.get(env, :__rc_catch__) -> "return Rc"
      Map.get(env, :__native_rc_out__) -> "return __call_rc"
      true -> RcRuntimeEmit.failure_return(env)
    end
  end

  defp caller_rc?(env) do
    Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
      Map.get(env, :__native_rc_out__, false)
  end

  defp boxed_out_decl(env, out, rhs) do
    if caller_rc?(env) and not RcRuntimeEmit.function_out_ref?(out), do: ValueSlots.track(out)

    case RcRuntimeEmit.parse_take_wrapper_call(rhs) do
      {:ok, take_fn, call_args} ->
        RcRuntimeEmit.take_wrapper_assign(out, take_fn, call_args, env)

      :error ->
        if predeclared_out?(env, out) or ValueSlots.owned_ref?(out) or
             RcRuntimeEmit.function_out_ref?(out) do
          if RcRuntimeEmit.function_out_ref?(out) and ValueSlots.owned_ref?(rhs) do
            RcRuntimeEmit.transfer_assignment(out, rhs)
          else
            "#{RcRuntimeEmit.assignment_lhs(out)} = #{rhs};"
          end
        else
          "ElmcValue *#{out} = #{rhs};"
        end
    end
  end

  defp predeclared_out?(env, out),
    do: into_predeclared_out?(env, out) or declared_out_slot?(env, out)

  defp declared_out_slot?(env, out) do
    MapSet.member?(Map.get(env, :__declared_outs__, MapSet.new()), out)
  end

  defp into_predeclared_out?(env, out),
    do: Map.get(env, :__into_out__) == out

  defp call_arg_list(arg_vars), do: RcRuntimeEmit.call_arg_list(arg_vars)

  defp direct_boxed_call_expr(c_name, arg_vars, out, rc_callee?) do
    out_arg = RcRuntimeEmit.allocator_out_arg(out)

    case arg_vars do
      [] ->
        if rc_callee?, do: "#{c_name}(#{out_arg})", else: "#{c_name}()"

      _ ->
        args = call_arg_list(arg_vars)

        if rc_callee? do
          "#{c_name}(#{out_arg}, #{args})"
        else
          "#{c_name}(#{args})"
        end
    end
  end

  defp zero_arg_call_code(env, module_name, name, c_name, out) do
    if RcRequired.rc_required?(module_name, name) do
      zero_arg_rc_call_stmts(env, module_name, name, c_name, out)
    else
      rhs = zero_arg_call_rhs(env, module_name, name, c_name)
      boxed_out_decl(env, out, rhs)
    end
  end

  defp zero_arg_call_rhs(env, module_name, name, c_name) do
    if EnvBindings.direct_call_target?(env, module_name, name),
      do: "#{c_name}()",
      else: "#{c_name}(NULL, 0)"
  end

  defp zero_arg_rc_call_stmts(env, module_name, name, c_name, out) do
    call = zero_arg_rc_call_expr(env, module_name, name, c_name, out)
    init = zero_arg_rc_out_init(env, out)

    if caller_rc?(env) do
      """
      #{init}
      Rc = #{call};
      CHECK_RC(Rc);
      """
      |> String.trim()
    else
      """
      #{init}
      {
        RC __call_rc = #{call};
        if (__call_rc != RC_SUCCESS) {
          #{ValueSlots.release_stmt(out)}
          #{out} = NULL;
          #{rc_call_failure_return(env)}
        }
      }
      """
      |> String.trim()
    end
  end

  defp zero_arg_rc_out_init(env, out) do
    if ValueSlots.owned_ref?(out) or RcRuntimeEmit.function_out_ref?(out) or
         predeclared_out?(env, out) do
      ""
    else
      ValueSlots.boxed_null_decl(out)
    end
  end

  defp zero_arg_rc_call_expr(env, module_name, name, c_name, out) do
    out_arg = RcRuntimeEmit.allocator_out_arg(out)

    if EnvBindings.direct_call_target?(env, module_name, name) do
      "#{c_name}(#{out_arg})"
    else
      "#{c_name}(#{out_arg}, NULL, 0)"
    end
  end

  defp partial_rc_closure_return_body(module_name, name, c_name, arity, env) do
    closure_call_return_body(module_name, name, c_name, "call_args, #{arity}", env)
  end

  defp rc_closure_return_body(module_name, name, c_name, call_args_spec, env) do
    closure_call_return_body(module_name, name, c_name, call_args_spec, env)
  end

  defp closure_call_return_body(module_name, name, c_name, call_args_spec, env) do
    decl_map = program_decl_map(env)
    emit_wrapper? = emit_wrapper_for_closure?(module_name, name, env)

    with {:ok, decl} <- Map.fetch(decl_map, {module_name, name}) do
      cond do
        NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) ->
          native_scalar_closure_return_body(c_name, call_args_spec, module_name, name, decl, env)

        RcRequired.rc_required?(module_name, name) and emit_wrapper? ->
          rc_boxed_wrapper_closure_return_body(c_name, call_args_spec)

        emit_wrapper? ->
          "return #{c_name}(#{call_args_spec});"

        EnvBindings.direct_call_target?(env, module_name, name) ->
          mixed_direct_closure_return_body(
            c_name,
            call_args_spec,
            module_name,
            name,
            decl,
            env,
            true
          )

        true ->
          mixed_direct_closure_return_body(
            c_name,
            call_args_spec,
            module_name,
            name,
            decl,
            env,
            false
          )
      end
    else
      _ -> "return #{c_name}(#{call_args_spec});"
    end
  end

  defp rc_boxed_wrapper_closure_return_body(c_name, call_args_spec) do
    """
    ElmcValue *out = NULL;
    {
      RC __call_rc = #{c_name}(&out, #{call_args_spec});
      if (__call_rc != RC_SUCCESS) {
        ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "closure call failed");
        return NULL;
      }
    }
    return out;
    """
    |> String.trim()
  end

  defp wrapper_abi_target?(module_name, name) do
    MapSet.member?(Process.get(:elmc_wrapper_targets, MapSet.new()), {module_name, name})
  end

  defp emit_wrapper_for_closure?(module_name, name, env) do
    wrapper_abi_target?(module_name, name) or
      (not RcRequired.rc_required?(module_name, name) and
         not EnvBindings.direct_call_target?(env, module_name, name))
  end

  defp program_decl_map(env) do
    Map.get(env, :__program_decls__) || Process.get(:elmc_program_decls, %{})
  end

  defp closure_env(env) do
    env
    |> RcRuntimeEmit.strip_function_tail_scope()
    |> Map.put_new(:__program_decls__, Process.get(:elmc_program_decls, %{}))
  end

  defp native_scalar_closure_return_body(c_name, call_args_spec, module_name, name, decl, env) do
    decl_map = Map.fetch!(env, :__program_decls__)
    {args_var, arity} = closure_call_args(call_args_spec, module_name, name, env)
    arg_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)
    return_kind = NativeFunctionCall.return_kind(decl, module_name, decl_map)

    {bindings, native_arg_names} =
      0..(arity - 1)
      |> Enum.map(fn index ->
        kind = Enum.at(arg_kinds, index, :boxed)
        c_arg = "closure_native_arg_#{index}"
        {closure_native_arg_binding(args_var, index, c_arg, kind), c_arg}
      end)
      |> Enum.unzip()

    native_args = Enum.join(native_arg_names, ", ")
    bindings = Enum.join(bindings, "\n  ")

    return_stmt =
      case return_kind do
        :native_int ->
          """
          ElmcValue *out = NULL;
          RC Rc = RC_SUCCESS;
          CATCH_BEGIN
            Rc = elmc_new_int(&out, #{c_name}_native(#{native_args}));
            CHECK_RC(Rc);
          CATCH_END
          return out;
          """

        :native_bool ->
          """
          ElmcValue *out = NULL;
          RC Rc = RC_SUCCESS;
          CATCH_BEGIN
            Rc = elmc_new_bool(&out, #{c_name}_native(#{native_args}));
            CHECK_RC(Rc);
          CATCH_END
          return out;
          """
        :boxed ->
          if NativeFunctionCall.native_boxed_rc_abi?(decl, module_name, decl_map) do
            """
            ElmcValue *out = NULL;
            RC Rc = RC_SUCCESS;
            CATCH_BEGIN
              Rc = #{c_name}_native(&out, #{native_args});
              CHECK_RC(Rc);
            CATCH_END
            return out;
            """
            |> String.trim()
          else
            "return #{c_name}_native(#{native_args});"
          end
      end

    argc_void =
      cond do
        arity == 0 and call_args_spec == "args, argc" ->
          "(void)args;\n(void)argc;"

        call_args_spec == "args, argc" ->
          "(void)argc;"

        true ->
          ""
      end

    """
    #{argc_void}
    #{bindings}
    #{return_stmt}
    """
    |> String.trim()
  end

  defp mixed_direct_closure_return_body(c_name, call_args_spec, module_name, name, decl, env, rc_callee?) do
    decl_map = Map.fetch!(env, :__program_decls__)
    {args_var, arity} = closure_call_args(call_args_spec, module_name, name, env)
    arg_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)

    {bindings, call_arg_names} =
      0..(arity - 1)
      |> Enum.map(fn index ->
        kind = Enum.at(arg_kinds, index, :boxed)
        c_arg = "closure_direct_arg_#{index}"
        {closure_native_arg_binding(args_var, index, c_arg, kind), c_arg}
      end)
      |> Enum.unzip()

    call_args = Enum.join(call_arg_names, ", ")
    bindings = Enum.join(bindings, "\n  ")

    return_stmt =
      if rc_callee? do
        """
        ElmcValue *out = NULL;
        {
          RC __call_rc = #{c_name}(&out, #{call_args});
          if (__call_rc != RC_SUCCESS) {
            ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "closure call failed");
            return NULL;
          }
        }
        return out;
        """
      else
        "return #{c_name}(#{call_args});"
      end

    argc_void =
      cond do
        arity == 0 and call_args_spec == "args, argc" ->
          "(void)args;\n(void)argc;"

        call_args_spec == "args, argc" ->
          "(void)argc;"

        true ->
          ""
      end

    """
    #{argc_void}
    #{bindings}
    #{return_stmt}
    """
    |> String.trim()
  end

  defp closure_native_arg_binding(args_var, index, c_arg, :native_int) do
    "elmc_int_t #{c_arg} = (#{args_var}[#{index}]) ? elmc_as_int(#{args_var}[#{index}]) : 0;"
  end

  defp closure_native_arg_binding(args_var, index, c_arg, :native_bool) do
    "bool #{c_arg} = (#{args_var}[#{index}]) ? elmc_as_bool(#{args_var}[#{index}]) : false;"
  end

  defp closure_native_arg_binding(args_var, index, c_arg, :boxed) do
    "ElmcValue *#{c_arg} = #{args_var}[#{index}];"
  end

  defp closure_call_args("args, argc", module_name, name, env) do
    {"args", EnvBindings.function_arity(env, module_name, name, [])}
  end

  defp closure_call_args("call_args, " <> arity_str, _module_name, _name, _env) do
    {"call_args", String.to_integer(String.trim(arity_str))}
  end

  defp release_call_operands(env, arg_vars, arg_passthrough) do
    arg_vars
    |> Enum.with_index()
    |> Enum.reject(fn {var, index} ->
      passthrough?(arg_passthrough, index) or EnvBindings.borrowed_arg_ref?(env, var) or
        RcRuntimeEmit.function_out_ref?(var)
    end)
    |> Enum.map(fn {var, _index} -> var end)
    |> Enum.map_join("\n  ", &ValueSlots.post_call_operand_release/1)
    |> case do
      "" -> ""
      releases -> releases
    end
  end

  defp passthrough?(nil, _index), do: false
  defp passthrough?(arg_passthrough, index), do: Enum.at(arg_passthrough, index, false)

  defp release_borrowed_call_operands(env, arg_vars, arg_passthrough) do
    arg_vars
    |> Enum.zip(arg_passthrough)
    |> Enum.reject(fn {var, passthrough?} ->
      passthrough? or EnvBindings.borrowed_arg_ref?(env, var)
    end)
    |> Enum.map_join("\n  ", fn {var, _} -> ValueSlots.post_call_operand_release(var) end)
    |> case do
      "" -> ""
      releases -> releases
    end
  end

  defp field_accessor_field(%{op: :field_access, field: field}) when is_binary(field),
    do: field

  defp field_accessor_field(_body), do: nil

  @spec compile_cross_module(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def compile_cross_module(target, args, env, counter) do
    case Util.split_qualified_function_target(target) do
      {module_name, name} -> compile(module_name, name, args, env, counter)
      nil -> compile(target, "", args, env, counter)
    end
  end
end
