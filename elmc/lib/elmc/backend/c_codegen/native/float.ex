defmodule Elmc.Backend.CCodegen.Native.Float do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @type compile_result :: Types.native_scalar_compile_result()

  @spec compile_expr(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  def compile_expr(%{op: :float_literal, value: value}, _env, counter) do
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {"", float_val, counter}
  end

  def compile_expr(%{op: op, value: value}, _env, counter) when op in [:int_literal, :char_literal],
    do: {"", "(double)#{value}", counter}

  def compile_expr(%{op: :field_access, arg: arg, field: field}, env, counter)
      when is_binary(arg) do
    case Map.fetch(env, arg) do
      {:ok, source} when is_binary(source) ->
        getter =
          RecordFields.get_float_expr(source, field, Host.record_shape_for_var(env, arg))

        {"", getter, counter}

      :error ->
        compile_fallback(%{op: :field_access, arg: arg, field: field}, env, counter)
    end
  end

  def compile_expr(%{op: :field_access, arg: %{op: :var, name: name}, field: field}, env, counter) do
    compile_expr(%{op: :field_access, arg: name, field: field}, env, counter)
  end

  def compile_expr(%{op: :var, name: name} = expr, env, counter) do
    case EnvBindings.native_float_binding(env, name) do
      native_ref when is_binary(native_ref) ->
        {"", native_ref, counter}

      nil ->
        case EnvBindings.native_int_binding(env, name) do
          native_ref when is_binary(native_ref) ->
            {"", "(double)#{native_ref}", counter}

          nil ->
            compile_fallback(expr, env, counter)
        end
    end
  end

  def compile_expr(%{op: :call, name: name, args: [left, right]}, env, counter)
      when name in ["__add__", "__sub__", "__mul__", "__fdiv__"] do
    op = %{"__add__" => "+", "__sub__" => "-", "__mul__" => "*", "__fdiv__" => "/"}[name]
    {left_code, left_ref, counter} = compile_expr(left, env, counter)
    {right_code, right_ref, counter} = compile_expr(right, env, counter)
    {left_code <> right_code, "(#{left_ref} #{op} #{right_ref})", counter}
  end

  def compile_expr(%{op: :runtime_call, function: "elmc_basics_to_float", args: [value]}, env, counter) do
    {value_code, value_ref, counter} = Host.compile_native_int_expr(value, env, counter)
    {value_code, "(double)#{value_ref}", counter}
  end

  def compile_expr(%{op: :runtime_call, function: function, args: [value]}, env, counter)
      when function in [
             "elmc_basics_sin",
             "elmc_basics_cos",
             "elmc_basics_tan",
             "elmc_basics_sqrt"
           ] do
    {value_code, value_ref, counter} = compile_expr(value, env, counter)

    native_function =
      %{
        "elmc_basics_sin" => "elmc_basics_sin_double",
        "elmc_basics_cos" => "elmc_basics_cos_double",
        "elmc_basics_tan" => "elmc_basics_tan_double",
        "elmc_basics_sqrt" => "elmc_basics_sqrt_double"
      }
      |> Map.fetch!(function)

    {value_code, "#{native_function}(#{value_ref})", counter}
  end

  def compile_expr(%{op: :runtime_call, function: "elmc_basics_abs", args: [value]}, env, counter) do
    {value_code, value_ref, counter} = compile_expr(value, env, counter)
    {value_code, "(#{value_ref} < 0 ? -#{value_ref} : #{value_ref})", counter}
  end

  def compile_expr(%{op: :runtime_call, function: "elmc_basics_negate", args: [value]}, env, counter) do
    {value_code, value_ref, counter} = compile_expr(value, env, counter)
    {value_code, "(-#{value_ref})", counter}
  end

  def compile_expr(%{op: :qualified_call, target: target, args: args} = expr, env, counter) do
    case Host.special_value_from_target(target, args) do
      nil ->
        case Host.qualified_builtin_operator_name(target) do
          builtin when builtin in ["__add__", "__sub__", "__mul__", "__fdiv__"] ->
            compile_expr(%{op: :call, name: builtin, args: args}, env, counter)

          _ ->
            compile_fallback(expr, env, counter)
        end

      rewritten ->
        compile_expr(rewritten, env, counter)
    end
  end

  def compile_expr(expr, env, counter), do: compile_fallback(expr, env, counter)

  @spec compile_boxed(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {String.t(), String.t(), Types.compile_counter()}
  def compile_boxed(expr, env, counter) do
    {code, value_ref, counter} = compile_expr(expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {
      """
      #{code}
        #{ValueSlots.boxed_decl(out, "elmc_new_float((double)#{value_ref})", env)}
      """,
      out,
      next
    }
  end

  @spec expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def expr?(%{op: :float_literal}, _env), do: true
  def expr?(%{op: op}, _env) when op in [:int_literal, :char_literal], do: true

  def expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name),
    do:
      is_binary(EnvBindings.native_float_binding(env, name)) or
        is_binary(EnvBindings.native_int_binding(env, name))

  def expr?(%{op: :field_access, arg: arg, field: field}, env),
    do: RecordFields.float_field?(env, arg, field)

  def expr?(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env),
    do: expr?(then_expr, env) and expr?(else_expr, env)

  def expr?(%{op: :call, name: name, args: [left, right]}, env)
      when name in ["__add__", "__sub__", "__mul__", "__fdiv__"] do
    expr?(left, env) and expr?(right, env)
  end

  def expr?(%{op: :runtime_call, function: "elmc_basics_to_float", args: [value]}, env),
    do: Host.native_int_expr?(value, env)

  def expr?(%{op: :runtime_call, function: function, args: [value]}, env)
      when function in [
             "elmc_basics_sin",
             "elmc_basics_cos",
             "elmc_basics_tan",
             "elmc_basics_sqrt",
             "elmc_basics_abs",
             "elmc_basics_negate"
           ] do
    expr?(value, env)
  end

  def expr?(%{op: :qualified_call, target: target, args: args}, env) do
    case Host.special_value_from_target(target, args) do
      %{op: op} when op in [:float_literal, :int_literal, :char_literal] ->
        true

      nil ->
        Host.qualified_builtin_operator_member?(target, ["__add__", "__sub__", "__mul__", "__fdiv__"]) and
          length(args) == 2 and
          Enum.all?(args, &expr?(&1, env))

      expr ->
        expr?(expr, env)
    end
  end

  def expr?(_expr, _env), do: false

  @spec compile_fallback(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          compile_result()
  defp compile_fallback(expr, env, counter) do
    {code, var, counter} = Host.compile_expr(expr, env, counter)
    next = counter + 1
    out = "native_f_#{next}"

    {
      """
      #{code}
        const double #{out} = elmc_as_float(#{var});
        elmc_release(#{var});
      """,
      out,
      next
    }
  end
end
