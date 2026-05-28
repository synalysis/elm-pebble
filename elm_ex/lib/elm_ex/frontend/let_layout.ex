defmodule ElmEx.Frontend.LetLayout do
  @moduledoc """
  Layout rules for `let` expressions, matching the official Elm compiler.

  The expression parser (`elm_ex_expr_parser`) is token-based and can accept
  `let x = y in z` on one line. Elm requires `in` on its own line (with the
  body following on the next). Call `validate/1` on source before lexing/parsing.
  """

  @inline_let_in_line ~r/\blet\s+.+\s+in(\s+|$)/u

  @doc """
  Returns `:ok` when no physical line contains `let` and `in` as keywords on the same line.
  """
  @spec validate(String.t()) :: :ok | {:error, {:inline_let_in, pos_integer()}}
  def validate(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {line, line_no}, :ok ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          {:cont, :ok}

        String.starts_with?(trimmed, "--") ->
          {:cont, :ok}

        Regex.match?(@inline_let_in_line, trimmed) ->
          {:halt, {:error, {:inline_let_in, line_no}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  @doc false
  @spec parse_error(pos_integer()) :: {pos_integer(), :elm_ex_expr_parser, [String.t() | char()]}
  def parse_error(line) when is_integer(line) and line > 0 do
    {line, :elm_ex_expr_parser,
     [
       "let expressions require 'in' on its own line (see https://elm-lang.org/docs/syntax)",
       ~c"in_kw"
     ]}
  end
end
