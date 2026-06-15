defmodule Elmc.Backend.CCodegen.SubCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CollectionCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @max_native_params 5

  @spec compile(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :pebble_sub, mask: mask, params: params}, env, counter) do
    params = List.wrap(params)

    if length(params) > @max_native_params or not native_params?(params, env) do
      CollectionCompile.compile(SpecialValues.encoded_sub_as_tuple(mask, params), env, counter)
    else
      compile_native_sub(mask, params, env, counter)
    end
  end

  defp native_params?(params, env) do
    Enum.all?(params, &native_param?(&1, env))
  end

  defp native_param?(%{op: op}, _env) when op in [:int_literal, :c_int_expr, :msg_tag_expr], do: true
  defp native_param?(expr, env), do: NativeInt.expr?(expr, env)

  defp compile_native_sub(mask, params, env, counter) do
    {mask_code, mask_ref, counter} = compile_mask_ref(mask, env, counter)

    {param_parts, counter} =
      Enum.map_reduce(params, counter, fn param, counter ->
        {code, ref, counter} = compile_param_ref(param, env, counter)
        {{code, ref}, counter}
      end)

    params_code =
      param_parts
      |> Enum.map(fn {code, _} -> code end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    param_refs = Enum.map(param_parts, fn {_, ref} -> ref end)
    arity = length(params)
    fn_name = "elmc_sub#{arity}"
    args = Enum.join([mask_ref | param_refs], ", ")
    next = counter + 1
    out = "tmp_#{next}"

    prefix =
      [mask_code, params_code]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    code = """
    #{prefix}
    ElmcValue *#{out} = #{fn_name}(#{args});
    """

    {code, out, next}
  end

  defp compile_mask_ref(%{op: :c_int_expr, value: value}, _env, counter) when is_binary(value),
    do: {"", value, counter}

  defp compile_mask_ref(%{op: :int_literal, value: value}, _env, counter) when is_integer(value),
    do: {"", Integer.to_string(value), counter}

  defp compile_mask_ref(mask, env, counter) do
    {code, var, counter} = Host.compile_expr(mask, env, counter)
    {code, "elmc_as_int(#{var})", counter}
  end

  defp compile_param_ref(%{op: :msg_tag_expr, name: name}, _env, counter) when is_binary(name) do
    {"", msg_tag_macro(name), counter}
  end

  defp compile_param_ref(%{op: :c_int_expr, value: value}, _env, counter) when is_binary(value),
    do: {"", value, counter}

  defp compile_param_ref(expr, env, counter) do
    if NativeInt.expr?(expr, env) do
      Host.compile_native_int_expr(expr, env, counter)
    else
      {code, var, counter} = Host.compile_expr(expr, env, counter)
      {code, "elmc_as_int(#{var})", counter}
    end
  end

  defp msg_tag_macro(name) do
    "ELMC_PEBBLE_MSG_#{Elmc.Backend.Pebble.Util.macro_name(name)}"
  end
end
