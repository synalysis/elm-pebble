defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Expr do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.Emit.If
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Qualified.Draws, as: QualifiedDraws
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec emit_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()
  @spec emit_expr(Types.ir_list_literal_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()
  @spec emit_expr(Types.ir_let_in_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()
  @spec emit_expr(Types.ir_qualified_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()

  def emit_expr(%{op: :list_literal, items: items}, env, counter) do
    case Host.direct_static_draw_table_loop(items, env, counter) do
      {:ok, table_code, counter} ->
        {:ok, table_code, counter}

      :error ->
        Enum.reduce_while(items, {:ok, "", counter}, fn item, {:ok, acc, c} ->
          case emit_expr(item, env, c) do
            {:ok, code, c2} -> {:cont, {:ok, acc <> "\n" <> code, c2}}
            :error -> {:halt, :error}
          end
        end)
    end
  end

  def emit_expr(
        %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
        env,
        counter
      ) do
    cond do
      native_int_let?(name, value_expr, in_expr, env) ->
        hoisted_before = Process.get(:elmc_hoisted_native_ints, %{})

        {value_code, value_ref, counter} =
          try do
            compile_env = Host.merge_process_hoisted_native_ints(env)
            Host.compile_native_int_expr(value_expr, compile_env, counter)
          after
            Process.put(:elmc_hoisted_native_ints, hoisted_before)
          end

        next = counter + 1
        native_var = "direct_native_let_#{Util.safe_c_suffix(name)}_#{next}"

        body_env =
          env
          |> Map.delete(name)
          |> EnvBindings.put_native_int_binding(name, native_var)
          |> EnvBindings.remove_native_bool_binding(name)
          |> EnvBindings.put_boxed_int_binding(name, false)

        case emit_expr(in_expr, body_env, next) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
               const elmc_int_t #{native_var} = #{value_ref};
             #{body_code}
             """, counter}

          :error ->
            :error
        end

      native_string_let?(name, value_expr, in_expr, env) ->
        {value_code, value_ref, cleanup_refs, counter} =
          Host.compile_native_string_expr(value_expr, env, counter)

        body_env =
          env
          |> Map.delete(name)
          |> EnvBindings.put_native_string_binding(name, value_ref)

        cleanup_code =
          cleanup_refs
          |> Enum.map_join("\n  ", fn ref -> "elmc_release(#{ref});" end)

        case emit_expr(in_expr, body_env, counter) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
             #{body_code}
               #{cleanup_code}
             """, counter}

          :error ->
            :error
        end

      native_float_let?(name, value_expr, in_expr, env) ->
        {value_code, value_ref, counter} =
          Host.compile_native_float_expr(value_expr, env, counter)

        next = counter + 1
        native_var = "direct_native_float_let_#{Util.safe_c_suffix(name)}_#{next}"

        body_env =
          env
          |> Map.delete(name)
          |> EnvBindings.put_native_float_binding(name, native_var)
          |> EnvBindings.remove_native_int_binding(name)

        case emit_expr(in_expr, body_env, counter) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
               const double #{native_var} = #{value_ref};
             #{body_code}
             """, counter}

          :error ->
            :error
        end

      pebble_angle_let_binding?(name, value_expr, in_expr, env) ->
        body_env = EnvBindings.put_pebble_angle_binding(env, name, value_expr)

        case emit_expr(in_expr, body_env, counter) do
          {:ok, body_code, counter} -> {:ok, body_code, counter}
          :error -> :error
        end

      Host.direct_native_text_options_let?(name, value_expr, in_expr, env) ->
        case Host.direct_native_text_options_packed_expr(value_expr) do
          {:ok, packed_expr} ->
            {value_code, value_ref, counter} = Host.direct_int_value(packed_expr, env, counter)
            next = counter + 1
            native_var = "direct_native_let_#{Util.safe_c_suffix(name)}_#{next}"

            body_env =
              env
              |> Map.delete(name)
              |> EnvBindings.put_native_int_binding(name, native_var)
              |> EnvBindings.remove_native_bool_binding(name)
              |> EnvBindings.put_boxed_int_binding(name, false)

            case emit_expr(in_expr, body_env, next) do
              {:ok, body_code, counter} ->
                {:ok,
                 """
                 #{value_code}
                   const elmc_int_t #{native_var} = #{value_ref};
                 #{body_code}
                 """, counter}

              :error ->
                :error
            end

          :error ->
            :error
        end

      Host.direct_native_record_helper_let?(name, value_expr, env) ->
        case Host.direct_emit_native_record_fields(name, value_expr, env, counter) do
          {:ok, field_code, body_env, counter} ->
            case emit_expr(in_expr, body_env, counter) do
              {:ok, body_code, counter} ->
                {:ok,
                 """
                 #{field_code}
                 #{body_code}
                 """, counter}

              :error ->
                :error
            end

          :error ->
            :error
        end

      fragment_expr?(value_expr, env) ->
        emit_expr(in_expr, Map.put(env, name, {:direct_fragment, value_expr}), counter)

      inline_render_expr?(value_expr, env) ->
        emit_expr(in_expr, Map.put(env, name, {:direct_fragment, value_expr}), counter)

      true ->
        case emit_direct_command_native_int_let(name, value_expr, in_expr, env, counter) do
          {:ok, code, counter} ->
            {:ok, code, counter}

          :error ->
            {value_code, value_var, counter} = Host.compile_expr(value_expr, env, counter)

            body_env =
              env
              |> Map.put(name, value_var)
              |> EnvBindings.put_boxed_int_binding(name, Host.native_int_expr?(value_expr, env))
              |> EnvBindings.put_record_shape(name, Host.record_shape(value_expr, env))

            case emit_expr(in_expr, body_env, counter) do
              {:ok, body_code, counter} ->
                {:ok,
                 """
                 #{value_code}
                   #{body_code}
                   elmc_release(#{value_var});
                 """, counter}

              :error ->
                :error
            end
        end
    end
  end

  def emit_expr(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      ) do
    {cond_code, cond_ref, cond_release, counter} =
      if Host.native_bool_expr?(cond_expr, env) do
        {code, ref, counter} = Host.compile_native_bool_expr(cond_expr, env, counter)
        {code, ref, "", counter}
      else
        {code, var, counter} = Host.compile_expr(cond_expr, env, counter)
        {code, "elmc_as_int(#{var}) != 0", "  elmc_release(#{var});", counter}
      end

    then_env = Hoist.put_hoisted_native_bool(env, cond_expr, "1")
    else_env = Hoist.put_hoisted_native_bool(env, cond_expr, "0")

    with {:ok, then_code, counter} <- emit_expr(then_expr, then_env, counter),
         {:ok, else_code, counter} <- emit_expr(else_expr, else_env, counter) do
      {:ok, If.if_code(cond_code, cond_ref, then_code, else_code, cond_release), counter}
    else
      _ -> :error
    end
  end

  def emit_expr(%{op: :case, subject: subject, branches: branches}, env, counter) do
    subject_ref = Map.get(env, subject, subject)

    case_env =
      if Patterns.maybe_unwrap_just_case?(branches),
        do: Map.put(env, :maybe_unwrap_just, true),
        else: env

    result =
      Enum.reduce_while(branches, {:ok, "", counter}, fn branch, {:ok, acc, c} ->
        {branch_env, unwrap_setup, unwrap_release, c} =
          Patterns.maybe_unwrap_var_branch(case_env, branch, subject_ref, c)

        branch_env =
          Map.put(
            branch_env,
            :__direct_targets__,
            Map.get(env, :__direct_targets__, MapSet.new())
          )

        case emit_expr(branch.expr, branch_env, c) do
          {:ok, expr_code, c2} ->
            cond_code = Patterns.pattern_condition(subject_ref, branch.pattern)

            branch_body =
              """
              #{CSource.indent(unwrap_setup, 4)}
              #{CSource.indent(expr_code, 4)}
              #{CSource.indent(unwrap_release, 4)}
              """

            cond do
              cond_code == "0" ->
                {:cont, {:ok, acc, c2}}

              cond_code == "1" and acc == "" ->
                {:halt, {:ok, acc <> branch_body, c2}}

              cond_code == "1" ->
                snippet = """
                else {
                #{branch_body}
                }
                """

                {:halt, {:ok, acc <> snippet, c2}}

              true ->
                snippet = """
                #{if acc == "", do: "if", else: "else if"} (#{cond_code}) {
                #{branch_body}
                }
                """

                {:cont, {:ok, acc <> snippet, c2}}
            end

          :error ->
            {:halt, :error}
        end
      end)

    case result do
      {:ok, branch_code, counter} -> {:ok, branch_code, counter}
      :error -> :error
    end
  end

  def emit_expr(%{op: :call, name: name, args: args}, env, counter) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())

    cond do
      name == "__append__" and length(args) == 2 ->
        [left, right] = args

        with {:ok, left_code, counter} <- emit_expr(left, env, counter),
             {:ok, right_code, counter} <- emit_expr(right, env, counter) do
          {:ok, left_code <> right_code, counter}
        else
          _ -> :error
        end

      let_bound_closure_call?(env, name) ->
        emit_closure_command_call(name, args, env, counter)

      MapSet.member?(targets, {module_name, name}) ->
        Host.direct_emit_command_call({module_name, name}, args, env, counter)

      true ->
        :error
    end
  end

  def emit_expr(%{op: :var, name: name}, env, counter) do
    case Map.get(env, name) do
      {:direct_fragment, expr} -> emit_expr(expr, Map.delete(env, name), counter)
      _ -> :error
    end
  end

  def emit_expr(%{op: :qualified_call, target: target, args: args}, env, counter) do
    Host.direct_emit_qualified(Host.normalize_special_target(target), args, env, counter)
  end

  def emit_expr(_expr, _env, _counter), do: :error

  defp let_bound_closure_call?(env, name) do
    case Map.get(env, Host.binding_key(name)) do
      closure_var when is_binary(closure_var) -> true
      _ -> false
    end
  end

  defp emit_closure_command_call(name, args, env, counter) do
    closure_var = Map.fetch!(env, Host.binding_key(name))

    {arg_code, arg_refs, release_refs, counter} =
      Enum.reduce(args, {"", [], [], counter}, fn arg_expr,
                                                  {code_acc, refs_acc, releases_acc, c} ->
        {code, ref, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ [ref], c2}
      end)

    next = counter + 1
    argc = length(arg_refs)
    arg_list = Enum.join(arg_refs, ", ")

    releases =
      release_refs
      |> Enum.map_join("\n  ", fn ref -> "elmc_release(#{ref});" end)

    {:ok,
     """
     #{arg_code}
       ElmcValue *direct_call_args_#{next}[#{max(argc, 1)}] = { #{arg_list} };
       ElmcValue *direct_closure_result_#{next} = elmc_closure_call(#{closure_var}, direct_call_args_#{next}, #{argc});
       #{releases}
     """, next}
  end

  defp emit_direct_command_native_int_let(name, value_expr, in_expr, env, counter)
       when is_binary(name) or is_atom(name) do
    usage = native_int_usage(name, in_expr, env)

    if not Map.get(env, :__hoisted_native_ints_enabled__, false) or
         not native_int_let_value?(value_expr, env) or
         Host.binding_used_in_lambda?(name, in_expr) or usage.boxed > 0 do
      :error
    else
      hoisted_before = Process.get(:elmc_hoisted_native_ints, %{})

      {value_code, value_ref, counter} =
        try do
          compile_env = Host.merge_process_hoisted_native_ints(env)
          Host.compile_native_int_expr(value_expr, compile_env, counter)
        after
          Process.put(:elmc_hoisted_native_ints, hoisted_before)
        end

      if direct_command_native_int_ref?(value_ref) do
        next = counter + 1
        native_var = "direct_native_let_#{Util.safe_c_suffix(name)}_#{next}"

        body_env =
          env
          |> Map.delete(name)
          |> EnvBindings.put_native_int_binding(name, native_var)
          |> EnvBindings.remove_native_bool_binding(name)
          |> EnvBindings.put_boxed_int_binding(name, false)

        case emit_expr(in_expr, body_env, next) do
          {:ok, body_code, counter} ->
            {:ok,
             """
             #{value_code}
               const elmc_int_t #{native_var} = #{value_ref};
             #{body_code}
             """, counter}

          :error ->
            :error
        end
      else
        :error
      end
    end
  end

  defp emit_direct_command_native_int_let(_name, _value_expr, _in_expr, _env, _counter),
    do: :error

  defp direct_command_native_int_ref?(ref) when is_binary(ref) do
    ref != "" and not String.starts_with?(ref, "tmp_")
  end

  @spec native_int_let?(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) ::
          boolean()
  defp native_int_let?(name, value_expr, in_expr, env)
       when is_binary(name) or is_atom(name) do
    usage = native_int_usage(name, in_expr, env)
    value_native? = native_int_let_value?(value_expr, env)
    lambda? = Host.binding_used_in_lambda?(name, in_expr)

    value_native? and usage.total > 0 and usage.boxed == 0 and not lambda?
  end

  defp native_int_let?(_name, _value_expr, _in_expr, _env), do: false

  defp native_int_let_value?(value_expr, env) do
    case TypedReturn.expr_type(value_expr, env) do
      nil -> Host.native_int_expr?(value_expr, env)
      "Int" -> Host.native_int_expr?(value_expr, env)
      _ -> false
    end
  end

  defp native_string_let?(name, value_expr, in_expr, env)
       when is_binary(name) or is_atom(name) do
    usage = native_string_usage(name, in_expr, env)

    Host.native_string_expr?(value_expr, env) and usage.total > 0 and usage.boxed == 0 and
      usage.native_string > 0 and not Host.binding_used_in_lambda?(name, in_expr)
  end

  defp native_string_let?(_name, _value_expr, _in_expr, _env), do: false

  defp native_float_let?(name, value_expr, in_expr, env)
       when is_binary(name) or is_atom(name) do
    usage = native_float_usage(name, in_expr, env)

    Host.native_float_expr?(value_expr, env) and usage.total > 0 and usage.boxed == 0 and
      not Host.binding_used_in_lambda?(name, in_expr)
  end

  defp native_float_let?(_name, _value_expr, _in_expr, _env), do: false

  defp pebble_angle_let_binding?(name, value_expr, in_expr, _env)
       when is_binary(name) or is_atom(name) do
    Host.pebble_angle_let?(name, value_expr, in_expr)
  end

  defp pebble_angle_let_binding?(_name, _value_expr, _in_expr, _env), do: false

  defp native_float_usage(name, expr, env) do
    name
    |> collect_direct_var_contexts(expr, :boxed, env)
    |> Enum.reduce(%{total: 0, boxed: 0, native: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
        native: acc.native + if(context == :native, do: 1, else: 0)
      }
    end)
  end

  defp native_string_usage(name, expr, env) do
    name
    |> collect_direct_var_contexts(expr, :boxed, env)
    |> Enum.reduce(%{total: 0, boxed: 0, native_string: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0),
        native_string: acc.native_string + if(context == :native_string, do: 1, else: 0)
      }
    end)
  end

  defp native_int_usage(name, expr, env) do
    name
    |> collect_direct_var_contexts(expr, :boxed, env)
    |> Enum.reduce(%{total: 0, boxed: 0}, fn context, acc ->
      %{
        total: acc.total + 1,
        boxed: acc.boxed + if(context == :boxed, do: 1, else: 0)
      }
    end)
  end

  defp collect_direct_var_contexts(name, %{op: :var, name: var_name}, context, _env) do
    if EnvBindings.same_binding?(name, var_name), do: [context], else: []
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :field_access, arg: arg, field: field},
         _context,
         env
       ) do
    case record_literal_field_expr(arg, field) do
      {:ok, field_expr} ->
        field_context =
          if Host.native_int_candidate_for_analysis?(name, field_expr), do: :native, else: :boxed

        collect_direct_var_contexts(name, field_expr, field_context, env)

      :error ->
        arg_contexts = collect_direct_var_contexts(name, arg, :boxed, env)
        if arg_contexts != [], do: [:boxed | arg_contexts], else: arg_contexts
    end
  end

  defp collect_direct_var_contexts(name, %{op: :field_access, arg: arg}, _context, env) do
    arg_contexts = collect_direct_var_contexts(name, arg, :boxed, env)
    if arg_contexts != [], do: [:boxed | arg_contexts], else: arg_contexts
  end

  defp collect_direct_var_contexts(name, %{op: :add_const, var: var_name}, _context, _env) do
    if EnvBindings.same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_direct_var_contexts(name, %{op: :sub_const, var: var_name}, _context, _env) do
    if EnvBindings.same_binding?(name, var_name), do: [:native], else: []
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :add_vars, left: left, right: right},
         _context,
         _env
       ) do
    [left, right]
    |> Enum.filter(&EnvBindings.same_binding?(name, &1))
    |> Enum.map(fn _ -> :native end)
  end

  defp collect_direct_var_contexts(name, %{op: :call, name: call_name, args: args}, context, env) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    decl_map = Map.get(env, :__program_decls__, %{})

    cond do
      call_name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy"] ->
        Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))

      MapSet.member?(targets, {module_name, call_name}) ->
        collect_direct_command_arg_contexts(name, {module_name, call_name}, args, env)

      native_call =
          Host.native_function_call_arg_kinds(
            %{op: :call, name: call_name, args: args},
            module_name,
            decl_map
          ) ->
        {_call_args, arg_kinds} = native_call
        collect_direct_function_arg_contexts(name, args, arg_kinds, env)

      true ->
        collect_direct_var_contexts_from_map(
          name,
          %{op: :call, name: call_name, args: args},
          context,
          env
        )
    end
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context,
         env
       )
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :runtime_call, function: function, args: args},
         _context,
         env
       )
       when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :qualified_call, target: target, args: args} = expr,
         context,
         env
       ) do
    normalized = Host.normalize_special_target(target)
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    decl_map = Map.get(env, :__program_decls__, %{})

    case Host.special_value_from_target(normalized, args) do
      nil ->
        cond do
          match?({:ok, _arg_kinds}, QualifiedDraws.usage_arg_kinds(normalized, args)) ->
            {:ok, arg_kinds} = QualifiedDraws.usage_arg_kinds(normalized, args)
            collect_direct_function_arg_contexts(name, args, arg_kinds, env)

          Host.qualified_builtin_operator_member?(normalized, [
            "__add__",
            "__sub__",
            "__mul__",
            "__idiv__",
            "modBy",
            "remainderBy"
          ]) ->
            Enum.flat_map(args, &collect_direct_var_contexts(name, &1, :native, env))

          match?({_module, _function}, Util.split_qualified_function_target(normalized)) ->
            case Util.split_qualified_function_target(normalized) do
              {target_module, target_name} ->
                cond do
                  MapSet.member?(targets, {target_module, target_name}) ->
                    collect_direct_command_arg_contexts(
                      name,
                      {target_module, target_name},
                      args,
                      env
                    )

                  native_call = Host.native_function_call_arg_kinds(expr, nil, decl_map) ->
                    {_call_args, arg_kinds} = native_call
                    collect_direct_function_arg_contexts(name, args, arg_kinds, env)

                  true ->
                    collect_direct_var_contexts_from_map(name, expr, context, env)
                end

              nil ->
                collect_direct_var_contexts_from_map(name, expr, context, env)
            end

          true ->
            collect_direct_var_contexts_from_map(name, expr, context, env)
        end

      rewritten ->
        collect_direct_var_contexts(name, rewritten, context, env)
    end
  end

  defp collect_direct_var_contexts(name, %{op: :tuple2, left: left, right: right}, _context, env) do
    left_context =
      if Host.native_int_candidate_for_analysis?(name, left), do: :native, else: :boxed

    right_context =
      if Host.native_int_candidate_for_analysis?(name, right), do: :native, else: :boxed

    collect_direct_var_contexts(name, left, left_context, env) ++
      collect_direct_var_contexts(name, right, right_context, env)
  end

  defp collect_direct_var_contexts(name, %{op: :record_literal, fields: fields}, _context, env)
       when is_list(fields) do
    Enum.flat_map(fields, fn field ->
      context =
        if Host.native_int_candidate_for_analysis?(name, field.expr), do: :native, else: :boxed

      collect_direct_var_contexts(name, field.expr, context, env)
    end)
  end

  defp collect_direct_var_contexts(name, %{op: :compare, left: left, right: right}, _context, env) do
    context =
      if Host.native_int_candidate_for_analysis?(name, left) and
           Host.native_int_candidate_for_analysis?(name, right),
         do: :native,
         else: :boxed

    collect_direct_var_contexts(name, left, context, env) ++
      collect_direct_var_contexts(name, right, context, env)
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
         _context,
         env
       ) do
    branch_context =
      if Host.native_int_candidate_for_analysis?(name, then_expr) and
           Host.native_int_candidate_for_analysis?(name, else_expr),
         do: :native,
         else: :boxed

    collect_direct_var_contexts(name, cond_expr, :boxed, env) ++
      collect_direct_var_contexts(name, then_expr, branch_context, env) ++
      collect_direct_var_contexts(name, else_expr, branch_context, env)
  end

  defp collect_direct_var_contexts(name, %{op: :lambda, args: args, body: body}, _context, env)
       when is_list(args) do
    if Enum.any?(args, &EnvBindings.same_binding?(name, &1)) do
      []
    else
      collect_direct_var_contexts(name, body, :boxed, env)
    end
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :let_in, name: binding_name, value_expr: value_expr, in_expr: in_expr},
         context,
         env
       ) do
    value_contexts = collect_direct_var_contexts(name, value_expr, context, env)

    if EnvBindings.same_binding?(name, binding_name) do
      value_contexts
    else
      value_contexts ++ collect_direct_var_contexts(name, in_expr, context, env)
    end
  end

  defp collect_direct_var_contexts(
         name,
         %{op: :case, subject: subject, branches: branches},
         context,
         env
       ) do
    subject_contexts =
      if EnvBindings.same_binding?(name, subject),
        do: [:boxed],
        else: collect_direct_var_contexts(name, subject, context, env)

    branch_contexts =
      Enum.flat_map(branches, fn %{expr: expr} ->
        collect_direct_var_contexts(name, expr, context, env)
      end)

    subject_contexts ++ branch_contexts
  end

  defp collect_direct_var_contexts(name, expr, context, env) when is_map(expr),
    do: collect_direct_var_contexts_from_map(name, expr, context, env)

  defp collect_direct_var_contexts(name, exprs, context, env) when is_list(exprs),
    do: Enum.flat_map(exprs, &collect_direct_var_contexts(name, &1, context, env))

  defp collect_direct_var_contexts(_name, _expr, _context, _env), do: []

  defp record_literal_field_expr(%{op: :record_literal, fields: fields}, field)
       when is_list(fields) and is_binary(field) do
    case Enum.find(fields, &(&1.name == field)) do
      %{expr: expr} -> {:ok, expr}
      nil -> :error
    end
  end

  defp record_literal_field_expr(_arg, _field), do: :error

  defp collect_direct_var_contexts_from_map(name, expr, context, env) do
    expr
    |> Map.values()
    |> Enum.flat_map(&collect_direct_var_contexts(name, &1, context, env))
  end

  defp collect_direct_command_arg_contexts(name, target_key, args, env) do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.get(target_key)

    arg_kinds =
      if decl, do: CommandDef.arg_kinds(decl), else: Enum.map(args, fn _ -> :boxed end)

    collect_direct_function_arg_contexts(name, args, arg_kinds, env)
  end

  defp collect_direct_function_arg_contexts(name, args, arg_kinds, env) do
    args
    |> Enum.zip(arg_kinds)
    |> Enum.flat_map(fn {arg, kind} ->
      context =
        case kind do
          :native_int -> :native
          :native_string -> :native_string
          _ -> :boxed
        end

      collect_direct_var_contexts(name, arg, context, env)
    end)
  end

  defp fragment_expr_target?(target) do
    target in [
      "Pebble.Ui.toUiNode",
      "String.append",
      "Pebble.Ui.clear",
      "Pebble.Ui.pixel",
      "Pebble.Ui.line",
      "Pebble.Ui.rect",
      "Pebble.Ui.fillRect",
      "Pebble.Ui.circle",
      "Pebble.Ui.fillCircle",
      "Pebble.Ui.textInt",
      "Pebble.Ui.textLabel",
      "Pebble.Ui.text",
      "Pebble.Ui.group",
      "Pebble.Ui.path",
      "Pebble.Ui.pathFilled",
      "Pebble.Ui.pathOutline",
      "Pebble.Ui.pathOutlineOpen",
      "Pebble.Ui.roundRect",
      "Pebble.Ui.arc",
      "Pebble.Ui.fillRadial",
      "Pebble.Ui.drawBitmapInRect",
      "Pebble.Ui.drawRotatedBitmap",
      "String.fromInt"
    ]
  end

  @spec fragment_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defp fragment_expr?(%{op: :list_literal, items: items}, env) do
    Enum.all?(items, &fragment_expr?(&1, env))
  end

  defp fragment_expr?(%{op: :case, branches: branches}, env) do
    Enum.all?(branches, &fragment_expr?(&1.expr, env))
  end

  defp fragment_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env) do
    fragment_expr?(then_expr, env) and fragment_expr?(else_expr, env)
  end

  defp fragment_expr?(%{op: :call, name: "__append__", args: [left, right]}, env) do
    fragment_expr?(left, env) and fragment_expr?(right, env)
  end

  defp fragment_expr?(%{op: :call, name: name}, env) do
    module_name = Map.get(env, :__module__, "Main")
    targets = Map.get(env, :__direct_targets__, MapSet.new())
    MapSet.member?(targets, {module_name, name})
  end

  defp fragment_expr?(%{op: :qualified_call, target: target, args: args}, env) do
    normalized_target = Host.normalize_special_target(target)

    case {normalized_target, args} do
      {"List.cons", [head, tail]} ->
        fragment_expr?(head, env) and fragment_expr?(tail, env)

      _ ->
        fragment_expr_target?(normalized_target) or
          qualified_direct_fragment?(normalized_target, env)
    end
  end

  defp fragment_expr?(_, _env), do: false

  defp inline_render_expr?(expr, env), do: render_list_expr?(expr, env)

  defp qualified_direct_fragment?(target, env) do
    targets = Map.get(env, :__direct_targets__, MapSet.new())

    case Elmc.Backend.CCodegen.DirectRender.Support.qualified_function_target(
           target,
           Map.get(env, :__program_decls__, %{})
         ) do
      nil -> false
      target_key -> MapSet.member?(targets, target_key)
    end
  end

  defp render_list_expr?(expr, env) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})
    seen = MapSet.new()

    case expr do
      %{op: :list_literal, items: items} ->
        Enum.all?(items, &Host.direct_supported?(&1, module_name, decl_map, seen))

      %{op: :if, then_expr: then_expr, else_expr: else_expr} ->
        render_list_expr?(then_expr, env) and render_list_expr?(else_expr, env)

      %{op: :let_in, in_expr: in_expr} ->
        render_list_expr?(in_expr, env)

      %{op: :call, name: "__append__", args: [left, right]} ->
        render_list_expr?(left, env) and render_list_expr?(right, env)

      %{op: :qualified_call, target: target, args: [head, tail]} ->
        Host.normalize_special_target(target) == "List.cons" and
          render_list_expr?(head, env) and render_list_expr?(tail, env)

      _ ->
        false
    end
  end
end
