defmodule Elmc.Backend.CCodegen.LiteralCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Pebble.Util, as: PebbleUtil

  @spec compile(Types.ir_literal_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :int_literal} = expr, _env, counter) do
    value = ResourceUnion.int_literal_value(expr)
    next = counter + 1
    var = "tmp_#{next}"

    code =
      if value == 0 do
        "ElmcValue *#{var} = elmc_int_zero();"
      else
        "ElmcValue *#{var} = elmc_new_int(#{value});"
      end

    {code, var, next}
  end

  def compile(%{op: :c_int_expr, value: value}, _env, counter) when is_binary(value) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(#{value});", var, next}
  end

  def compile(%{op: :msg_tag_expr, name: name}, _env, counter) when is_binary(name) do
    next = counter + 1
    var = "tmp_#{next}"
    macro = "ELMC_PEBBLE_MSG_#{PebbleUtil.macro_name(name)}"
    {"ElmcValue *#{var} = elmc_new_int(#{macro});", var, next}
  end

  def compile(%{op: :string_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_string(\"#{Util.escape_c_string(value)}\");", var, next}
  end

  def compile(%{op: :char_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_char(#{value});", var, next}
  end

  def compile(%{op: :float_literal, value: value}, _env, counter) do
    next = counter + 1
    var = "tmp_#{next}"
    float_val = if is_integer(value), do: "#{value}.0", else: "#{value}"
    {"ElmcValue *#{var} = elmc_new_float(#{float_val});", var, next}
  end

  def compile(%{op: :cmd_none}, env, counter) do
    Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)
  end
end
