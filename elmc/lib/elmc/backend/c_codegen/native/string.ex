defmodule Elmc.Backend.CCodegen.Native.String do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_string_compile_result()
  def compile_expr(%{op: :string_literal, value: value}, _env, counter) do
    {"", "\"#{Util.escape_c_string(value)}\"", [], counter}
  end

  def compile_expr(%{op: :var, name: name} = expr, env, counter) do
    case EnvBindings.native_string_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, [], counter}

      nil ->
        case Map.fetch(env, name) do
          {:ok, source} when is_binary(source) ->
            next = counter + 1
            out = "native_string_#{next}"
            {value_lines, value_cleanup} = value_code(expr, env, source, out)
            {value_lines, out, value_cleanup, next}

          _ ->
            compile_fallback(expr, env, counter)
        end
    end
  end

  def compile_expr(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr} = expr,
        env,
        counter
      ) do
    if expr?(then_expr, env) and expr?(else_expr, env) do
      {cond_code, cond_ref, counter} = Host.compile_native_bool_expr(cond_expr, env, counter)
      {then_code, then_ref, _then_cleanup, counter} = compile_expr(then_expr, env, counter)
      {else_code, else_ref, _else_cleanup, counter} = compile_expr(else_expr, env, counter)
      next = counter + 1
      out = "native_string_if_#{next}"

      code = """
      #{cond_code}#{then_code}#{else_code}
        const char *#{out} = #{cond_ref} ? #{then_ref} : #{else_ref};
      """

      {code, out, [], next}
    else
      compile_fallback(expr, env, counter)
    end
  end

  def compile_expr(%{op: :qualified_call, target: target, args: args} = expr, env, counter) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> compile_fallback(expr, env, counter)
      rewritten -> compile_expr(rewritten, env, counter)
    end
  end

  def compile_expr(
        %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr,
        env,
        counter
      ) do
    if Host.native_int_expr?(value, env) do
      {value_code, value_ref, counter} = Host.compile_native_int_expr(value, env, counter)
      next = counter + 1
      buffer = "native_string_buf_#{next}"
      out = "native_string_#{next}"

      code = """
      #{value_code}
        char #{buffer}[32];
        snprintf(#{buffer}, sizeof(#{buffer}), "%lld", (long long)#{value_ref});
        const char *#{out} = #{buffer};
      """

      {code, out, [], next}
    else
      compile_fallback(expr, env, counter)
    end
  end

  def compile_expr(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]} = expr,
        env,
        counter
      ) do
    if expr?(left, env) and expr?(right, env) do
      {left_code, left_ref, left_cleanup, counter} = compile_expr(left, env, counter)
      {right_code, right_ref, right_cleanup, counter} = compile_expr(right, env, counter)
      next = counter + 1
      buffer = "native_string_buf_#{next}"
      out = "native_string_#{next}"

      code = """
      #{left_code}#{right_code}
        char #{buffer}[96];
        int #{buffer}_i = 0;
        const char *#{buffer}_left = #{left_ref};
        while (#{buffer}_left && #{buffer}_left[#{buffer}_i] && #{buffer}_i < (int)sizeof(#{buffer}) - 1) {
          #{buffer}[#{buffer}_i] = #{buffer}_left[#{buffer}_i];
          #{buffer}_i++;
        }
        const char *#{buffer}_right = #{right_ref};
        int #{buffer}_right_i = 0;
        while (#{buffer}_right && #{buffer}_right[#{buffer}_right_i] && #{buffer}_i < (int)sizeof(#{buffer}) - 1) {
          #{buffer}[#{buffer}_i] = #{buffer}_right[#{buffer}_right_i];
          #{buffer}_i++;
          #{buffer}_right_i++;
        }
        #{buffer}[#{buffer}_i] = '\\0';
        const char *#{out} = #{buffer};
      """

      {code, out, left_cleanup ++ right_cleanup, next}
    else
      compile_fallback(expr, env, counter)
    end
  end

  def compile_expr(%{op: :call, name: "__append__", args: [left, right]}, env, counter) do
    compile_expr(
      %{op: :runtime_call, function: "elmc_append", args: [left, right]},
      env,
      counter
    )
  end

  def compile_expr(expr, env, counter), do: compile_fallback(expr, env, counter)

  @spec expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def expr?(%{op: :string_literal}, _env), do: true

  def expr?(%{op: :var, name: name} = expr, env)
      when is_binary(name) or is_atom(name),
      do:
        is_binary(EnvBindings.native_string_binding(env, name)) or
          EnvBindings.boxed_string_binding?(env, name) or
          TypedReturn.string_expr?(expr, env)

  def expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: expr?(then_expr, env) and expr?(else_expr, env)

  def expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> TypedReturn.string_expr?(%{op: :qualified_call, target: target, args: args}, env)
      rewritten -> expr?(rewritten, env)
    end
  end

  def expr?(%{op: :runtime_call, function: "elmc_string_from_int", args: [value]}, env),
    do: Host.native_int_expr?(value, env)

  def expr?(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env),
    do: expr?(left, env) and expr?(right, env)

  def expr?(%{op: :call, name: "__append__", args: [left, right]}, env),
    do: expr?(left, env) and expr?(right, env)

  def expr?(%{op: :call} = expr, env), do: TypedReturn.string_expr?(expr, env)

  def expr?(_expr, _env), do: false

  @spec boxed_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def boxed_expr?(%{op: :string_literal}, _env), do: true

  def boxed_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: boxed_expr?(then_expr, env) and boxed_expr?(else_expr, env)

  def boxed_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do:
      EnvBindings.boxed_string_binding?(env, name) or
        TypedReturn.string_expr?(%{op: :var, name: name}, env)

  def boxed_expr?(%{op: :runtime_call, function: "elmc_string_from_int", args: [value]}, env),
    do: Host.native_int_expr?(value, env)

  def boxed_expr?(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env),
    do: expr?(left, env) and expr?(right, env)

  def boxed_expr?(expr, env), do: TypedReturn.string_expr?(expr, env)

  @spec boxed_non_null_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def boxed_non_null_expr?(%{op: :int_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :string_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :char_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :float_literal}, _env), do: true
  def boxed_non_null_expr?(%{op: :compare}, _env), do: true

  def boxed_non_null_expr?(%{op: :call, name: name, args: [_left, _right]}, _env)
      when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"],
      do: true

  def boxed_non_null_expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: boxed_non_null_expr?(then_expr, env) and boxed_non_null_expr?(else_expr, env)

  def boxed_non_null_expr?(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil ->
        Host.qualified_builtin_operator_member?(Host.normalize_special_target(target), [
          "__eq__",
          "__neq__",
          "__lt__",
          "__lte__",
          "__gt__",
          "__gte__"
        ]) and length(args || []) == 2

      rewritten ->
        boxed_non_null_expr?(rewritten, env)
    end
  end

  def boxed_non_null_expr?(%{op: :constructor_call, target: target, args: args}, env)
      when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil -> false
      rewritten -> boxed_non_null_expr?(rewritten, env)
    end
  end

  def boxed_non_null_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do: EnvBindings.boxed_int_binding?(env, name) or EnvBindings.boxed_string_binding?(env, name)

  def boxed_non_null_expr?(
        %{op: :runtime_call, function: "elmc_string_from_int", args: [value]},
        env
      ),
      do: Host.native_int_expr?(value, env)

  def boxed_non_null_expr?(
        %{op: :runtime_call, function: "elmc_append", args: [left, right]},
        env
      ),
      do: expr?(left, env) and expr?(right, env)

  def boxed_non_null_expr?(_expr, _env), do: false

  @spec compile_fallback(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.native_string_compile_result()
  defp compile_fallback(expr, env, counter) do
    {code, var, counter} = Host.compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_string_#{next}"
    {value_lines, value_cleanup} = value_code(expr, env, var, out)

    {
      """
      #{code}
      #{value_lines}
      """,
      out,
      [var | value_cleanup],
      next
    }
  end

  @spec value_code(Types.ir_expr(), Types.compile_env(), String.t(), String.t()) ::
          {String.t(), [String.t()]}
  defp value_code(expr, env, var, out) do
    cond do
      native_string_call_expr?(expr, env) ->
        {
          """
            const char *#{out} =
              (#{var} && #{var}->tag == ELMC_TAG_STRING && #{var}->payload)
                ? (const char *)#{var}->payload
                : "";
          """,
          []
        }

      TypedReturn.string_expr?(expr, env) ->
        boxed = "#{out}_boxed"

        {
          """
            ElmcValue *#{boxed} = NULL;
            const char *#{out} = "";
            if (#{var} && #{var}->tag == ELMC_TAG_STRING && #{var}->payload) {
              #{out} = (const char *)#{var}->payload;
            } else if (#{var} && #{var}->tag == ELMC_TAG_LIST) {
              #{boxed} = elmc_string_from_list(#{var});
              #{out} = (#{boxed} && #{boxed}->payload) ? (const char *)#{boxed}->payload : "";
            }
          """,
          [boxed]
        }

      true ->
        {
          """
            const char *#{out} =
              (#{var} && #{var}->tag == ELMC_TAG_STRING && #{var}->payload)
                ? (const char *)#{var}->payload
                : "";
          """,
          []
        }
    end
  end

  defp native_string_call_expr?(expr, env) do
    case expr do
      %{op: :call} -> TypedReturn.string_expr?(expr, env)
      %{op: :qualified_call} -> TypedReturn.string_expr?(expr, env)
      _ -> false
    end
  end
end
