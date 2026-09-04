defmodule ElmEx.Frontend.LayoutRules do
  @moduledoc """
  Shared Elm layout rules for parse (indent lexer) and print (formatter).

  Both sides agree on what counts as a sibling `let` binding or `case` arm at the
  same indentation level, so formatted source re-tokenizes the same way.
  """


  @doc "True when a physical line starts a new `let` binding at the block indent."
  @spec let_binding_start?(String.t()) :: boolean()
  def let_binding_start?(text) when is_binary(text) do
    trimmed = String.trim(text)

    Regex.match?(~r/^[a-z_][A-Za-z0-9_']*(\s+[a-z_][A-Za-z0-9_']*)*\s*=/u, trimmed) or
      paren_pattern_binding_start?(trimmed) or
      Regex.match?(~r/^\{\s*[^=]*\}\s*=/u, trimmed)
  end

  # `(a, b) = …`, `(Just x) = …` — not lambdas `(\x -> …)` and not parenthesized
  # expressions that merely contain `=` inside a record update / nested form.
  @spec paren_pattern_binding_start?(String.t()) :: boolean()

  defp paren_pattern_binding_start?(trimmed) when is_binary(trimmed) do
    case split_paren_pattern_binding(trimmed) do
      {:ok, inner} ->
        inner_trim = String.trim(inner)
        inner_trim != "" and not String.starts_with?(inner_trim, "\\")

      :error ->
        false
    end
  end

  @spec split_paren_pattern_binding(binary()) :: {:ok, binary()} | :error

  defp split_paren_pattern_binding(<<"(", rest::binary>>) do
    case find_matching_close_paren(rest, 1, 0) do
      {:ok, inner, after_close} ->
        if Regex.match?(~r/^\s*=(?!=)/u, after_close) do
          {:ok, inner}
        else
          :error
        end

      :error ->
        :error
    end
  end

  defp split_paren_pattern_binding(_), do: :error

  @spec find_matching_close_paren(String.t(), pos_integer(), non_neg_integer()) ::
          {:ok, String.t(), String.t()} | :error

  defp find_matching_close_paren(text, depth, idx) when depth > 0 do
    case String.at(text, idx) do
      nil ->
        :error

      "(" ->
        find_matching_close_paren(text, depth + 1, idx + 1)

      ")" ->
        if depth == 1 do
          inner = String.slice(text, 0, idx)
          rest_after = String.slice(text, (idx + 1)..-1//1)
          {:ok, inner, rest_after}
        else
          find_matching_close_paren(text, depth - 1, idx + 1)
        end

      _ ->
        find_matching_close_paren(text, depth, idx + 1)
    end
  end

  @doc "True when a physical line starts a new `case` arm at the block indent."
  @spec case_arm_start?(String.t()) :: boolean()
  def case_arm_start?(text) when is_binary(text) do
    trimmed = String.trim(text)

    not keyword_line?(trimmed) and
      not Regex.match?(~r/^(else|if|case|let)\b/u, trimmed) and
      not Regex.match?(~r/^\(\s*\\/u, trimmed) and
      Regex.match?(~r/->/u, trimmed) and
      (Regex.match?(~r/^_\s*->/u, trimmed) or
         Regex.match?(~r/^["'0-9[{A-Za-z_(]/u, trimmed))
  end

  @spec keyword_line?(String.t()) :: boolean()

  defp keyword_line?(trimmed) do
    trimmed in ["in", "else", "then", "of", "let", "if", "case"] or
      Regex.match?(~r/^(in|else|then|of|let|if|case)\b/u, trimmed)
  end

  @doc "True when a physical line starts with the `else` keyword."
  @spec else_line_start?(String.t()) :: boolean()
  def else_line_start?(text) when is_binary(text) do
    String.trim(text) |> String.starts_with?("else")
  end

  @doc "True when a physical line starts with the `in` keyword (optionally followed by the body)."
  @spec in_line_start?(String.t()) :: boolean()
  def in_line_start?(text) when is_binary(text) do
    trimmed = String.trim(text)
    trimmed == "in" or String.starts_with?(trimmed, "in ")
  end

  @doc "True when a physical line starts with the `of` keyword."
  @spec of_line_start?(String.t()) :: boolean()
  def of_line_start?(text) when is_binary(text) do
    trimmed = String.trim(text)
    trimmed == "of" or String.starts_with?(trimmed, "of ")
  end

  @doc "True when a physical line continues a pipe chain (`|> …`)."
  @spec pipe_continuation?(String.t()) :: boolean()
  def pipe_continuation?(text) when is_binary(text) do
    String.trim(text) |> String.starts_with?("|>")
  end

  @doc "True when a physical line continues a cons expression (`:: …`)."
  @spec cons_continuation?(String.t()) :: boolean()
  def cons_continuation?(text) when is_binary(text) do
    String.trim(text) |> String.starts_with?("::")
  end

  @doc "True when a physical line continues an append expression (`++ …`)."
  @spec append_continuation?(String.t()) :: boolean()
  def append_continuation?(text) when is_binary(text) do
    String.trim(text) |> String.starts_with?("++")
  end

  @doc "True when a line continues the current expression after a value line."
  @spec value_line_continuation?(String.t()) :: boolean()
  def value_line_continuation?(text) when is_binary(text) do
    pipe_continuation?(text) or cons_continuation?(text) or append_continuation?(text)
  end

  @doc "True when a line starts the RHS of an infix operator (`<|`, `<<`, `>>`)."
  @spec infix_rhs_line_start?(String.t()) :: boolean()
  def infix_rhs_line_start?(text) when is_binary(text) do
    trimmed = String.trim(text)

    not keyword_line?(trimmed) and
      not let_binding_start?(text) and
      not case_arm_start?(text) and
      Regex.match?(~r/^(\(|\[|\{|\\|[A-Za-z_(])/, trimmed)
  end

  @doc "True when a physical line continues a split call argument (list, tuple, or record)."
  @spec application_continuation?(String.t()) :: boolean()
  def application_continuation?(text) when is_binary(text) do
    trimmed = String.trim(text)

    not let_binding_start?(text) and
      not case_arm_start?(text) and
      (String.starts_with?(trimmed, "[") or String.starts_with?(trimmed, "(") or
         String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, ",") or
         value_application_continuation?(text))
  end

  @doc false
  @spec value_application_continuation?(String.t()) :: boolean()
  def value_application_continuation?(text) when is_binary(text) do
    trimmed = String.trim(text)

    not keyword_line?(trimmed) and
      not Regex.match?(~r/^(else|if|case|let|in)\b/u, trimmed) and
      Regex.match?(~r/^[A-Za-z_(]/u, trimmed)
  end

  @doc "Token the layout lexer emits between sibling `let` bindings."
  @spec let_binding_sep() :: atom()

  def let_binding_sep, do: :semicolon

  @doc "Token the layout lexer emits between sibling `case` arms."
  @spec case_arm_sep() :: atom()

  def case_arm_sep, do: :case_sep
end
