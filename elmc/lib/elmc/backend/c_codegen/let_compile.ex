defmodule Elmc.Backend.CCodegen.LetCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LetAnalysis
  alias Elmc.Backend.CCodegen.LetRecCompile
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Native.UsageAnalysis, as: NativeUsageAnalysis
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec compile(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  @spec compile(Types.ir_let_in_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :let_in} = expr, env, counter) do
    {bindings, body} = flatten_let_chain(expr)

    if length(bindings) > 1 and LetRecCompile.cyclic_bindings?(bindings) do
      LetRecCompile.compile(bindings, body, env, counter)
    else
      %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = expr
      compile(name, value_expr, in_expr, env, counter)
    end
  end

  def compile(name, value_expr, in_expr, env, counter) do
    cond do
      NativeUsageAnalysis.bool_let?(name, value_expr, in_expr, env) ->
        compile_native_bool_let(name, value_expr, in_expr, env, counter)

      NativeUsageAnalysis.pebble_angle_let?(name, value_expr, in_expr) ->
        compile_pebble_angle_let(name, value_expr, in_expr, env, counter)

      NativeUsageAnalysis.float_let?(name, value_expr, in_expr, env) ->
        compile_native_float_let(name, value_expr, in_expr, env, counter)

      NativeUsageAnalysis.int_let?(name, value_expr, in_expr, env) ->
        compile_native_int_let(name, value_expr, in_expr, env, counter)

      NativeUsageAnalysis.string_let?(name, value_expr, in_expr, env) ->
        compile_native_string_let(name, value_expr, in_expr, env, counter)

      true ->
        compile_boxed_let(name, value_expr, in_expr, env, counter)
    end
  end

  @spec compile_native_bool_let(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_bool_let(name, value_expr, in_expr, env, counter) do
    {value_code, value_ref, counter} = Host.compile_native_bool_expr(value_expr, env, counter)
    next = counter + 1
    native_var = "native_bool_#{Util.safe_c_suffix(name)}_#{next}"
    before_probe = DebugProbes.let_probe(env, name, :before)
    after_probe = DebugProbes.let_probe(env, name, :after)

    body_env =
      env
      |> Map.delete(name)
      |> EnvBindings.remove_native_int_binding(name)
      |> EnvBindings.put_native_bool_binding(name, native_var)
      |> EnvBindings.remove_native_float_binding(name)
      |> EnvBindings.put_boxed_int_binding(name, false)
      |> EnvBindings.put_boxed_string_binding(name, false)

    {body_code, body_var, counter} = Host.compile_expr(in_expr, body_env, counter)

    code = """
    #{before_probe}
      #{value_code}
      const elmc_int_t #{native_var} = #{value_ref};
      #{after_probe}
      #{body_code}
    """

    {code, body_var, counter}
  end

  @spec compile_pebble_angle_let(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_pebble_angle_let(name, value_expr, in_expr, env, counter) do
    body_env =
      env
      |> Map.delete(name)
      |> EnvBindings.remove_native_int_binding(name)
      |> EnvBindings.remove_native_bool_binding(name)
      |> EnvBindings.remove_native_float_binding(name)
      |> EnvBindings.put_pebble_angle_binding(name, value_expr)
      |> EnvBindings.put_boxed_int_binding(name, false)
      |> EnvBindings.put_boxed_string_binding(name, false)

    Host.compile_expr(in_expr, body_env, counter)
  end

  @spec compile_native_float_let(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_float_let(name, value_expr, in_expr, env, counter) do
    {value_code, value_ref, counter} = Host.compile_native_float_expr(value_expr, env, counter)
    next = counter + 1
    native_var = "native_float_#{Util.safe_c_suffix(name)}_#{next}"
    before_probe = DebugProbes.let_probe(env, name, :before)
    after_probe = DebugProbes.let_probe(env, name, :after)

    body_env =
      env
      |> Map.delete(name)
      |> EnvBindings.remove_native_int_binding(name)
      |> EnvBindings.remove_native_bool_binding(name)
      |> EnvBindings.put_native_float_binding(name, native_var)
      |> EnvBindings.put_boxed_int_binding(name, false)
      |> EnvBindings.put_boxed_string_binding(name, false)

    {body_code, body_var, counter} = Host.compile_expr(in_expr, body_env, counter)

    code = """
    #{before_probe}
      #{value_code}
      const double #{native_var} = #{value_ref};
      #{after_probe}
      #{body_code}
    """

    {code, body_var, counter}
  end

  @spec compile_native_int_let(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_int_let(name, value_expr, in_expr, env, counter) do
    {value_code, value_ref, counter} = Host.compile_native_int_expr(value_expr, env, counter)
    next = counter + 1
    native_var = "native_let_#{Util.safe_c_suffix(name)}_#{next}"
    before_probe = DebugProbes.let_probe(env, name, :before)
    after_probe = DebugProbes.let_probe(env, name, :after)

    body_env =
      env
      |> Map.delete(name)
      |> EnvBindings.put_native_int_binding(name, native_var)
      |> EnvBindings.remove_native_bool_binding(name)
      |> EnvBindings.remove_native_float_binding(name)
      |> EnvBindings.put_boxed_int_binding(name, false)
      |> EnvBindings.put_boxed_string_binding(name, false)

    {body_code, body_var, counter} = Host.compile_expr(in_expr, body_env, counter)

    code = """
    #{before_probe}
      #{value_code}
      const elmc_int_t #{native_var} = #{value_ref};
      #{after_probe}
      #{body_code}
    """

    {code, body_var, counter}
  end

  defp compile_native_string_let(name, value_expr, in_expr, env, counter) do
    {value_code, value_ref, cleanup_refs, counter} =
      NativeString.compile_expr(value_expr, env, counter)

    body_env =
      env
      |> Map.delete(name)
      |> EnvBindings.put_native_string_binding(name, value_ref)
      |> EnvBindings.remove_native_int_binding(name)
      |> EnvBindings.remove_native_bool_binding(name)
      |> EnvBindings.remove_native_float_binding(name)
      |> EnvBindings.put_boxed_string_binding(name, false)

    cleanup_code =
      cleanup_refs
      |> Enum.map_join("\n  ", fn ref -> "elmc_release(#{ref});" end)

    {body_code, body_var, counter} = Host.compile_expr(in_expr, body_env, counter)

    code = """
    #{value_code}
      #{body_code}
      #{cleanup_code}
    """

    {code, body_var, counter}
  end

  @spec compile_boxed_let(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_boxed_let(name, value_expr, in_expr, env, counter) do
    {value_code, value_var, counter} = Host.compile_expr(value_expr, env, counter)
    before_probe = DebugProbes.let_probe(env, name, :before)
    after_probe = DebugProbes.let_probe(env, name, :after)

    body_env =
      env
      |> Map.put(name, value_var)
      |> EnvBindings.remove_native_int_binding(name)
      |> EnvBindings.remove_native_bool_binding(name)
      |> EnvBindings.remove_native_float_binding(name)
      |> EnvBindings.put_boxed_int_binding(
        name,
        LetAnalysis.classification(env, name) == :boxed_int or
          Host.native_int_expr?(value_expr, env)
      )
      |> EnvBindings.put_boxed_string_binding(name, NativeString.boxed_expr?(value_expr, env))
      |> EnvBindings.put_record_shape(name, Expr.record_shape(value_expr, env))

    {body_code, body_var, counter} = Host.compile_expr(in_expr, body_env, counter)

    code = """
        #{before_probe}
    #{value_code}
          #{after_probe}
      #{body_code}
      elmc_release(#{value_var});
    """

    {code, body_var, counter}
  end

  @spec flatten_let_chain(Types.ir_expr()) :: {[LetRecCompile.let_binding()], Types.ir_expr()}
  defp flatten_let_chain(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    {rest, body} = flatten_let_chain(in_expr)
    {[{name, value_expr} | rest], body}
  end

  defp flatten_let_chain(body), do: {[], body}
end
