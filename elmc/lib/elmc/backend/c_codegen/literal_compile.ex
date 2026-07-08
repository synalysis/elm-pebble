defmodule Elmc.Backend.CCodegen.LiteralCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.ResourceSlotMacros
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.Pebble.Util, as: PebbleUtil

  @spec compile(Types.ir_literal_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :int_literal} = expr, env, counter) do
    if BuiltinUnion.maybe_nothing_literal?(expr) do
      BuiltinUnion.compile_maybe_nothing(env, counter)
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
    {var, counter} =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        CaseCompile.fresh_var(counter, env)
      else
        next = counter + 1
        {"tmp_#{next}", next}
      end

    code =
      if String.contains?(value, <<0>>) do
        escaped = Util.escape_c_string(value)
        byte_len = byte_size(value)

        RcRuntimeEmit.assign_call(env, var, "elmc_new_string_len", "\"#{escaped}\", #{byte_len}") <>
          "\n"
      else
        RcRuntimeEmit.assign_call(env, var, "elmc_new_string", "\"#{Util.escape_c_string(value)}\"") <>
          "\n"
      end

    {code, var, counter}
  end

  def compile(%{op: :char_literal, value: value}, env, counter) do
    {var, counter} = literal_out_slot(env, counter)
    {RcRuntimeEmit.assign_call(env, var, "elmc_new_char", "#{value}") <> "\n", var, counter}
  end

  def compile(%{op: :bool_literal, value: value}, env, counter) do
    {var, counter} = literal_out_slot(env, counter)
    flag = if value, do: "1", else: "0"

    {RcRuntimeEmit.assign_call(env, var, "elmc_new_bool", flag) <> "\n", var, counter}
  end

  def compile(%{op: :order_literal, value: value}, env, counter) when is_integer(value) do
    {var, counter} = literal_out_slot(env, counter)
    {RcRuntimeEmit.assign_call(env, var, "elmc_new_order", "#{value}") <> "\n", var, counter}
  end

  def compile(%{op: :float_literal, value: value}, env, counter) do
    {var, counter} = literal_out_slot(env, counter)
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {RcRuntimeEmit.assign_call(env, var, "elmc_new_float", float_val) <> "\n", var, counter}
  end

  def compile(%{op: :cmd_none}, env, counter) do
    Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)
  end

  def compile(%{op: :sub_none}, env, counter) do
    Host.compile_expr(
      %{op: :pebble_sub, mask: %{op: :int_literal, value: 0}, params: []},
      env,
      counter
    )
  end

  defp compile_int_literal(%{op: :int_literal} = expr, env, counter) do
    value = ResourceUnion.int_literal_value(expr)
    ref = IntLiteralRef.ref(expr, env)
    {var, counter} = literal_out_slot(env, counter)

    code =
      if value == 0 and ResourceSlotMacros.literal_ref(expr) == nil and
           UnionMacros.literal_ref(expr, env) == nil do
        int_zero_assign(var, env)
      else
        RcRuntimeEmit.assign_call(env, var, "elmc_new_int", ref)
      end

    {code, var, counter}
  end

  defp int_zero_assign(var, env) do
    if ValueSlots.owned_ref?(var) or Map.get(env, :__into_out__) == var or
         RcRuntimeEmit.function_out_ref?(var) do
      "#{RcRuntimeEmit.assignment_lhs(var)} = elmc_int_zero();"
    else
      "ElmcValue *#{var} = elmc_int_zero();"
    end
  end

  defp literal_out_slot(env, counter) do
    cond do
      out = RcRuntimeEmit.fn_out_alloc_target(env) ->
        {out, counter}

      true ->
        CaseCompile.fresh_var(counter, env)
    end
  end
end
