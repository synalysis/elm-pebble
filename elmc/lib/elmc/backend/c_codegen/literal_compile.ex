defmodule Elmc.Backend.CCodegen.LiteralCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.ResourceSlotMacros
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Pebble.Util, as: PebbleUtil

  @spec compile(Types.ir_literal_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :int_literal} = expr, env, counter) do
    if BuiltinUnion.maybe_nothing_literal?(expr) do
      BuiltinUnion.compile_maybe_nothing(counter)
    else
      compile_int_literal(expr, env, counter)
    end
  end

  def compile(%{op: :c_int_expr, value: value}, env, counter) when is_binary(value) do
    {var, counter} = literal_out_slot(env, counter)
    {RcRuntimeEmit.assign_call(env, var, "elmc_new_int", value) <> "\n", var, counter}
  end

  def compile(%{op: :msg_tag_expr, name: name}, env, counter) when is_binary(name) do
    {var, counter} = literal_out_slot(env, counter)
    macro = "ELMC_PEBBLE_MSG_#{PebbleUtil.macro_name(name)}"
    {RcRuntimeEmit.assign_call(env, var, "elmc_new_int", macro) <> "\n", var, counter}
  end

  def compile(%{op: :string_literal, value: value}, env, counter) do
    next = counter + 1
    var = "tmp_#{next}"

    code =
      if String.contains?(value, <<0>>) do
        "ElmcValue *#{var} = #{Util.string_literal_c_expr(value)};\n"
      else
        RcRuntimeEmit.assign_call(env, var, "elmc_new_string", "\"#{Util.escape_c_string(value)}\"") <>
          "\n"
      end

    {code, var, next}
  end

  def compile(%{op: :char_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_char(#{value});", var, next}
  end

  def compile(%{op: :bool_literal, value: value}, env, counter) do
    {var, counter} = literal_out_slot(env, counter)
    flag = if value, do: "1", else: "0"

    {RcRuntimeEmit.assign_call(env, var, "elmc_new_bool", flag) <> "\n", var, counter}
  end

  def compile(%{op: :order_literal, value: value}, _env, counter) when is_integer(value) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_order(#{value});", var, next}
  end

  def compile(%{op: :float_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {"ElmcValue *#{var} = elmc_new_float_take(#{float_val});", var, next}
  end

  def compile(%{op: :cmd_none}, env, counter) do
    Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)
  end

  defp compile_int_literal(%{op: :int_literal} = expr, env, counter) do
    value = ResourceUnion.int_literal_value(expr)
    ref = IntLiteralRef.ref(expr, env)
    {var, counter} = literal_out_slot(env, counter)

    code =
      if value == 0 and ResourceSlotMacros.literal_ref(expr) == nil and
           UnionMacros.literal_ref(expr, env) == nil do
        if Map.get(env, :__into_out__) == var do
          "#{var} = elmc_int_zero();"
        else
          "ElmcValue *#{var} = elmc_int_zero();"
        end
      else
        RcRuntimeEmit.assign_call(env, var, "elmc_new_int", ref)
      end

    {code, var, counter}
  end

  defp literal_out_slot(env, counter) do
    case Map.get(env, :__into_out__) do
      into_out when is_binary(into_out) ->
        {into_out, counter}

      _ ->
        next = counter + 1
        {"tmp_#{next}", next}
    end
  end
end
