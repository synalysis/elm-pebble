defmodule Elmc.Backend.CCodegen.RuntimeCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.Native.Float, as: NativeFloat
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.VarAnalysis

  @float_unary_functions ~w(
    elmc_basics_to_float elmc_basics_sin elmc_basics_cos elmc_basics_tan
    elmc_basics_sqrt elmc_basics_abs elmc_basics_negate
  )a

  @spec compile(Types.ir_runtime_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env, counter) do
    if NativeString.expr?(left, env) and NativeString.expr?(right, env) do
      compile_native_append(left, right, env, counter)
    else
      compile_generic(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]},
        env,
        counter
      )
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: function,
          args: [%{op: :lambda, args: [arg], body: body}, list]
        },
        env,
        counter
      )
      when function in ["elmc_list_all", "elmc_list_any"] and is_binary(arg) do
    case compile_list_bool_loop(function, arg, body, list, env, counter) do
      {:ok, code, out, counter} ->
        {code, out, counter}

      :error ->
        compile_generic(
          %{
            op: :runtime_call,
            function: function,
            args: [%{op: :lambda, args: [arg], body: body}, list]
          },
          env,
          counter
        )
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_map",
          args: [lambda, list]
        } = expr,
        env,
        counter
      ) do
    case two_arg_lambda(lambda) do
      {:ok, left, right, body} ->
        case compile_list_map_tuple2_native_int_cursor_loop(left, right, body, list, env, counter) do
          {:ok, code, out, counter} -> {code, out, counter}
          :error -> compile_generic(expr, env, counter)
        end

      :error ->
        case lambda do
          %{op: :lambda, args: [arg], body: body} when is_binary(arg) ->
            case unwrap_tuple2_lambda_body(body, arg) do
              {:ok, left, right, inner} ->
                case compile_list_map_tuple2_native_int_cursor_loop(left, right, inner, list, env, counter) do
                  {:ok, code, out, counter} -> {code, out, counter}
                  :error -> compile_generic(expr, env, counter)
                end

              :error ->
                case compile_list_map_int_range_loop(arg, body, list, env, counter) do
                  {:ok, code, out, counter} ->
                    {code, out, counter}

                  :error ->
                    case compile_list_map_native_int_cursor_loop(arg, body, list, env, counter) do
                      {:ok, code, out, counter} -> {code, out, counter}
                      :error -> compile_generic(expr, env, counter)
                    end
                end
            end

          _ ->
            compile_generic(expr, env, counter)
        end
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_indexed_map",
          args: [%{op: :lambda} = lambda, list]
        } = expr,
        env,
        counter
      ) do
    with {:ok, index_arg, item_arg, body} <- two_arg_lambda(lambda),
         {:ok, code, out, counter} <-
           compile_list_indexed_map_int_loop(index_arg, item_arg, body, list, env, counter) do
      {code, out, counter}
    else
      _ -> compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{
          op: :runtime_call,
          function: "elmc_list_foldl",
          args: [%{op: :lambda} = lambda, acc, list]
        } = expr,
        env,
        counter
      ) do
    with {:ok, item_arg, acc_arg, body} <- two_arg_lambda(lambda),
         {:ok, code, out, counter} <-
           compile_list_foldl_int_range_loop(item_arg, acc_arg, body, acc, list, env, counter) do
      {code, out, counter}
    else
      _ -> compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
        env,
        counter
      ) do
    NativeInt.compile_boxed(%{op: :call, name: "modBy", args: [base, value]}, env, counter)
  end

  def compile(
        %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
        env,
        counter
      ) do
    NativeInt.compile_boxed(%{op: :call, name: "remainderBy", args: [base, value]}, env, counter)
  end

  def compile(
        %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr,
        env,
        counter
      ) do
    if NativeInt.expr?(value, env) do
      {value_code, value_ref, counter} = Host.compile_native_int_expr(value, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
        #{value_code}
          ElmcValue *#{out} = elmc_string_from_native_int(#{value_ref});
      """

      {code, out, next}
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{op: :runtime_call, function: function, args: [left, right]} = expr,
        env,
        counter
      )
      when function in ["elmc_basics_min", "elmc_basics_max"] do
    if NativeInt.expr?(left, env) and NativeInt.expr?(right, env) do
      NativeInt.compile_boxed(
        %{op: :call, name: NativeInt.native_min_max_name(function), args: [left, right]},
        env,
        counter
      )
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(
        %{op: :runtime_call, function: function, args: [value]} = expr,
        env,
        counter
      )
      when function in ["elmc_basics_abs", "elmc_basics_negate"] do
    cond do
      NativeInt.expr?(value, env) ->
        NativeInt.compile_boxed(
          %{op: :call, name: NativeInt.native_unary_int_name(function), args: [value]},
          env,
          counter
        )

      NativeFloat.expr?(expr, env) ->
        NativeFloat.compile_boxed(expr, env, counter)

      true ->
        compile_generic(expr, env, counter)
    end
  end

  def compile(%{op: :runtime_call, function: function, args: [_value]} = expr, env, counter)
      when function in @float_unary_functions do
    if NativeFloat.expr?(expr, env) do
      NativeFloat.compile_boxed(expr, env, counter)
    else
      compile_generic(expr, env, counter)
    end
  end

  def compile(%{op: :runtime_call, function: function, args: args}, env, counter) do
    compile_generic(%{op: :runtime_call, function: function, args: args}, env, counter)
  end

  @spec compile_native_append(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_append(left, right, env, counter) do
    {left_code, left_ref, left_cleanup, counter} = NativeString.compile_expr(left, env, counter)

    {right_code, right_ref, right_cleanup, counter} =
      NativeString.compile_expr(right, env, counter)

    next = counter + 1
    out = "tmp_#{next}"

    releases =
      (left_cleanup ++ right_cleanup)
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{left_code}#{right_code}
      ElmcValue *#{out} = elmc_string_append_native(#{left_ref}, #{right_ref});
      #{releases}
      #{DebugProbes.append_probe(env, "elmc_append", out, next)}
    """

    {code, out, next}
  end

  @spec compile_list_bool_loop(
          String.t(),
          String.t(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defp compile_list_bool_loop(function, arg, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})

    body =
      if map_size(substitutions) > 0 do
        Host.substitute_expr(body, substitutions)
      else
        body
      end

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_hof_cursor_#{next}"
    node = "list_hof_node_#{next}"
    head = "list_hof_head_#{next}"
    result = "list_hof_result_#{next}"
    out = "tmp_#{next}"

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)

    if NativeBool.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeBool.compile_expr(body, body_env, next)
      {initial, break_condition, break_value} = list_loop_polarity(function, body_ref)

      code = """
      #{list_code}
        elmc_int_t #{result} = #{initial};
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
      #{indent_loop_body(body_code)}
          if (#{break_condition}) {
            #{result} = #{break_value};
            break;
          }
          #{cursor} = #{node}->tail;
        }
        ElmcValue *#{out} = elmc_new_bool(#{result});
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp maybe_put_native_int_arg(env, arg, body, head) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})
    usage = Host.native_int_usage(arg, body, module_name, decl_map)

    if usage.total > 0 and usage.boxed == 0 do
      env
      |> EnvBindings.put_native_int_binding(arg, "elmc_as_int(#{head})")
      |> EnvBindings.put_boxed_int_binding(arg, false)
    else
      env
    end
  end

  defp list_loop_polarity("elmc_list_all", body_ref), do: {"1", "!(#{body_ref})", "0"}
  defp list_loop_polarity("elmc_list_any", body_ref), do: {"0", body_ref, "1"}

  defp indent_loop_body(code),
    do: code |> String.trim_trailing() |> String.replace("\n", "\n    ")

  defp two_arg_lambda(%{args: [left, right], body: body})
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp two_arg_lambda(%{args: [left], body: %{op: :lambda, args: [right], body: body}})
       when is_binary(left) and is_binary(right),
       do: {:ok, left, right, body}

  defp two_arg_lambda(_lambda), do: :error

  defp compile_list_map_tuple2_native_int_cursor_loop(left, right, body, list, env, counter) do
    {body, substitutions} = Host.unwrap_let_chain(body, %{})
    body = if map_size(substitutions) > 0, do: Host.substitute_expr(body, substitutions), else: body

    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_map_cursor_#{next}"
    node = "list_map_node_#{next}"
    head = "list_map_head_#{next}"
    dx = "list_map_dx_#{next}"
    dy = "list_map_dy_#{next}"
    item_value = "list_map_item_#{next}"
    cons = "list_map_cons_#{next}"
    rev = "list_map_rev_#{next}"
    out = "tmp_#{next}"

    body_env =
      env
      |> EnvBindings.put_native_int_binding(left, dx)
      |> EnvBindings.put_native_int_binding(right, dy)
      |> EnvBindings.put_boxed_int_binding(left, false)
      |> EnvBindings.put_boxed_int_binding(right, false)
      |> augment_zero_arg_int_constants(body)

    if NativeInt.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

      code = """
    #{list_code}
      ElmcValue *#{rev} = elmc_list_nil();
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head} = #{node}->head;
        ElmcValue *#{left}_tuple = elmc_tuple_first(#{head});
        const elmc_int_t #{dx} = elmc_as_int(#{left}_tuple);
        elmc_release(#{left}_tuple);
        ElmcValue *#{right}_tuple = elmc_tuple_second(#{head});
        const elmc_int_t #{dy} = elmc_as_int(#{right}_tuple);
        elmc_release(#{right}_tuple);
    #{indent_loop_body(body_code)}
        ElmcValue *#{item_value} = elmc_new_int(#{body_ref});
        ElmcValue *#{cons} = elmc_list_cons(#{item_value}, #{rev});
        elmc_release(#{item_value});
        elmc_release(#{rev});
        #{rev} = #{cons};
        #{cursor} = #{node}->tail;
      }
      ElmcValue *#{out} = elmc_list_reverse(#{rev});
      elmc_release(#{rev});
      elmc_release(#{list_var});
    """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp compile_list_map_native_int_cursor_loop(arg, body, list, env, counter) do
    case unwrap_tuple2_lambda_body(body, arg) do
      {:ok, left, right, inner} ->
        compile_list_map_tuple2_native_int_cursor_loop(left, right, inner, list, env, counter)

      :error ->
        {body, substitutions} = Host.unwrap_let_chain(body, %{})
        body = if map_size(substitutions) > 0, do: Host.substitute_expr(body, substitutions), else: body
        compile_list_map_single_native_int_cursor_loop(arg, body, list, env, counter)
    end
  end

  defp unwrap_tuple2_lambda_body(
         %{
           op: :let_in,
           name: left,
           value_expr: first,
           in_expr: %{
             op: :let_in,
             name: right,
             value_expr: second,
             in_expr: inner
           }
         },
         tuple_arg
       ) do
    if tuple_first_of_var?(first, tuple_arg) and tuple_second_of_var?(second, tuple_arg) do
      {:ok, left, right, inner}
    else
      :error
    end
  end

  defp unwrap_tuple2_lambda_body(_, _), do: :error

  defp tuple_first_of_var?(expr, var) do
    case expr do
      %{op: :tuple_first_expr, arg: %{op: :var, name: ^var}} -> true
      %{op: :qualified_call, target: target, args: [%{op: :var, name: ^var}]}
      when target in ["Tuple.first", "Basics.first"] ->
        true

      %{op: :runtime_call, function: "elmc_tuple_first", args: [%{op: :var, name: ^var}]} ->
        true

      _ ->
        false
    end
  end

  defp tuple_second_of_var?(expr, var) do
    case expr do
      %{op: :tuple_second_expr, arg: %{op: :var, name: ^var}} -> true
      %{op: :qualified_call, target: target, args: [%{op: :var, name: ^var}]}
      when target in ["Tuple.second", "Basics.second"] ->
        true

      %{op: :runtime_call, function: "elmc_tuple_second", args: [%{op: :var, name: ^var}]} ->
        true

      _ ->
        false
    end
  end

  defp compile_list_map_single_native_int_cursor_loop(arg, body, list, env, counter) do
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_map_cursor_#{next}"
    node = "list_map_node_#{next}"
    head = "list_map_head_#{next}"
    item_value = "list_map_item_#{next}"
    cons = "list_map_cons_#{next}"
    rev = "list_map_rev_#{next}"
    out = "tmp_#{next}"

    body_env =
      env
      |> Map.put(arg, head)
      |> maybe_put_native_int_arg(arg, body, head)
      |> augment_zero_arg_int_constants(body)

    if NativeInt.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

      code = """
      #{list_code}
        ElmcValue *#{rev} = elmc_list_nil();
        ElmcValue *#{cursor} = #{list_var};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{head} = #{node}->head;
      #{indent_loop_body(body_code)}
          ElmcValue *#{item_value} = elmc_new_int(#{body_ref});
          ElmcValue *#{cons} = elmc_list_cons(#{item_value}, #{rev});
          elmc_release(#{item_value});
          elmc_release(#{rev});
          #{rev} = #{cons};
          #{cursor} = #{node}->tail;
        }
        ElmcValue *#{out} = elmc_list_reverse(#{rev});
        elmc_release(#{rev});
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp augment_zero_arg_int_constants(env, body) do
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    VarAnalysis.used_vars(body)
    |> Enum.reduce(env, fn name, acc ->
      case Map.get(decl_map, {module_name, name}) do
        %{args: [], expr: %{op: :int_literal, value: value}} ->
          EnvBindings.put_native_int_binding(acc, name, Integer.to_string(value))

        _ ->
          acc
      end
    end)
  end

  defp compile_list_map_int_range_loop(arg, body, list, env, counter) do
    with {:ok, range_code, first_ref, last_ref, counter} <- range_bounds(list, env, counter) do
      next = counter + 1
      item_var = "list_map_i_#{next}"
      step_var = "list_map_step_#{next}"
      item_value = "list_map_item_#{next}"
      rev = "list_map_rev_#{next}"
      out = "tmp_#{next}"

      body_env =
        env
        |> EnvBindings.put_native_int_binding(arg, item_var)
        |> EnvBindings.put_boxed_int_binding(arg, false)

      if NativeInt.expr?(body, body_env) do
        {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

        code = """
        #{range_code}
          ElmcValue *#{rev} = elmc_list_nil();
          if (#{first_ref} <= #{last_ref}) {
            elmc_int_t #{step_var} = 1;
            for (elmc_int_t #{item_var} = #{first_ref}; ; #{item_var} += #{step_var}) {
        #{indent_loop_body(body_code)}
              ElmcValue *#{item_value} = elmc_new_int(#{body_ref});
              ElmcValue *#{out} = elmc_list_cons(#{item_value}, #{rev});
              elmc_release(#{item_value});
              elmc_release(#{rev});
              #{rev} = #{out};
              if (#{item_var} == #{last_ref}) break;
            }
          }
          ElmcValue *#{out} = elmc_list_reverse(#{rev});
          elmc_release(#{rev});
        """

        {:ok, code, out, counter}
      else
        :error
      end
    else
      :error -> :error
    end
  end

  defp compile_list_indexed_map_int_loop(index_arg, item_arg, body, list, env, counter) do
    case compile_list_indexed_replace_int(index_arg, item_arg, body, list, env, counter) do
      {:ok, _code, _out, _counter} = ok ->
        ok

      :error ->
        compile_list_indexed_map_int_loop_body(index_arg, item_arg, body, list, env, counter)
    end
  end

  defp compile_list_indexed_replace_int(index_arg, item_arg, body, list, env, counter) do
    with {:ok, target_expr, value_expr} <- indexed_replace_int_pattern(index_arg, item_arg, body),
         true <- NativeInt.expr?(value_expr, env) do
      {target_code, target_ref, counter} = NativeInt.compile_expr(target_expr, env, counter)
      {value_code, value_ref, counter} = NativeInt.compile_expr(value_expr, env, counter)
      {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{target_code}#{value_code}#{list_code}
        ElmcValue *#{out} = elmc_list_replace_nth_int(#{list_var}, #{target_ref}, #{value_ref});
        elmc_release(#{list_var});
      """

      {:ok, code, out, next}
    else
      _ -> :error
    end
  end

  defp indexed_replace_int_pattern(index_arg, item_arg, %{
         op: :if,
         cond: %{op: :compare, kind: :eq, left: left, right: right},
         then_expr: then_expr,
         else_expr: %{op: :var, name: else_name}
       })
       when else_name == item_arg do
    indexed_replace_target(index_arg, left, right, then_expr)
  end

  defp indexed_replace_int_pattern(index_arg, item_arg, %{
         op: :if,
         cond: %{op: :compare, kind: :eq, left: left, right: right},
         then_expr: %{op: :var, name: then_name},
         else_expr: else_expr
       })
       when then_name == item_arg do
    indexed_replace_target(index_arg, left, right, else_expr)
  end

  defp indexed_replace_int_pattern(_index_arg, _item_arg, _body), do: :error

  defp indexed_replace_target(index_arg, %{op: :var, name: index_arg}, target_expr, value_expr),
    do: {:ok, target_expr, value_expr}

  defp indexed_replace_target(index_arg, target_expr, %{op: :var, name: index_arg}, value_expr),
    do: {:ok, target_expr, value_expr}

  defp indexed_replace_target(_index_arg, _left, _right, _value_expr), do: :error

  defp compile_list_indexed_map_int_loop_body(index_arg, item_arg, body, list, env, counter) do
    {list_code, list_var, counter} = Host.compile_expr(list, env, counter)
    next = counter + 1
    cursor = "list_indexed_map_cursor_#{next}"
    node = "list_indexed_map_node_#{next}"
    item_head = "list_indexed_map_head_#{next}"
    index_var = "list_indexed_map_index_#{next}"
    item_value = "list_indexed_map_item_#{next}"
    rev = "list_indexed_map_rev_#{next}"
    out = "tmp_#{next}"

    body_env =
      env
      |> Map.put(item_arg, item_head)
      |> EnvBindings.put_native_int_binding(item_arg, "elmc_as_int(#{item_head})")
      |> EnvBindings.put_boxed_int_binding(item_arg, false)
      |> EnvBindings.put_native_int_binding(index_arg, index_var)
      |> EnvBindings.put_boxed_int_binding(index_arg, false)

    if NativeInt.expr?(body, body_env) do
      {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

      code = """
      #{list_code}
        ElmcValue *#{rev} = elmc_list_nil();
        ElmcValue *#{cursor} = #{list_var};
        elmc_int_t #{index_var} = 0;
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          ElmcValue *#{item_head} = #{node}->head;
      #{indent_loop_body(body_code)}
          ElmcValue *#{item_value} = elmc_new_int(#{body_ref});
          ElmcValue *#{out} = elmc_list_cons(#{item_value}, #{rev});
          elmc_release(#{item_value});
          elmc_release(#{rev});
          #{rev} = #{out};
          #{index_var} += 1;
          #{cursor} = #{node}->tail;
        }
        ElmcValue *#{out} = elmc_list_reverse(#{rev});
        elmc_release(#{rev});
        elmc_release(#{list_var});
      """

      {:ok, code, out, counter}
    else
      :error
    end
  end

  defp compile_list_foldl_int_range_loop(item_arg, acc_arg, body, acc, list, env, counter) do
    with true <- NativeInt.expr?(acc, env),
         {:ok, range_code, first_ref, last_ref, counter} <- range_bounds(list, env, counter) do
      {acc_code, acc_ref, counter} = NativeInt.compile_expr(acc, env, counter)
      next = counter + 1
      item_var = "list_foldl_i_#{next}"
      step_var = "list_foldl_step_#{next}"
      acc_var = "list_foldl_acc_#{next}"
      out = "tmp_#{next}"

      body_env =
        env
        |> EnvBindings.put_native_int_binding(item_arg, item_var)
        |> EnvBindings.put_boxed_int_binding(item_arg, false)
        |> EnvBindings.put_native_int_binding(acc_arg, acc_var)
        |> EnvBindings.put_boxed_int_binding(acc_arg, false)

      if NativeInt.expr?(body, body_env) do
        {body_code, body_ref, counter} = NativeInt.compile_expr(body, body_env, next)

        code = """
        #{range_code}#{acc_code}
          elmc_int_t #{acc_var} = #{acc_ref};
          if (#{first_ref} <= #{last_ref}) {
            elmc_int_t #{step_var} = 1;
            for (elmc_int_t #{item_var} = #{first_ref}; ; #{item_var} += #{step_var}) {
        #{indent_loop_body(body_code)}
              #{acc_var} = #{body_ref};
              if (#{item_var} == #{last_ref}) break;
            }
          }
          ElmcValue *#{out} = elmc_new_int(#{acc_var});
        """

        {:ok, code, out, counter}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp range_bounds(
         %{op: :runtime_call, function: "elmc_list_range", args: [first, last]},
         env,
         counter
       ) do
    {first_code, first_ref, counter} = NativeInt.compile_expr(first, env, counter)
    {last_code, last_ref, counter} = NativeInt.compile_expr(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp range_bounds(%{op: :qualified_call, target: target, args: [first, last]}, env, counter)
       when target in ["List.range", "Elm.Kernel.List.range"] do
    {first_code, first_ref, counter} = NativeInt.compile_expr(first, env, counter)
    {last_code, last_ref, counter} = NativeInt.compile_expr(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp range_bounds(%{op: :call, name: "range", args: [first, last]}, env, counter) do
    {first_code, first_ref, counter} = NativeInt.compile_expr(first, env, counter)
    {last_code, last_ref, counter} = NativeInt.compile_expr(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  defp range_bounds(_expr, _env, _counter), do: :error

  @spec compile_generic(
          %{
            required(:op) => :runtime_call,
            required(:function) => String.t(),
            required(:args) => [Types.ir_expr()]
          },
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_generic(%{op: :runtime_call, function: function, args: args}, env, counter) do
    {arg_code, arg_vars, counter} =
      Enum.reduce(args, {"", [], counter}, fn arg_expr, {code_acc, vars_acc, c} ->
        {code, var, c2} = Host.compile_expr(arg_expr, env, c)
        {code_acc <> "\n  " <> code, vars_acc ++ [var], c2}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    call_args = Enum.join(arg_vars, ", ")

    releases =
      arg_vars
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      ElmcValue *#{out} = #{function}(#{call_args});
      #{releases}
      #{Host.face_ops_append_probe(env, function, out, next)}
    """

    {code, out, next}
  end
end
