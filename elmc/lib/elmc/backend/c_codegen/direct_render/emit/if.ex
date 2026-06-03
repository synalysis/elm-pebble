defmodule Elmc.Backend.CCodegen.DirectRender.Emit.If do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Util

  @spec if_code(String.t(), String.t(), String.t(), String.t(), String.t()) :: String.t()
  def if_code(cond_code, cond_ref, then_code, else_code, cond_release) do
    then_empty? = empty_code?(then_code)
    else_empty? = empty_code?(else_code)

    body =
      cond do
        then_empty? and else_empty? ->
          ""

        then_empty? ->
          """
            if (!(#{cond_ref})) {
          #{Util.indent(else_code, 4)}
            }
          """

        else_empty? ->
          """
            if (#{cond_ref}) {
          #{Util.indent(then_code, 4)}
            }
          """

        true ->
          """
            if (#{cond_ref}) {
          #{Util.indent(then_code, 4)}
            } else {
          #{Util.indent(else_code, 4)}
            }
          """
      end

    """
    if (!direct_stop) {
    #{cond_code}
    #{body}
    #{cond_release}
    }
    """
  end

  @spec empty_code?(String.t() | nil) :: boolean()
  defp empty_code?(code), do: String.trim(code || "") == ""
end
