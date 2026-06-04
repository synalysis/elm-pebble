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

    {body_code, body_var, counter} =
      maybe_extract_boxed_let_body(in_expr, body_env, body_code, body_var, counter)

    code = """
        #{before_probe}
    #{value_code}
          #{after_probe}
      #{body_code}
      elmc_release(#{value_var});
    """

    {code, body_var, counter}
  end

  defp maybe_extract_boxed_let_body(in_expr, body_env, body_code, body_var, counter) do
    if extract_boxed_let_body?(body_env, body_code) do
      case boxed_let_body_helper_params(in_expr, body_env) do
        {:ok, params} ->
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_let_body_helper_#{Util.safe_c_suffix(Map.get(body_env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(body_env, :__function_name__, "fn"))}_#{helper_id}"

          helper_param_decls =
            params
            |> Enum.map_join(", ", fn {_key, c_ref} -> "ElmcValue *#{c_ref}" end)

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
          #{Util.indent(body_code, 2)}
            return #{body_var};
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          next = counter + 1
          out = "tmp_#{next}"
          call_args = Enum.map_join(params, ", ", fn {_key, c_ref} -> c_ref end)

          code = """
            ElmcValue *#{out} = #{helper_name}(#{call_args});
          """

          {code, out, next}

        :error ->
          {body_code, body_var, counter}
      end
    else
      {body_code, body_var, counter}
    end
  end

  defp extract_boxed_let_body?(env, body_code) do
    not Map.get(env, :__inside_lambda__, false) and
      Process.get(:elmc_generic_helper_defs) != nil and emitted_line_count(body_code) >= 100
  end

  defp emitted_line_count(code), do: code |> String.split("\n") |> length()

  defp boxed_let_body_helper_params(expr, env) do
    params =
      expr
      |> external_vars()
      |> Enum.sort()
      |> Enum.reduce_while([], fn var, acc ->
        case Map.get(env, var) do
          c_ref when is_binary(c_ref) ->
            if c_identifier?(c_ref), do: {:cont, [{var, c_ref} | acc]}, else: {:halt, :error}

          _other ->
            if zero_arg_function_var?(env, var), do: {:cont, acc}, else: {:halt, :error}
        end
      end)

    case params do
      :error ->
        :error

      params ->
        {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_key, c_ref} -> c_ref end)}
    end
  end

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

  defp zero_arg_function_var?(env, var) do
    module_name = Map.get(env, :__module__, "Main")

    case Map.get(env, :__program_decls__, %{}) do
      %{} = decl_map ->
        case Map.get(decl_map, {module_name, var}) do
          %{args: args} when args in [[], nil] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp external_vars(expr), do: external_vars(expr, MapSet.new())

  defp external_vars(%{op: :var, name: name}, bound) when is_binary(name) or is_atom(name) do
    key = EnvBindings.binding_key(name)
    if MapSet.member?(bound, key), do: MapSet.new(), else: MapSet.new([key])
  end

  defp external_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound) do
    value_vars = external_vars(value_expr, bound)
    in_vars = external_vars(in_expr, MapSet.put(bound, EnvBindings.binding_key(name)))
    MapSet.union(value_vars, in_vars)
  end

  defp external_vars(%{op: :lambda, args: args, body: body}, bound) when is_list(args) do
    lambda_bound =
      Enum.reduce(args, bound, fn arg, acc -> MapSet.put(acc, EnvBindings.binding_key(arg)) end)

    external_vars(body, lambda_bound)
  end

  defp external_vars(%{op: :field_access, arg: arg}, bound) when is_binary(arg) or is_atom(arg) do
    key = EnvBindings.binding_key(arg)
    if MapSet.member?(bound, key), do: MapSet.new(), else: MapSet.new([key])
  end

  defp external_vars(expr, bound) when is_map(expr) do
    Enum.reduce(expr, MapSet.new(), fn
      {_key, value}, acc when is_map(value) or is_list(value) ->
        MapSet.union(acc, external_vars(value, bound))

      {_key, _value}, acc ->
        acc
    end)
  end

  defp external_vars(values, bound) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, external_vars(value, bound))
    end)
  end

  defp external_vars(_expr, _bound), do: MapSet.new()

  @spec flatten_let_chain(Types.ir_expr()) :: {[LetRecCompile.let_binding()], Types.ir_expr()}
  defp flatten_let_chain(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    {rest, body} = flatten_let_chain(in_expr)
    {[{name, value_expr} | rest], body}
  end

  defp flatten_let_chain(body), do: {[], body}
end
