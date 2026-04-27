defmodule ElmEx.Frontend.GeneratedDeclarationParser do
  @moduledoc """
  Generated declaration parser adapter for single-line declarations.
  """

  @type scanned_line :: %{
          line_no: pos_integer(),
          raw_line: String.t(),
          trimmed: String.t(),
          indented?: boolean(),
          decl: {:ok, tuple()} | :none,
          function_header:
            {:ok, %{name: String.t(), args: [String.t()], body: String.t()}} | :none
        }

  @spec parse_line(String.t()) :: {:ok, tuple()} | {:error, term()}
  def parse_line(source) when is_binary(source) do
    with {:ok, tokens, _line} <- :elm_ex_decl_lexer.string(String.to_charlist(source)),
         {:ok, decl} <- :elm_ex_decl_parser.parse(tokens) do
      {:ok, decl}
    else
      {:error, reason, _line} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse_function_header_line(String.t()) ::
          {:ok, %{name: String.t(), args: [String.t()], body: String.t()}} | {:error, term()}
  def parse_function_header_line(source) when is_binary(source) do
    case String.split(source, "=", parts: 2) do
      [left, right] ->
        header_source = String.trim(left) <> " ="

        with {:ok, {:function_header, name, args}} <- parse_line(header_source) do
          {:ok, %{name: name, args: args, body: String.trim(right)}}
        else
          _ -> parse_complex_function_header(String.trim(left), String.trim(right))
        end

      _ ->
        {:error, :missing_equals}
    end
  end

  @spec parse_complex_function_header(String.t(), String.t()) ::
          {:ok, %{name: String.t(), args: [String.t()], body: String.t()}} | {:error, term()}
  defp parse_complex_function_header(left, right)
       when is_binary(left) and is_binary(right) do
    case Regex.run(~r/^([a-z][A-Za-z0-9_']*)\s+(.+)$/u, left, capture: :all_but_first) do
      [name, arg_source] ->
        if name in ["type", "module", "import", "port", "effect", "infix"] do
          {:error, :invalid_function_header}
        else
        args = split_top_level_spaces(arg_source)

        if args == [] do
          {:error, :invalid_function_header}
        else
          lambda_body = "\\" <> Enum.join(args, " ") <> " -> " <> right
          {:ok, %{name: name, args: [], body: String.trim(lambda_body)}}
        end
        end

      _ ->
        {:error, :invalid_function_header}
    end
  end

  @spec split_top_level_spaces(String.t()) :: [String.t()]
  defp split_top_level_spaces(source) when is_binary(source) do
    source
    |> String.trim()
    |> do_split_top_level_spaces([], "", 0, nil)
    |> Enum.reverse()
  end

  @spec do_split_top_level_spaces(String.t(), [String.t()], String.t(), integer(), nil | String.t()) ::
          [String.t()]
  defp do_split_top_level_spaces(<<>>, acc, current, _depth, _quote) do
    token = String.trim(current)
    if token == "", do: acc, else: [token | acc]
  end

  defp do_split_top_level_spaces(<<char::utf8, rest::binary>>, acc, current, depth, quote) do
    ch = <<char::utf8>>

    cond do
      quote != nil and ch == quote ->
        do_split_top_level_spaces(rest, acc, current <> ch, depth, nil)

      quote == nil and (ch == "\"" or ch == "'") ->
        do_split_top_level_spaces(rest, acc, current <> ch, depth, ch)

      quote == nil and ch in ["(", "[", "{"] ->
        do_split_top_level_spaces(rest, acc, current <> ch, depth + 1, quote)

      quote == nil and ch in [")", "]", "}"] and depth > 0 ->
        do_split_top_level_spaces(rest, acc, current <> ch, depth - 1, quote)

      quote == nil and depth == 0 and String.trim(ch) == "" ->
        token = String.trim(current)

        next_acc =
          if token == "" do
            acc
          else
            [token | acc]
          end

        do_split_top_level_spaces(rest, next_acc, "", depth, quote)

      true ->
        do_split_top_level_spaces(rest, acc, current <> ch, depth, quote)
    end
  end

  @spec scan_lines(String.t()) :: [scanned_line()]
  def scan_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_no} ->
      trimmed = String.trim(line)
      indented? = String.starts_with?(line, " ") or String.starts_with?(line, "\t")
      parse_allowed? = trimmed != "" and not String.starts_with?(trimmed, "--")

      decl =
        if parse_allowed? and
             (not indented? or String.starts_with?(trimmed, "|") or
                String.starts_with?(trimmed, "=")) do
          case parse_line(trimmed) do
            {:ok, parsed} -> {:ok, parsed}
            _ -> :none
          end
        else
          :none
        end

      function_header =
        if parse_allowed? and not indented? and String.contains?(line, "=") and
             (decl == :none or match?({:ok, {:function_header, _, _}}, decl)) and
             not non_function_declaration_prefix?(trimmed) do
          case parse_function_header_line(String.trim_trailing(line)) do
            {:ok, parsed} -> {:ok, parsed}
            _ -> :none
          end
        else
          :none
        end

      %{
        line_no: line_no,
        raw_line: line,
        trimmed: trimmed,
        indented?: indented?,
        decl: decl,
        function_header: function_header
      }
    end)
  end

  @spec non_function_declaration_prefix?(String.t()) :: boolean()
  defp non_function_declaration_prefix?(trimmed) when is_binary(trimmed) do
    String.starts_with?(trimmed, "type ") or
      String.starts_with?(trimmed, "module ") or
      String.starts_with?(trimmed, "import ") or
      String.starts_with?(trimmed, "port ") or
      String.starts_with?(trimmed, "effect module ") or
      String.starts_with?(trimmed, "infix ")
  end
end
