defmodule Elmc.Backend.C.Ast.Emit do
  @moduledoc false

  alias Elmc.Backend.C.Ast.RcFn

  @spec to_c(RcFn.t()) :: String.t()
  def to_c(%RcFn{stmts: stmts}) do
    stmts
    |> Enum.map(&stmt_to_c/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp stmt_to_c({:decl_rc}), do: "RC Rc = RC_SUCCESS;"
  defp stmt_to_c({:decl_owned, decl}), do: decl
  defp stmt_to_c({:letrec, line}), do: line
  defp stmt_to_c({:catch_begin}), do: "CATCH_BEGIN"
  defp stmt_to_c({:catch_end}), do: "CATCH_END"
  defp stmt_to_c({:raw, body}), do: body
  defp stmt_to_c({:epilogue, text}), do: text
  defp stmt_to_c({:return_rc}), do: "return Rc;"
end
