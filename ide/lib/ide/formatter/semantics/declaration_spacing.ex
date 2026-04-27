defmodule Ide.Formatter.Semantics.DeclarationSpacing do
  @moduledoc false

  @spec normalize(String.t()) :: String.t()
  def normalize(source) when is_binary(source) do
    lines = String.split(source, "\n", trim: false)

    normalized_rev =
      normalize_declaration_lines(
        lines,
        %{prev_decl: nil, pending_blanks: 0, in_block_comment: false},
        []
      )

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_declaration_lines(term(), term(), term()) :: term()
  defp normalize_declaration_lines([], state, acc) do
    emit_blanks(acc, state.pending_blanks)
  end

  defp normalize_declaration_lines([line | rest], state, acc) do
    trimmed = String.trim_leading(line)
    indent = leading_indent(line)
    next_in_block_comment = block_comment_state_after(line, state.in_block_comment)

    cond do
      state.in_block_comment ->
        next_state = %{state | pending_blanks: 0, in_block_comment: next_in_block_comment}
        normalize_declaration_lines(rest, next_state, [line | acc])

      trimmed == "" ->
        normalize_declaration_lines(
          rest,
          %{
            state
            | pending_blanks: state.pending_blanks + 1,
              in_block_comment: next_in_block_comment
          },
          acc
        )

      indent == 0 and is_tuple(top_level_declaration(line)) ->
        decl = top_level_declaration(line)

        required_blanks =
          case state.prev_decl do
            nil ->
              state.pending_blanks

            prev ->
              cond do
                prev == {:doc_comment, nil} and
                    (match?({:definition, _}, decl) or match?({:annotation, _}, decl)) ->
                  state.pending_blanks

                match?({:comment, nil}, decl) ->
                  state.pending_blanks

                true ->
                  declaration_spacing(prev, decl)
              end
          end

        next_acc =
          acc
          |> emit_blanks(required_blanks)
          |> then(&[line | &1])

        next_prev_decl = declaration_state_after(state.prev_decl, decl, state.pending_blanks)

        normalize_declaration_lines(
          rest,
          %{
            prev_decl: next_prev_decl,
            pending_blanks: 0,
            in_block_comment: next_in_block_comment
          },
          next_acc
        )

      true ->
        next_acc =
          acc
          |> emit_blanks(state.pending_blanks)
          |> then(&[line | &1])

        next_prev_decl =
          if indent == 0 do
            nil
          else
            state.prev_decl
          end

        normalize_declaration_lines(
          rest,
          %{
            prev_decl: next_prev_decl,
            pending_blanks: 0,
            in_block_comment: next_in_block_comment
          },
          next_acc
        )
    end
  end

  @spec block_comment_state_after(term(), term()) :: term()
  defp block_comment_state_after(line, in_block_comment) do
    trimmed = String.trim_leading(line)
    opens? = String.contains?(trimmed, "{-")
    closes? = String.contains?(trimmed, "-}")

    cond do
      in_block_comment and closes? and not opens? -> false
      in_block_comment -> true
      opens? and not closes? -> true
      true -> false
    end
  end

  @spec top_level_declaration(term()) :: term()
  defp top_level_declaration(line) do
    trimmed = String.trim_leading(line)

    cond do
      trimmed == "--}" ->
        {:comment_close, nil}

      String.starts_with?(trimmed, "--") ->
        {:comment, nil}

      String.starts_with?(trimmed, "{-|") ->
        {:doc_comment, nil}

      String.starts_with?(trimmed, "infix ") ->
        {:fixity, nil}

      String.starts_with?(trimmed, "type alias ") ->
        named_upper_declaration(trimmed, "type alias ")

      type_declaration_line?(line) ->
        named_upper_declaration(trimmed, "type ")

      String.starts_with?(trimmed, "port ") ->
        named_lower_declaration(trimmed, "port ")

      true ->
        named_lower_top_level_declaration(trimmed)
    end
  end

  @spec named_upper_declaration(term(), term()) :: term()
  defp named_upper_declaration(trimmed, prefix) do
    rest =
      String.slice(trimmed, String.length(prefix), String.length(trimmed))
      |> String.trim_leading()

    {name, _} = take_upper_identifier(rest)
    if name == "", do: nil, else: {:definition, name}
  end

  @spec named_lower_declaration(term(), term()) :: term()
  defp named_lower_declaration(trimmed, prefix) do
    rest =
      String.slice(trimmed, String.length(prefix), String.length(trimmed))
      |> String.trim_leading()

    {name, _} = take_lower_identifier(rest)
    if name == "", do: nil, else: {:definition, name}
  end

  @spec named_lower_top_level_declaration(term()) :: term()
  defp named_lower_top_level_declaration(trimmed) do
    case take_lower_identifier(trimmed) do
      {"", _rest} ->
        nil

      {name, rest} ->
        rest = String.trim_leading(rest)
        reserved? = name in ["infix", "port", "type", "import", "module", "effect"]

        cond do
          reserved? ->
            nil

          String.starts_with?(rest, ":") ->
            {:annotation, name}

          String.contains?(rest, "=") ->
            {:definition, name}

          rest == "" ->
            {:starter, name}

          true ->
            nil
        end
    end
  end

  @spec declaration_spacing(term(), term()) :: term()
  defp declaration_spacing(prev, decl) do
    cond do
      annotation_definition_pair?(prev, decl) ->
        0

      starter_definition_pair?(prev, decl) ->
        0

      starter_comment_pair?(prev, decl) ->
        0

      definition_continuation_pair?(prev, decl) ->
        0

      prev == {:fixity, nil} and decl == {:fixity, nil} ->
        0

      prev == {:comment, nil} and decl == {:comment, nil} ->
        0

      prev == {:comment_close, nil} or decl == {:comment_close, nil} ->
        0

      prev == {:doc_comment, nil} and
          (match?({:definition, _}, decl) or match?({:annotation, _}, decl)) ->
        0

      true ->
        2
    end
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec emit_blanks(term(), term()) :: term()
  defp emit_blanks(acc, 0), do: acc
  defp emit_blanks(acc, n) when n > 0, do: emit_blanks(["" | acc], n - 1)

  @spec type_declaration_line?(term()) :: term()
  defp type_declaration_line?(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "type ") do
      next = String.at(trimmed, 5)

      case next do
        nil -> false
        <<c::utf8>> -> c in ?A..?Z
        _ -> false
      end
    else
      false
    end
  end

  @spec take_lower_identifier(term()) :: term()
  defp take_lower_identifier(rest) do
    chars = String.graphemes(rest)
    {name_chars, remaining} = Enum.split_while(chars, &lower_identifier_char?/1)

    case name_chars do
      [first | _] when first >= "a" and first <= "z" ->
        {Enum.join(name_chars), Enum.join(remaining)}

      _ ->
        {"", rest}
    end
  end

  @spec take_upper_identifier(term()) :: term()
  defp take_upper_identifier(rest) do
    chars = String.graphemes(rest)
    {name_chars, remaining} = Enum.split_while(chars, &upper_identifier_char?/1)

    case name_chars do
      [first | _] when first >= "A" and first <= "Z" ->
        {Enum.join(name_chars), Enum.join(remaining)}

      _ ->
        {"", rest}
    end
  end

  @spec lower_identifier_char?(term()) :: term()
  defp lower_identifier_char?(char) when is_binary(char) do
    case String.to_charlist(char) do
      [c] ->
        c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?_ or c == ?'

      _ ->
        false
    end
  end

  @spec upper_identifier_char?(term()) :: term()
  defp upper_identifier_char?(char) when is_binary(char) do
    case String.to_charlist(char) do
      [c] ->
        c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?_ or c == ?'

      _ ->
        false
    end
  end

  @spec annotation_definition_pair?(term(), term()) :: term()
  defp annotation_definition_pair?({:annotation, name}, {:definition, name}), do: true
  defp annotation_definition_pair?(_, _), do: false

  @spec starter_definition_pair?(term(), term()) :: term()
  defp starter_definition_pair?({:starter, name}, {:definition, name}) when not is_nil(name),
    do: true

  defp starter_definition_pair?(_, _), do: false

  @spec starter_comment_pair?(term(), term()) :: term()
  defp starter_comment_pair?({:starter, _}, {:comment, nil}), do: true
  defp starter_comment_pair?(_, _), do: false

  @spec definition_continuation_pair?(term(), term()) :: term()
  defp definition_continuation_pair?({:definition, name}, {:definition, name})
       when not is_nil(name),
       do: true

  defp definition_continuation_pair?(_, _), do: false

  @spec declaration_state_after(term(), term(), term()) :: term()
  defp declaration_state_after({:starter, name} = prev, {:comment, nil}, 0) when not is_nil(name),
    do: prev

  defp declaration_state_after(_prev, decl, _pending_blanks), do: decl
end
