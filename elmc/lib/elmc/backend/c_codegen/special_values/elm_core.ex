defmodule Elmc.Backend.CCodegen.SpecialValues.ElmCore do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @modules ~w(
    Array Basics Bitwise Char Debug Dict List Maybe Result Set String Task Process Tuple
  )

  @literals ["True", "False", "LT", "EQ", "GT", "()", "Basics.e", "Basics.pi"]

  @spec known_target?(String.t()) :: boolean()
  def known_target?(target) when is_binary(target) do
    target in @literals or match_module?(target)
  end

  def known_target?(_target), do: false

  @spec comment_line(String.t()) :: String.t()
  def comment_line(target) when is_binary(target) do
    "  /* elm/core: #{Util.escape_c_comment(display_name(target))} */\n"
  end

  @spec with_comment(Types.compile_result(), String.t()) :: Types.compile_result()
  def with_comment({code, var, counter} = result, target) do
    if known_target?(target) do
      {comment_line(target) <> code, var, counter}
    else
      result
    end
  end

  defp match_module?(target) do
    case String.split(target, ".") do
      [module, _function | _] -> module in @modules
      _ -> false
    end
  end

  defp display_name(target) do
    case String.split(target, ".") do
      [single] -> single
      parts -> Enum.join(parts, ".")
    end
  end
end
