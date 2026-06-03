defmodule Elmc.Backend.CCodegen.RuntimeCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Float, as: NativeFloat
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Types

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
      compile_generic(%{op: :runtime_call, function: "elmc_append", args: [left, right]}, env, counter)
    end
  end

  def compile(%{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]}, env, counter) do
    NativeInt.compile_boxed(%{op: :call, name: "modBy", args: [base, value]}, env, counter)
  end

  def compile(
        %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
        env,
        counter
      ) do
    NativeInt.compile_boxed(%{op: :call, name: "remainderBy", args: [base, value]}, env, counter)
  end

  def compile(%{op: :runtime_call, function: "elmc_string_from_int", args: [value]} = expr, env, counter) do
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
    {right_code, right_ref, right_cleanup, counter} = NativeString.compile_expr(right, env, counter)
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

  @spec compile_generic(
          %{required(:op) => :runtime_call, required(:function) => String.t(), required(:args) => [Types.ir_expr()]},
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
