defmodule ElmEx.Frontend.GeneratedDeclarationParser do
  @moduledoc """
  Generated declaration parser adapter for single-line declarations.
  """

  alias ElmEx.Types

  @type decl_result :: {:ok, Types.decl_parser_output()} | :none

  @type scanned_line :: %{
          line_no: pos_integer(),
          raw_line: String.t(),
          trimmed: String.t(),
          indented?: boolean(),
          decl: decl_result(),
          function_header:
            {:ok,
             %{
               required(:name) => String.t(),
               required(:args) => [String.t()],
               required(:body) => String.t(),
               optional(:header_source) => String.t()
             }} | :none
        }

  @spec parse_line(String.t()) :: {:ok, Types.decl_parser_output()} | {:error, Types.parse_error_reason()}
  def parse_line(source) when is_binary(source) do
    with {:ok, tokens, _line} <- :elm_ex_decl_lexer.string(String.to_charlist(source)),
         {:ok, decl} <- :elm_ex_decl_parser.parse(tokens) do
      {:ok, decl}
    else
      {:error, reason, _line} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse_function_header_line(String.t(), String.t()) ::
          {:ok, %{name: String.t(), args: [String.t()], body: String.t(), header_source: String.t()}}
          | {:error, Types.parse_error_reason() | atom()}
  def parse_function_header_line(source, raw_source)
      when is_binary(source) and is_binary(raw_source) do
    raw_header_source =
      case split_on_definition_equals(raw_source) do
        {:ok, left, _right} -> String.trim_trailing(left) <> " ="
        :error -> String.trim_trailing(raw_source)
      end

    case split_on_definition_equals(source) do
      {:ok, left, right} ->
        header_source = String.trim(left) <> " ="

        with {:ok, {:function_header, name, args}} <- parse_line(header_source) do
          {:ok, %{name: name, args: args, body: String.trim(right), header_source: raw_header_source}}
        else
          _ ->
            case parse_complex_function_header(String.trim(left), String.trim(right)) do
              {:ok, parsed} -> {:ok, Map.put(parsed, :header_source, raw_header_source)}
              other -> other
            end
        end

      :error ->
        {:error, :missing_equals}
    end
  end

  @spec split_on_definition_equals(String.t()) :: {:ok, String.t(), String.t()} | :error
  defp split_on_definition_equals(source) when is_binary(source) do
    case definition_equals_index(source, 0, 0, nil) do
      nil -> :error
      idx -> {:ok, String.slice(source, 0, idx), String.slice(source, idx + 1..-1//1)}
    end
  end

  @spec definition_equals_index(String.t(), non_neg_integer(), non_neg_integer(), String.t() | nil) ::
          non_neg_integer() | nil
  defp definition_equals_index(<<>>, _idx, _depth, _quote), do: nil

  defp definition_equals_index(<<"=", _rest::binary>>, idx, 0, nil), do: idx

  defp definition_equals_index(<<char::utf8, rest::binary>>, idx, depth, quote) do
    ch = <<char::utf8>>

    cond do
      quote != nil and ch == quote ->
        definition_equals_index(rest, idx + byte_size(ch), depth, nil)

      quote == nil and ch in ["\"", "'"] ->
        definition_equals_index(rest, idx + byte_size(ch), depth, ch)

      quote == nil and ch in ["(", "[", "{"] ->
        definition_equals_index(rest, idx + byte_size(ch), depth + 1, quote)

      quote == nil and ch in [")", "]", "}"] and depth > 0 ->
        definition_equals_index(rest, idx + byte_size(ch), depth - 1, quote)

      true ->
        definition_equals_index(rest, idx + byte_size(ch), depth, quote)
    end
  end

  @spec parse_complex_function_header(String.t(), String.t()) ::
          {:ok, %{name: String.t(), args: [String.t()], body: String.t()}}
          | {:error, Types.parse_error_reason() | atom()}
  defp parse_complex_function_header(left, right)
       when is_binary(left) and is_binary(right) do
    trimmed_left = String.trim(left)

    case Regex.run(~r/^port\s+([a-z][A-Za-z0-9_']*)\s*$/u, trimmed_left, capture: :all_but_first) do
      [name] ->
        {:ok, %{name: name, args: [], body: String.trim(right)}}

      _ ->
        parse_non_port_complex_function_header(trimmed_left, right)
    end
  end

  @spec parse_non_port_complex_function_header(String.t(), String.t()) ::
          {:ok, %{name: String.t(), args: [String.t()], body: String.t()}}
          | {:error, Types.parse_error_reason() | atom()}
  defp parse_non_port_complex_function_header(trimmed_left, right)
       when is_binary(trimmed_left) and is_binary(right) do
    cond do
      String.starts_with?(trimmed_left, "{") or String.starts_with?(trimmed_left, "(") ->
        {:ok, %{name: trimmed_left, args: [], body: String.trim(right)}}

      true ->
        case Regex.run(~r/^([a-z][A-Za-z0-9_']*)\s+(.+)$/u, trimmed_left, capture: :all_but_first) do
          [name, arg_source] ->
            if name in ["type", "module", "import", "port", "effect"] or
                 (name == "infix" and not infix_function_definition_line?(trimmed_left <> " =")) do
              {:error, :invalid_function_header}
            else
              args = split_top_level_spaces(arg_source)

              if args == [] do
                {:error, :invalid_function_header}
              else
                {:ok, %{name: name, args: args, body: String.trim(right)}}
              end
            end

          _ ->
            {:error, :invalid_function_header}
        end
    end
  end

  @spec split_top_level_spaces(String.t()) :: [String.t()]
  defp split_top_level_spaces(source) when is_binary(source) do
    source
    |> String.trim()
    |> do_split_top_level_spaces([], "", 0, nil)
    |> Enum.reverse()
  end

  @spec do_split_top_level_spaces(
          String.t(),
          [String.t()],
          String.t(),
          integer(),
          nil | String.t()
        ) ::
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

  @spec parse_operator_signature_line(String.t()) ::
          {:ok, {:function_signature, String.t(), String.t()}} | :error
  defp parse_operator_signature_line(trimmed) when is_binary(trimmed) do
    case Regex.run(~r/^(\([^)]+\))\s*:\s*(.+)$/u, trimmed, capture: :all_but_first) do
      [name, type] -> {:ok, {:function_signature, name, String.trim(type)}}
      _ -> :error
    end
  end

  @spec scan_lines(String.t()) :: [scanned_line()]
  def scan_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_reduce(0, fn {line, line_no}, comment_depth ->
      {code_line, new_depth} = strip_block_comments_on_line(line, comment_depth)
      trimmed = String.trim(code_line)
      indented? = String.starts_with?(line, " ") or String.starts_with?(line, "\t")
      parse_allowed? = trimmed != "" and not String.starts_with?(trimmed, "--")

      decl =
        if parse_allowed? and
             (not indented? or String.starts_with?(trimmed, "|") or
                String.starts_with?(trimmed, "=")) do
          case parse_line(trimmed) do
            {:ok, parsed} ->
              {:ok, parsed}

            _ ->
              case parse_operator_signature_line(trimmed) do
                {:ok, sig} -> {:ok, sig}
                :error -> :none
              end
          end
        else
          :none
        end

      function_header =
        if parse_allowed? and not indented? and String.contains?(code_line, "=") and
             (decl == :none or match?({:ok, {:function_header, _, _}}, decl)) and
             not non_function_declaration_prefix?(trimmed) do
          case parse_function_header_line(String.trim_trailing(code_line), String.trim_trailing(line)) do
            {:ok, parsed} -> {:ok, parsed}
            _ -> :none
          end
        else
          :none
        end

      scanned = %{
        line_no: line_no,
        raw_line: line,
        trimmed: trimmed,
        indented?: indented?,
        decl: decl,
        function_header: function_header
      }

      {scanned, new_depth}
    end)
    |> elem(0)
  end

  @doc false
  @spec strip_declaration_comments(String.t()) :: String.t()
  def strip_declaration_comments(line) when is_binary(line) do
    {stripped, _} = strip_block_comments_on_line(line, 0)
    String.trim(stripped)
  end

  @spec strip_block_comments_on_line(String.t(), non_neg_integer()) ::
          {String.t(), non_neg_integer()}
  defp strip_block_comments_on_line(line, depth) when is_binary(line) and depth >= 0 do
  do_strip_block_comments_on_line(line, depth, "")
  end

  defp do_strip_block_comments_on_line(<<>>, depth, acc), do: {acc, depth}

  defp do_strip_block_comments_on_line(source, depth, acc) do
    case depth do
      0 ->
        case source do
          <<"{-", rest::binary>> ->
            do_strip_block_comments_on_line(rest, 1, acc <> "  ")

          <<char::utf8, rest::binary>> ->
            do_strip_block_comments_on_line(rest, 0, acc <> <<char::utf8>>)
        end

      n when n > 0 ->
        case source do
          <<"{-", rest::binary>> ->
            do_strip_block_comments_on_line(rest, n + 1, acc)

          <<"-}", rest::binary>> ->
            do_strip_block_comments_on_line(rest, n - 1, acc <> "  ")

          <<_char::utf8, rest::binary>> ->
            do_strip_block_comments_on_line(rest, n, acc <> " ")

          <<>> ->
            {acc, n}
        end
    end
  end

  @spec non_function_declaration_prefix?(String.t()) :: boolean()
  defp non_function_declaration_prefix?(trimmed) when is_binary(trimmed) do
    String.starts_with?(trimmed, "type ") or
      String.starts_with?(trimmed, "module ") or
      String.starts_with?(trimmed, "import ") or
      (String.starts_with?(trimmed, "port ") and
         not Regex.match?(~r/^port\s+[a-z][A-Za-z0-9_']*\s*=/u, trimmed)) or
      String.starts_with?(trimmed, "effect module ") or
      (Regex.match?(~r/^infix(?:l|r)?\s+/u, trimmed) and
         not infix_function_definition_line?(trimmed))
  end

  @spec infix_function_definition_line?(String.t()) :: boolean()
  defp infix_function_definition_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^infix(?:l|r)?\s+[a-z][A-Za-z0-9_']*(?:\s+[a-z][A-Za-z0-9_']*)*\s*=/u, trimmed)
  end
end
