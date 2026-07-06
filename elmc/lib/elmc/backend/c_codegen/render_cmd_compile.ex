defmodule Elmc.Backend.CCodegen.RenderCmdCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CollectionCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.PolarPoint
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @max_native_params 6

  @spec compile(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :render_cmd, kind: kind, params: params}, env, counter) do
    params = List.wrap(params)

    if length(params) > @max_native_params do
      arity = length(params)

      padded =
        params ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, @max_native_params - arity))

      CollectionCompile.compile(
        %{op: :tuple2, left: kind, right: Helpers.tuple_chain(padded)},
        env,
        counter
      )
    else
      compile_native_render_cmd(kind, params, env, counter)
    end
  end

  defp compile_native_render_cmd(kind, params, env, counter) do
    {kind_code, kind_ref, counter} = compile_kind_ref(kind, env, counter)

    padded =
      params ++ List.duplicate(%{op: :int_literal, value: 0}, @max_native_params - length(params))

    {param_parts, counter} =
      Enum.map_reduce(padded, counter, fn param, counter ->
        {code, ref, counter} = compile_param_ref(param, env, counter)
        {{code, ref}, counter}
      end)

    params_code =
      param_parts
      |> Enum.map(fn {code, _} -> code end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    param_refs = Enum.map(param_parts, fn {_, ref} -> ref end)
    args = Enum.join([kind_ref | param_refs], ", ")
    {out, next} = RcRuntimeEmit.compile_result_slot(env, counter)

    prefix =
      [kind_code, params_code]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    code = """
    #{prefix}
      #{RcRuntimeEmit.assign_call(env, out, "elmc_render_cmd6", args)}
    """

    {code, out, next}
  end

  defp compile_kind_ref(%{op: :c_int_expr, value: value}, _env, counter) when is_binary(value),
    do: {"", value, counter}

  defp compile_kind_ref(%{op: :int_literal, value: value}, _env, counter) when is_integer(value),
    do: {"", Integer.to_string(value), counter}

  defp compile_kind_ref(kind, env, counter) do
    {code, var, counter} = Host.compile_expr(kind, env, counter)
    {code, "elmc_as_int(#{var})", counter}
  end

  defp compile_param_ref(%{op: :c_int_expr, value: value}, _env, counter) when is_binary(value),
    do: {"", value, counter}

  defp compile_param_ref(%{op: :int_literal, value: value}, _env, counter) when is_integer(value),
    do: {"", Integer.to_string(value), counter}

  defp compile_param_ref(%{op: :field_access, arg: arg, field: field} = expr, env, counter)
       when is_binary(field) do
    param_env = RcRuntimeEmit.strip_function_tail_scope(env)

    case Host.inline_record_field_expr(arg, field, param_env) do
      field_expr when is_map(field_expr) ->
        compile_param_ref(field_expr, env, counter)

      nil ->
        compile_param_ref_fallback(expr, env, counter)
    end
  end

  defp compile_param_ref(expr, env, counter) do
    compile_param_ref_fallback(expr, env, counter)
  end

  defp compile_param_ref_fallback(%{op: :field_access, arg: arg, field: field}, env, counter)
       when is_binary(field) do
    param_env = RcRuntimeEmit.strip_function_tail_scope(env)

    case PolarPoint.try_compile_field(arg, field, param_env, counter) do
      {:ok, code, ref, counter} ->
        {code, ref, counter}

      :error ->
        field_expr = %{op: :field_access, arg: arg, field: field}

        if NativeInt.expr?(field_expr, param_env) do
          Host.compile_native_int_expr(field_expr, param_env, counter)
        else
          {code, var, counter} = Host.compile_expr(field_expr, param_env, counter)
          {code, "elmc_as_int(#{var})", counter}
        end
    end
  end

  defp compile_param_ref_fallback(expr, env, counter) do
    param_env = RcRuntimeEmit.strip_function_tail_scope(env)

    if NativeInt.expr?(expr, param_env) do
      Host.compile_native_int_expr(expr, param_env, counter)
    else
      {code, var, counter} = Host.compile_expr(expr, param_env, counter)
      {code, "elmc_as_int(#{var})", counter}
    end
  end
end
