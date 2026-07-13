defmodule Elmc.Backend.CCodegen.ImmortalStringLiteral do
  @moduledoc false

  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec value_init(String.t()) :: String.t()
  def value_init(value) when is_binary(value) do
    "{ ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)\"#{Util.escape_c_string(value)}\", #{byte_size(value)} }"
  end

  @spec array_decl(String.t(), [String.t()]) :: String.t()
  def array_decl(name, values) when is_binary(name) and is_list(values) do
    body =
      values
      |> Enum.map(fn value -> "    #{value_init(value)}" end)
      |> Enum.intersperse(",\n")
      |> IO.iodata_to_binary()

    """
    static ElmcValue #{name}[#{length(values)}] = {
    #{body}
    };
    """
    |> String.trim_trailing()
  end

  @spec static_decl(String.t(), String.t()) :: String.t()
  def static_decl(name, value) when is_binary(name) and is_binary(value) do
    "static ElmcValue #{name} = #{value_init(value)};"
  end

  @spec assign_ref(Types.compile_env(), String.t(), String.t()) :: String.t()
  def assign_ref(env, out, value_ref) when is_binary(out) and is_binary(value_ref) do
    if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
      """
      *#{RcRuntimeEmit.allocator_out_arg(out)} = #{value_ref};
      """
      |> String.trim()
    else
      "#{out} = elmc_retain(#{value_ref});"
    end
  end
end
