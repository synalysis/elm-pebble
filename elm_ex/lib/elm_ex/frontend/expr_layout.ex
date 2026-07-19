defmodule ElmEx.Frontend.ExprLayout do
  @moduledoc """
  Legacy layout normalization for `elm_ex_expr_parser`.

  Multiline Elm is normally tokenized by `ElmEx.Frontend.ExprLayoutLexer`, which
  emits `{indent, line}`, `{dedent, line}`, and `{newline, line}` for Yecc.
  This module remains as a fallback that flattens layout into explicit `;;` /
  `;` separators for pre-normalized or edge-case fragments.
  """

  alias ElmEx.Frontend.GeneratedExpressionParser.Layout

  @type source() :: String.t()

  @doc """
  Normalize layout-heavy Elm expression source into the legacy flat surface syntax.
  """
  @spec normalize(source()) :: source()
  def normalize(source) when is_binary(source), do: Layout.normalize(source)
end
