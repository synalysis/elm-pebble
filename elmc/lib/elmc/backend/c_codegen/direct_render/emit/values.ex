defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Values do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec range_bounds(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), String.t(), Types.compile_counter()} | :error
  def range_bounds(
        %{op: :qualified_call, target: target, args: [first, last]},
        env,
        counter
      )
      when target in ["List.range", "Elm.Kernel.List.range"] do
    {first_code, first_ref, counter} = int_value(first, env, counter)
    {last_code, last_ref, counter} = int_value(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  def range_bounds(%{op: :call, name: "range", args: [first, last]}, env, counter) do
    {first_code, first_ref, counter} = int_value(first, env, counter)
    {last_code, last_ref, counter} = int_value(last, env, counter)
    {:ok, first_code <> last_code, first_ref, last_ref, counter}
  end

  def range_bounds(_expr, _env, _counter), do: :error

  @spec int_value(Types.ir_expr() | nil, Types.compile_env(), Types.compile_counter()) ::
          Types.direct_int_compile_result()
  def int_value(nil, _env, counter), do: {"", "0", counter}

  def int_value(%{op: :int_literal} = expr, _env, counter),
    do: {"", "#{Host.int_literal_compile_value(expr)}", counter}

  def int_value(%{op: :c_int_expr, value: value}, _env, counter) when is_binary(value),
    do: {"", value, counter}

  def int_value(
        %{op: :direct_native_if, cond: cond, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      ) do
    {cond_code, cond_ref, cond_release, counter} =
      if Host.native_bool_expr?(cond, env) do
        {code, ref, c} = Host.compile_native_bool_expr(cond, env, counter)
        {code, ref, "", c}
      else
        {code, var, c} = Host.compile_expr(cond, env, counter)
        {code, "elmc_as_int(#{var}) != 0", "  elmc_release(#{var});", c}
      end

    {then_code, then_ref, counter} = int_value(then_expr, env, counter)
    {else_code, else_ref, counter} = int_value(else_expr, env, counter)
    next = counter + 1
    value_ref = "direct_native_if_#{next}"

    code = """
    #{cond_code}#{then_code}#{else_code}#{cond_release}
      const elmc_int_t #{value_ref} = (#{cond_ref}) ? #{then_ref} : #{else_ref};
    """

    {code, value_ref, next}
  end

  def int_value(%{op: :char_literal, value: value}, _env, counter),
    do: {"", "#{value}", counter}

  def int_value(%{op: :var, name: name} = expr, env, counter) do
    cond do
      is_binary(EnvBindings.native_int_binding(env, name)) ->
        {"", EnvBindings.native_int_binding(env, name), counter}

      true ->
        case Map.fetch(env, name) do
          {:ok, {:direct_fragment, fragment}} ->
            int_value(fragment, env, counter)

          {:ok, source} when is_binary(source) ->
            {"", "elmc_as_int(#{source})", counter}

          _ ->
            case Elmc.Backend.CCodegen.ConstantInt.native_ref(expr, env) do
              {:ok, ref} -> {"", ref, counter}
              :error -> runtime_int_value(expr, env, counter)
            end
        end
    end
  end

  def int_value(%{op: :call, name: name, args: args} = expr, env, counter) do
    cond do
      int_hoistable_zero_arg_call?(expr, env) ->
        int_hoisted_zero_arg_value(expr, env, counter)

      true ->
        case int_builtin(name, args, env, counter) do
          {:ok, code, value, counter} -> {code, value, counter}
          :error -> runtime_int_value(expr, env, counter)
        end
    end
  end

  def int_value(%{op: :qualified_call, target: target, args: args} = expr, env, counter) do
    if int_hoistable_zero_arg_call?(expr, env) do
      int_hoisted_zero_arg_value(expr, env, counter)
    else
      int_value_qualified_call(target, args, expr, env, counter)
    end
  end

  def int_value(%{op: :constructor_call, target: target, args: args}, env, counter) do
    if Host.resource_union_constructor?(target, args) do
      {"", "#{Host.pebble_resource_slot_index(target)}", counter}
    else
      runtime_int_value(
        %{op: :constructor_call, target: target, args: args},
        env,
        counter
      )
    end
  end

  def int_value(%{op: :qualified_ref, target: target}, env, counter) when is_binary(target) do
    resource_slot_int_value(target, env, counter)
  end

  def int_value(%{op: :qualified_var, target: target}, env, counter) when is_binary(target) do
    resource_slot_int_value(target, env, counter)
  end

  def int_value(%{op: :field_access, arg: %{op: :var, name: name}, field: field}, env, counter) do
    case Map.get(env, name) do
      {:native_record, fields} ->
        case Map.fetch(fields, field) do
          {:ok, native_ref} -> {"", native_ref, counter}
          :error -> {"", "0", counter}
        end

      {:direct_fragment, fragment} ->
        int_value(%{op: :field_access, arg: fragment, field: field}, env, counter)

      _ ->
        int_value_field_access_fallback(%{op: :var, name: name}, field, env, counter)
    end
  end

  def int_value(%{op: :field_access, arg: arg, field: field}, env, counter) do
    source =
      case arg do
        %{op: :var, name: name} ->
          case Map.get(env, name) do
            {:direct_fragment, fragment} -> fragment
            _ -> arg
          end

        _ ->
          arg
      end

    int_value_field_access_fallback(source, field, env, counter)
  end

  def int_value(expr, env, counter), do: runtime_int_value(expr, env, counter)

  defp resource_slot_int_value(target, env, counter) when is_binary(target) do
    if Host.resource_union_constructor?(target, []) do
      {"", "#{Host.pebble_resource_slot_index(target)}", counter}
    else
      runtime_int_value(%{op: :qualified_ref, target: target}, env, counter)
    end
  end

  defp int_hoistable_zero_arg_call?(%{op: :call, args: []}, env),
    do: Host.hoisted_native_ints_enabled?(env)

  defp int_hoistable_zero_arg_call?(%{op: :qualified_call, target: target, args: []}, env)
       when is_binary(target) do
    Host.hoisted_native_ints_enabled?(env) and
      is_nil(Host.special_value_from_target(target, [])) and
      zero_arg_native_int_call?(%{op: :qualified_call, target: target, args: []}, env)
  end

  defp int_hoistable_zero_arg_call?(_, _env), do: false

  defp int_hoisted_zero_arg_value(expr, env, counter) do
    case Host.hoisted_native_int_lookup(env, expr) do
      {:ok, ref} ->
        {"", ref, counter}

      :error ->
        case inline_zero_arg_native_int_call(expr, env, counter) do
          {:ok, code, ref, counter} ->
            {code, ref, counter}

          :error ->
            case int_builtin(Map.get(expr, :name), Map.get(expr, :args, []), env, counter) do
              {:ok, code, value, counter} ->
                {code, value, counter}

              :error ->
                Host.compile_native_int_fallback(expr, env, counter)
            end
        end
    end
  end

  defp inline_zero_arg_native_int_call(expr, env, counter) do
    case zero_arg_native_int_call_target_key(expr, env) do
      target_key when not is_nil(target_key) ->
        Host.compile_native_int_inline_function(target_key, [], env, counter)

      _ ->
        :error
    end
  end

  defp zero_arg_native_int_call_target_key(%{op: :call, name: name, args: []}, env)
       when is_binary(name) do
    {Map.get(env, :__module__, "Main"), name}
  end

  defp zero_arg_native_int_call_target_key(%{op: :qualified_call, target: target, args: []}, _env)
       when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Util.split_qualified_function_target()
  end

  defp zero_arg_native_int_call_target_key(_, _), do: nil

  @spec int_value_qualified_call(
          String.t(),
          [Types.ir_expr()],
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_int_compile_result()
  defp int_value_qualified_call(target, args, _expr, env, counter) do
    case Host.special_value_from_target(target, args) do
      %{op: :int_literal, value: value} ->
        {"", "#{value}", counter}

      %{op: :field_access} = field ->
        int_value(field, env, counter)

      nil ->
        cond do
          Host.resource_union_constructor?(target, args) ->
            {"", "#{Host.pebble_resource_slot_index(target)}", counter}

          true ->
            with builtin when not is_nil(builtin) <- Host.qualified_builtin_operator_name(target),
                 {:ok, code, value, counter} <- int_builtin(builtin, args, env, counter) do
              {code, value, counter}
            else
              _ ->
                runtime_int_value(
                  %{op: :qualified_call, target: target, args: args},
                  env,
                  counter
                )
            end
        end

      expr ->
        int_value(expr, env, counter)
    end
  end

  @spec int_value_field_access_fallback(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_int_compile_result()
  defp int_value_field_access_fallback(arg, field, env, counter) do
    cond do
      field_expr = Host.record_field_expr(arg, field) ->
        int_value(field_expr, env, counter)

      field_expr = Host.inline_record_field_expr(arg, field, env) ->
        int_value(field_expr, env, counter)

      true ->
        runtime_int_value(%{op: :field_access, arg: arg, field: field}, env, counter)
    end
  end

  @spec int_builtin(String.t(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.direct_int_builtin_result()
  defp int_builtin(name, [left, right], env, counter)
       when name in ["__add__", "__sub__", "__mul__"] do
    op = %{"__add__" => "+", "__sub__" => "-", "__mul__" => "*"}[name]
    {left_code, left_value, counter} = int_value(left, env, counter)
    {right_code, right_value, counter} = int_value(right, env, counter)
    {:ok, left_code <> right_code, "(#{left_value} #{op} #{right_value})", counter}
  end

  defp int_builtin("__idiv__", [left, right], env, counter) do
    {left_code, left_value, counter} = int_value(left, env, counter)

    case static_nonzero_int_value(right, env) do
      value when is_integer(value) ->
        {:ok, left_code, "(#{left_value} / #{value})", counter}

      nil ->
        {right_code, right_value, counter} = int_value(right, env, counter)

        case parse_compile_time_int_ref(right_value) do
          value when is_integer(value) and value != 0 ->
            {:ok, left_code <> right_code, "(#{left_value} / #{value})", counter}

          _ ->
            next = counter + 1
            denom = "direct_den_#{next}"

            code = """
            #{left_code}#{right_code}
              elmc_int_t #{denom} = #{right_value};
            """

            {:ok, code, "(#{denom} == 0 ? 0 : (#{left_value} / #{denom}))", next}
        end
    end
  end

  defp int_builtin("modBy", [base, value], env, counter) do
    case static_nonzero_int_value(base, env) do
      base_value when is_integer(base_value) ->
        {value_code, value_value, counter} = int_value(value, env, counter)
        next = counter + 1
        out = "direct_mod_#{next}"
        correction = abs(base_value)

        code = """
        #{value_code}
          elmc_int_t #{out} = #{value_value} % #{base_value};
          if (#{out} < 0) #{out} += #{correction};
        """

        {:ok, code, out, next}

      nil ->
        {base_code, base_value, counter} = int_value(base, env, counter)
        {value_code, value_value, counter} = int_value(value, env, counter)
        next = counter + 1
        base_var = "direct_mod_base_#{next}"

        code = """
        #{base_code}#{value_code}
          elmc_int_t #{base_var} = #{base_value};
        """

        {:ok, code, "(#{base_var} == 0 ? 0 : (#{value_value} % #{base_var}))", next}
    end
  end

  defp int_builtin("max", [left, right], env, counter) do
    int_min_max_builtin("max", left, right, env, counter)
  end

  defp int_builtin("min", [left, right], env, counter) do
    int_min_max_builtin("min", left, right, env, counter)
  end

  defp int_builtin("clamp", [low, high, value], env, counter) do
    {low_code, low_value, counter} = int_value(low, env, counter)
    {high_code, high_value, counter} = int_value(high, env, counter)
    {value_code, value_value, counter} = int_value(value, env, counter)
    next = counter + 1
    low_var = "direct_low_#{next}"
    high_var = "direct_high_#{next}"
    value_var = "direct_value_#{next}"

    code = """
    #{low_code}#{high_code}#{value_code}
      int64_t #{low_var} = #{low_value};
      int64_t #{high_var} = #{high_value};
      int64_t #{value_var} = #{value_value};
    """

    {:ok, code,
     "(#{value_var} < #{low_var} ? #{low_var} : (#{value_var} > #{high_var} ? #{high_var} : #{value_var}))",
     next}
  end

  defp int_builtin(_name, _args, _env, _counter), do: :error

  defp static_nonzero_int_value(expr, env) do
    case Elmc.Backend.CCodegen.ConstantInt.literal_value(expr, env) do
      {:ok, value} when is_integer(value) and value != 0 -> value
      _ -> nil
    end
  end

  defp parse_compile_time_int_ref(ref) when is_binary(ref) do
    case Util.parse_compile_time_int_ref(ref) do
      value when is_integer(value) and value != 0 -> value
      _ -> nil
    end
  end

  defp parse_compile_time_int_ref(_ref), do: nil

  defp int_min_max_builtin(name, left, right, env, counter) do
    expr = %{op: :call, name: name, args: [left, right]}

    if Host.hoisted_native_ints_enabled?(env) do
      {code, ref, counter} = Host.compile_native_int_expr(expr, env, counter)
      {:ok, code, ref, counter}
    else
      op = if name == "min", do: "<=", else: ">="
      int_min_max(left, right, op, env, counter)
    end
  end

  defp int_min_max(left, right, op, env, counter) do
    {left_code, left_value, counter} = int_value(left, env, counter)
    {right_code, right_value, counter} = int_value(right, env, counter)
    next = counter + 1
    left_var = "direct_left_#{next}"
    right_var = "direct_right_#{next}"

    code = """
    #{left_code}#{right_code}
      int64_t #{left_var} = #{left_value};
      int64_t #{right_var} = #{right_value};
    """

    {:ok, code, "(#{left_var} #{op} #{right_var} ? #{left_var} : #{right_var})", next}
  end

  @spec runtime_int_value(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.direct_int_compile_result()
  defp runtime_int_value(expr, env, counter) do
    case Host.hoisted_native_int_lookup(env, expr) do
      {:ok, ref} ->
        {"", ref, counter}

      :error ->
        cond do
          Host.native_int_expr?(expr, env) ->
            Host.compile_native_int_expr(expr, env, counter)

          Host.hoisted_native_ints_enabled?(env) and zero_arg_native_int_call?(expr, env) ->
            Host.compile_native_int_fallback(expr, env, counter)

          true ->
            {expr_code, expr_var, counter} = Host.compile_expr(expr, env, counter)
            next = counter + 1
            int_var = "direct_i_#{next}"

            {
              """
              #{expr_code}
                int64_t #{int_var} = elmc_as_int(#{expr_var});
                elmc_release(#{expr_var});
              """,
              int_var,
              next
            }
        end
    end
  end

  @spec zero_arg_native_int_call?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defp zero_arg_native_int_call?(%{op: :call, name: name, args: []}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    target_key = {module_name, name}

    Host.typed_function_return?(target_key, env, 0, "Int") or
      zero_arg_declared_int_function?(target_key, env)
  end

  defp zero_arg_native_int_call?(%{op: :qualified_call, target: target, args: []}, env)
       when is_binary(target) do
    case Util.split_qualified_function_target(Host.normalize_special_target(target)) do
      target_key when not is_nil(target_key) ->
        Host.typed_function_return?(target_key, env, 0, "Int")

      nil ->
        false
    end
  end

  defp zero_arg_native_int_call?(_, _), do: false

  defp zero_arg_declared_int_function?(target_key, env) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target_key) do
      %{args: [], type: type} when is_binary(type) ->
        type == "Int" or String.starts_with?(type, "Int ")

      _ ->
        false
    end
  end
end
