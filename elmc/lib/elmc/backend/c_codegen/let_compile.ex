defmodule Elmc.Backend.CCodegen.LetCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.HelperParams
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LetAnalysis
  alias Elmc.Backend.CCodegen.LetRecCompile
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.Native.UsageAnalysis, as: NativeUsageAnalysis
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
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

    if LetRecCompile.cyclic_bindings?(bindings) do
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
      const bool #{native_var} = #{value_ref};
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
      |> Enum.map_join("\n  ", &ValueSlots.release_stmt/1)

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
    env =
      if match?(%{op: :lambda}, value_expr),
        do: Map.put(env, :__skip_let_body_helper__, true),
        else: env

    {value_code, value_var, counter, native_ref} =
      compile_boxed_let_value(value_expr, env, counter)

    before_probe = DebugProbes.let_probe(env, name, :before)
    after_probe = DebugProbes.let_probe(env, name, :after)
    record_shape = Expr.record_shape(value_expr, env)

    body_env =
      env
      |> Map.put(name, value_var)
      |> put_hybrid_loop_native_ref(name, native_ref)
      |> EnvBindings.remove_native_int_binding(name)
      |> EnvBindings.remove_native_bool_binding(name)
      |> EnvBindings.remove_native_float_binding(name)
      |> EnvBindings.put_boxed_int_binding(
        name,
        LetAnalysis.classification(env, name) == :boxed_int or
          Host.native_int_expr?(value_expr, env)
      )
      |> EnvBindings.put_boxed_string_binding(name, NativeString.boxed_expr?(value_expr, env))
      |> put_boxed_record_shape(name, record_shape)
      |> put_boxed_var_type(name, value_expr, env)
      |> RecordCompile.fresh_subexpr_cache()
      |> Map.put(:__rc_catch__, false)

    {body_code, body_var, counter} = Host.compile_expr(in_expr, body_env, counter)

    {body_code, body_var, counter} =
      maybe_extract_boxed_let_body(in_expr, body_env, body_code, body_var, counter)

    code = """
        #{before_probe}
    #{value_code}
          #{after_probe}
      #{body_code}
      #{let_value_release(env, value_var, body_code)}
    """

    {code, body_var, counter}
  end

  defp put_boxed_record_shape(env, name, fields) when is_list(fields) do
    shapes = Map.get(env, :__record_shapes__, %{})
    Map.put(env, :__record_shapes__, Map.put(shapes, EnvBindings.binding_key(name), fields))
  end

  defp put_boxed_record_shape(env, _name, _fields), do: env

  defp put_boxed_var_type(body_env, name, value_expr, env) do
    case TypedReturn.expr_type(value_expr, env) do
      type when is_binary(type) -> EnvBindings.put_var_type(body_env, name, type)
      _ -> body_env
    end
  end

  @spec compile_boxed_let_value(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter(), String.t() | nil}
  defp compile_boxed_let_value(value_expr, env, counter) do
    if Host.native_int_expr?(value_expr, env) do
      {native_code, native_ref, counter} = Host.compile_native_int_expr(value_expr, env, counter)
      {value_var, counter} = CaseCompile.fresh_var(counter, env)

      value_code = """
      #{native_code}#{RcRuntimeEmit.assign_call(env, value_var, "elmc_new_int", native_ref)}
      """

      {value_code, value_var, counter, native_ref}
    else
      value_env = RcRuntimeEmit.strip_function_tail_scope(env)

      {value_code, value_var, counter} = Host.compile_expr(value_expr, value_env, counter)
      {value_code, value_var, counter, nil}
    end
  end

  @spec put_hybrid_loop_native_ref(
          Types.compile_env(),
          Types.binding_name(),
          String.t() | nil
        ) :: Types.compile_env()
  defp put_hybrid_loop_native_ref(env, name, nil) do
    EnvBindings.remove_hybrid_loop_native_ref(env, name)
  end

  defp put_hybrid_loop_native_ref(env, name, native_ref) when is_binary(native_ref) do
    EnvBindings.put_hybrid_loop_native_ref(env, name, native_ref)
  end

  defp maybe_extract_boxed_let_body(in_expr, body_env, body_code, body_var, counter) do
    if extract_boxed_let_body?(body_env, body_code) do
      case boxed_let_body_helper_params(in_expr, body_env, body_code) do
        {:ok, params} when params != [] ->
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_let_body_helper_#{Util.safe_c_suffix(Map.get(body_env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(body_env, :__function_name__, "fn"))}_#{helper_id}"

          helper_param_decls = HelperParams.param_decls(params)

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
          #{CSource.indent(sanitize_let_helper_body(body_code), 2)}
            return #{body_var};
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          next = counter + 1
          out = "tmp_#{next}"
          call_args = HelperParams.call_args(params)

          code = """
            ElmcValue *#{out} = #{helper_name}(#{call_args});
          """

          {code, out, next}

        _ ->
          {body_code, body_var, counter}
      end
    else
      {body_code, body_var, counter}
    end
  end

  defp extract_boxed_let_body?(env, body_code) do
    RcRuntimeEmit.generic_helper_extraction_allowed?(env, body_code) and
      not Map.get(env, :__skip_let_body_helper__, false) and
      Process.get(:elmc_generic_helper_defs) != nil and emitted_line_count(body_code) >= 100
  end

  defp emitted_line_count(code), do: code |> String.split("\n") |> length()

  defp sanitize_let_helper_body(code) when is_binary(code) do
    code
    |> String.replace("return __alloc_rc;", "return NULL;")
    |> String.replace("return Rc;", "return NULL;")
  end

  defp boxed_let_body_helper_params(expr, env, body_code) do
    vars =
      expr
      |> external_vars()
      |> MapSet.union(case_subject_vars(expr))
      |> MapSet.union(helper_vars_from_body_code(body_code, env))
      |> MapSet.to_list()

    case HelperParams.collect(vars, env) do
      :error -> :error
      {:ok, params} -> {:ok, params}
    end
  end

  defp helper_vars_from_body_code(body_code, env) when is_binary(body_code) do
    env
    |> EnvBindings.env_resolvable_binding_keys()
    |> Enum.reduce(MapSet.new(), fn key, acc ->
      c_ref =
        cond do
          is_binary(ref = EnvBindings.native_int_binding(env, key)) -> ref
          is_binary(ref = EnvBindings.native_bool_binding(env, key)) -> ref
          is_binary(ref = EnvBindings.native_float_binding(env, key)) -> ref
          is_binary(ref = Map.get(env, key)) -> ref
          true -> nil
        end

      if is_binary(c_ref) and Regex.match?(~r/\b#{Regex.escape(c_ref)}\b/, body_code) do
        MapSet.put(acc, key)
      else
        acc
      end
    end)
  end

  defp case_subject_vars(expr) when is_map(expr) do
    own =
      case expr do
        %{op: :case, subject: subject} when is_binary(subject) -> MapSet.new([subject])
        _ -> MapSet.new()
      end

    expr
    |> Map.values()
    |> Enum.reduce(own, fn value, acc ->
      MapSet.union(acc, case_subject_vars(value))
    end)
  end

  defp case_subject_vars(values) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, case_subject_vars(value))
    end)
  end

  defp case_subject_vars(_), do: MapSet.new()

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

  defp let_value_release(env, value_var, body_code) when is_binary(value_var) do
    cond do
      EnvBindings.borrowed_arg_ref?(env, value_var) -> ""
      ValueSlots.transferred?(value_var, body_code) -> ""
      released_in_let_body?(value_var, body_code) -> ""
      true ->
        ValueSlots.release_stmt(value_var)
    end
  end

  defp released_in_let_body?(var, body_code) when is_binary(var) and is_binary(body_code) do
    String.contains?(body_code, "elmc_release(#{var})") or
      String.contains?(body_code, "ELMC_RELEASE(#{var})")
  end

  defp released_in_let_body?(_var, _body_code), do: false
end
