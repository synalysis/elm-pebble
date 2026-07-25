defmodule ElmEx.Frontend.SourceComments do
  @moduledoc """
  Extract and merge Elm source comments for pretty-printing.

  Comments are collected from the original source and reinserted after AST-based
  formatting so parse → print preserves documentation and line comments.
  """

  @type comment_kind :: :line | :block | :doc

  @type t :: %{
          required(:kind) => comment_kind(),
          required(:text) => String.t(),
          required(:line) => pos_integer(),
          optional(:after_name) => String.t() | nil
        }

  @doc """
  Extract standalone comments and doc comments from source text.
  """
  @spec extract(String.t(), String.t(), ElmEx.Frontend.Module.t()) :: [t()]
  def extract(_path, source, mod) when is_binary(source) do
    lines = String.split(source, "\n", trim: false)

    lines
    |> extract_comments(mod, 1, [])
    |> Enum.reverse()
  end

  @doc """
  Drop comments already preserved in module header/import/body-gap regions.
  """
  @spec for_body_region([t()], pos_integer()) :: [t()]
  def for_body_region(comments, body_line_start) when is_list(comments) do
    Enum.reject(comments, fn %{line: line} -> line < body_line_start end)
  end
  @spec merge(String.t(), [t()]) :: String.t()
  def merge(formatted, comments) when is_binary(formatted) and is_list(comments) do
    formatted
    |> String.split("\n", trim: false)
    |> merge_lines(comments, 1, [])
    |> Enum.join("\n")
    |> ensure_terminal_newline()
  end

  defp extract_comments([], _mod, _line_no, acc), do: acc

  defp extract_comments([line | rest], mod, line_no, acc) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "{-|") ->
        {doc_lines, remaining, next_line} = read_doc_block([line | rest], line_no, 0)
        doc_text = Enum.join(doc_lines, "\n")
        after_name = declaration_name_after(remaining, mod)

        extract_comments(
          remaining,
          mod,
          next_line,
          [%{kind: :doc, text: doc_text, line: line_no, after_name: after_name} | acc]
        )

      String.starts_with?(trimmed, "--") and comment_only_line?(trimmed) ->
        extract_comments(
          rest,
          mod,
          line_no + 1,
          [%{kind: :line, text: String.trim_trailing(line), line: line_no, after_name: nil} | acc]
        )

      String.starts_with?(trimmed, "{-") and String.ends_with?(String.trim_trailing(trimmed), "-}") and
          not String.starts_with?(trimmed, "{-|") ->
        extract_comments(
          rest,
          mod,
          line_no + 1,
          [%{kind: :block, text: String.trim_trailing(line), line: line_no, after_name: nil} | acc]
        )

      true ->
        extract_comments(rest, mod, line_no + 1, acc)
    end
  end

  defp read_doc_block(lines, start_line, depth) do
    case lines do
      [] ->
        {[], [], start_line}

      [line | rest] ->
        depth = advance_comment_depth(line, depth)
        doc_lines = [line]

        if doc_comment_end_line?(line) and depth == 0 do
          {doc_lines, rest, start_line + 1}
        else
          {more_lines, remaining, next_line} = read_doc_block(rest, start_line + 1, depth)
          {doc_lines ++ more_lines, remaining, next_line}
        end
    end
  end

  defp doc_comment_end_line?(line) do
    String.trim_leading(line) |> String.ends_with?("-}")
  end

  defp advance_comment_depth(line, depth) when is_binary(line) do
    do_advance_comment_depth(line, depth)
  end

  defp do_advance_comment_depth(<<>>, depth), do: depth

  defp do_advance_comment_depth(<<"{-", rest::binary>>, depth) do
    do_advance_comment_depth(rest, depth + 1)
  end

  defp do_advance_comment_depth(<<"-}", rest::binary>>, depth) when depth > 0 do
    do_advance_comment_depth(rest, depth - 1)
  end

  defp do_advance_comment_depth(<<_char::utf8, rest::binary>>, depth) do
    do_advance_comment_depth(rest, depth)
  end

  defp declaration_name_after(lines, mod) do
    lines
    |> Enum.find_value(&declaration_name_from_line/1) ||
      first_declaration_name(mod)
  end

  defp first_declaration_name(%{declarations: [first | _]}), do: Map.get(first, :name)
  defp first_declaration_name(_), do: nil

  defp comment_only_line?(trimmed) do
    String.starts_with?(trimmed, "--") or
      (String.starts_with?(trimmed, "{-") and String.ends_with?(trimmed, "-}"))
  end

  defp merge_lines([], _comments, _line_no, acc), do: acc

  defp merge_lines([line | rest], comments, line_no, acc) do
    declaration_name = declaration_name_from_line(line)

    matching =
      Enum.filter(comments, fn
        %{kind: :doc, after_name: name} when is_binary(name) -> name == declaration_name
        _ -> false
      end)

    doc_lines =
      matching
      |> Enum.flat_map(fn %{text: text} -> String.split(text, "\n", trim: false) end)

    merge_lines(rest, comments -- matching, line_no + 1, acc ++ doc_lines ++ [line])
  end

  defp declaration_name_from_line(line) do
    trimmed = String.trim(line)

    cond do
      Regex.match?(~r/^port\s+([a-z][A-Za-z0-9_']*)\s*:/u, trimmed) ->
        capture(trimmed, ~r/^port\s+([a-z][A-Za-z0-9_']*)\s*:/u)

      Regex.match?(~r/^([a-z][A-Za-z0-9_']*)\s*:/u, trimmed) ->
        capture(trimmed, ~r/^([a-z][A-Za-z0-9_']*)\s*:/u)

      Regex.match?(~r/^([a-z][A-Za-z0-9_']*)\s*=/u, trimmed) ->
        capture(trimmed, ~r/^([a-z][A-Za-z0-9_']*)\s*=/u)

      Regex.match?(~r/^type alias\s+([A-Z][A-Za-z0-9_']*)/u, trimmed) ->
        capture(trimmed, ~r/^type alias\s+([A-Z][A-Za-z0-9_']*)/u)

      Regex.match?(~r/^type\s+([A-Z][A-Za-z0-9_']*)/u, trimmed) ->
        capture(trimmed, ~r/^type\s+([A-Z][A-Za-z0-9_']*)/u)

      true ->
        nil
    end
  end

  defp capture(text, regex) do
    case Regex.run(regex, text, capture: :all_but_first) do
      [name] -> name
      _ -> nil
    end
  end

  defp ensure_terminal_newline(""), do: "\n"

  defp ensure_terminal_newline(value) do
    if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
  end
end
