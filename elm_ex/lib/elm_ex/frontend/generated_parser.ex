defmodule ElmEx.Frontend.GeneratedParser do
  @moduledoc """
  Generated-parser frontend that emits the full module AST contract.

  ## Header Metadata Contract

  `parse_file/1` augments `%ElmEx.Frontend.Module{}` with parser-derived header metadata:

  - `module_exposing`: `nil | ".." | [String.t()]`
  - `import_entries`: `%{"module" => String.t(), "as" => String.t() | nil, "exposing" => nil | ".." | [String.t()]}[]`
  - `port_module`: `boolean()`
  - `ports`: `[String.t()]`

  The metadata is derived from `:elm_ex_elm_lexer` tokens (single source of truth).

  ## Metadata Normalization Rules

  For metadata extraction only (not AST declaration parsing):

  - Remove a leading UTF-8 BOM (`EF BB BF`) when present.
  - Remove non-nested block comments matching `{- ... -}`.
  - Tokenize normalized source with `:elm_ex_elm_lexer`.
  - Parse module/import subset with `:elm_ex_elm_parser` using filtered metadata tokens.
  - Derive exposing/port details from the lexer token stream grouped by physical lines.

  This contract intentionally centralizes normalization and header interpretation in `elm_ex`
  so IDE/MCP consumers do not implement duplicate source scanners.
  """

  alias ElmEx.Frontend.GeneratedContractBuilder
  alias ElmEx.Frontend.AstContract

  @typep token() :: tuple()
  @typep tokens() :: [token()]

  @spec parse_file(String.t()) :: {:ok, ElmEx.Frontend.Module.t()} | {:error, map()}
  def parse_file(path) do
    with {:ok, source} <- File.read(path),
         {:ok, metadata} <- parse_metadata(source) do
      module_name = metadata.module
      imports = metadata.imports
      full_imports = (imports ++ ElmEx.Frontend.DefaultImports.module_names()) |> Enum.uniq()

      module =
        GeneratedContractBuilder.build(path, source, module_name, full_imports)
        |> Map.put(:module_exposing, metadata.module_exposing)
        |> Map.put(:import_entries, metadata.import_entries)
        |> Map.put(:port_module, metadata.port_module)
        |> Map.put(:ports, metadata.ports)

      case AstContract.validate_module(module) do
        :ok -> {:ok, module}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec parse_metadata(String.t()) :: {:ok, map()} | {:error, map()}
  defp parse_metadata(source) do
    metadata_source = normalize_source_for_metadata(source)

    with {:ok, tokens, _line} <- :elm_ex_elm_lexer.string(String.to_charlist(metadata_source)) do
      lines = split_token_lines(tokens)

      module_name =
        Enum.find_value(lines, fn
          [{:module_kw, _}, {:upper_id, _, name} | _] -> name
          [{:port_kw, _}, {:module_kw, _}, {:upper_id, _, name} | _] -> name
          [{:effect_kw, _}, {:module_kw, _}, {:upper_id, _, name} | _] -> name
          _ -> nil
        end)

      if is_binary(module_name) do
        %{
          module_exposing: module_exposing,
          import_entries: import_entries,
          port_module: port_module?,
          ports: ports
        } = extract_header_metadata(tokens)

        imports =
          import_entries
          |> Enum.map(& &1["module"])

        {:ok,
         %{
           module: module_name,
           imports: imports,
           module_exposing: module_exposing,
           import_entries: import_entries,
           port_module: port_module?,
           ports: ports
         }}
      else
        {:error, %{kind: :parse_error, reason: :missing_module_header, line: 1}}
      end
    else
      {:error, reason, line} -> {:error, %{kind: :parse_error, reason: reason, line: line}}
    end
  end

  @doc false
  @spec normalize_source_for_metadata(String.t()) :: String.t()
  def normalize_source_for_metadata(source) when is_binary(source) do
    source
    |> strip_leading_utf8_bom()
    |> then(&Regex.replace(~r/\{-[\s\S]*?-\}/u, &1, ""))
  end

  @spec strip_leading_utf8_bom(String.t()) :: String.t()
  defp strip_leading_utf8_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_leading_utf8_bom(source), do: source

  @doc false
  @spec metadata_subset_tokens(list()) :: list()
  def metadata_subset_tokens(tokens) when is_list(tokens) do
    tokens
    |> split_token_lines()
    |> select_metadata_lines()
    |> Enum.map(fn line -> Enum.filter(line, &metadata_subset_token?/1) end)
    |> Enum.map(&sanitize_metadata_line/1)
    |> Enum.reject(&(&1 == []))
    |> join_lines_with_newline_tokens()
    |> normalize_metadata_exposing_tail()
  end

  @spec sanitize_metadata_line(tokens()) :: tokens()
  defp sanitize_metadata_line([
         {:effect_kw, _} = effect_tok,
         {:module_kw, _} = module_tok,
         {:upper_id, _, _} = name_tok | rest
       ]) do
    exposing_tail =
      rest
      |> Enum.drop_while(&(token_kind(&1) != :exposing_kw))
      |> normalize_metadata_exposing_tail()

    [effect_tok, module_tok, name_tok] ++ exposing_tail
  end

  defp sanitize_metadata_line([
         {:module_kw, line} = module_tok,
         {:upper_id, _, _} = name_tok,
         {:lparen, _},
         {:dotdot, _},
         {:rparen, _},
         {:lower_id, _, "where"} | _rest
       ]) do
    [
      module_tok,
      name_tok,
      {:exposing_kw, line},
      {:lparen, line},
      {:dotdot, line},
      {:rparen, line}
    ]
  end

  defp sanitize_metadata_line(line) do
    normalize_metadata_exposing_tail(line)
  end

  @spec select_metadata_lines([tokens()]) :: [tokens()]
  defp select_metadata_lines(lines) when is_list(lines) do
    {selected, _active_exposing, _seen_lparen, _depth} =
      Enum.reduce(lines, {[], false, false, 0}, fn line,
                                                   {acc, active_exposing, seen_lparen, depth} ->
        subset = Enum.filter(line, &metadata_subset_token?/1)
        starts_header = metadata_header_line?(line)
        keep_line = starts_header or active_exposing

        if keep_line and subset != [] do
          line_delta = paren_delta(subset)

          {next_active_exposing, next_seen_lparen, next_depth} =
            cond do
              starts_header and line_has_kind?(subset, :exposing_kw) ->
                header_seen_lparen = line_has_kind?(subset, :lparen)
                header_depth = line_delta
                still_open = if(header_seen_lparen, do: header_depth > 0, else: true)
                {still_open, header_seen_lparen, header_depth}

              active_exposing ->
                updated_seen_lparen = seen_lparen or line_has_kind?(subset, :lparen)
                updated_depth = depth + line_delta
                still_open = if(updated_seen_lparen, do: updated_depth > 0, else: true)
                {still_open, updated_seen_lparen, updated_depth}

              true ->
                {false, false, 0}
            end

          {[line | acc], next_active_exposing, next_seen_lparen, next_depth}
        else
          {acc, active_exposing, seen_lparen, depth}
        end
      end)

    Enum.reverse(selected)
  end

  @spec paren_delta(tokens()) :: integer()
  defp paren_delta(tokens) when is_list(tokens) do
    Enum.reduce(tokens, 0, fn
      {:lparen, _}, acc -> acc + 1
      {:rparen, _}, acc -> acc - 1
      _tok, acc -> acc
    end)
  end

  @spec line_has_kind?(tokens(), atom()) :: boolean()
  defp line_has_kind?(tokens, kind) when is_list(tokens) and is_atom(kind) do
    Enum.any?(tokens, fn
      {^kind, _} -> true
      {^kind, _, _} -> true
      _ -> false
    end)
  end

  @spec metadata_header_line?(tokens()) :: boolean()
  defp metadata_header_line?(line) do
    match?([{:module_kw, _} | _], line) or
      match?([{:import_kw, _} | _], line) or
      match?([{:effect_kw, _}, {:module_kw, _}, {:upper_id, _, _} | _], line) or
      match?([{:port_kw, _}, {:module_kw, _} | _], line)
  end

  @spec metadata_subset_token?(token()) :: boolean()
  defp metadata_subset_token?({kind, _line})
       when kind in [
              :module_kw,
              :effect_kw,
              :import_kw,
              :as_kw,
              :exposing_kw,
              :port_kw,
              :dotdot,
              :comma,
              :lparen,
              :rparen,
              :colon
            ],
       do: true

  defp metadata_subset_token?({kind, _line, _value}) when kind in [:upper_id, :lower_id], do: true
  defp metadata_subset_token?(_), do: false

  @spec join_lines_with_newline_tokens([tokens()]) :: tokens()
  defp join_lines_with_newline_tokens(lines) do
    total = length(lines)

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      if idx < total - 1 do
        line ++ [{:newline, token_line(line)}]
      else
        line
      end
    end)
  end

  @spec token_line(tokens()) :: non_neg_integer()
  defp token_line([{_kind, line} | _]) when is_integer(line), do: line
  defp token_line([{_kind, line, _value} | _]) when is_integer(line), do: line
  defp token_line(_), do: 1

  @spec extract_header_metadata(tokens()) :: %{
          module_exposing: term(),
          import_entries: [map()],
          port_module: boolean(),
          ports: [String.t()]
        }
  defp extract_header_metadata(tokens) when is_list(tokens) do
    lines = split_token_lines(tokens)
    first_idx = Enum.find_index(lines, &(&1 != []))
    first_line = if is_integer(first_idx), do: Enum.at(lines, first_idx), else: nil

    {port_module, module_exposing} =
      case first_line do
        [{:port_kw, _}, {:module_kw, _}, {:upper_id, _, _} | _] ->
          {true, parse_exposing_from_lines(lines, first_idx)}

        [{:effect_kw, _}, {:module_kw, _}, {:upper_id, _, _} | _] ->
          {false, parse_exposing_from_lines(lines, first_idx)}

        [{:module_kw, _}, {:upper_id, _, _} | _] ->
          {false, parse_exposing_from_lines(lines, first_idx)}

        _ ->
          {false, nil}
      end

    import_entries =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} ->
        match?([{:import_kw, _}, {:upper_id, _, _} | _], line)
      end)
      |> Enum.map(fn {line, idx} -> parse_import_entry(line, lines, idx) end)
      |> Enum.reject(&is_nil/1)

    ports =
      lines
      |> Enum.filter(&match?([{:port_kw, _}, {:lower_id, _, _} | _], &1))
      |> Enum.map(fn [{:port_kw, _}, {:lower_id, _, name} | _] -> name end)
      |> Enum.uniq()

    %{
      module_exposing: module_exposing,
      import_entries: import_entries,
      port_module: port_module,
      ports: ports
    }
  end

  @spec split_token_lines(tokens()) :: [tokens()]
  defp split_token_lines(tokens) do
    tokens
    |> Enum.reduce([[]], fn
      {:newline, _}, acc ->
        [[] | acc]

      tok, [line | rest] ->
        [[tok | line] | rest]
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  @spec parse_import_entry(tokens(), [tokens()], non_neg_integer()) :: map() | nil
  defp parse_import_entry([{:import_kw, _}, {:upper_id, _, module_segment} | rest], lines, idx) do
    {module_parts, line} = take_module_path(rest, [module_segment])
    module_name = Enum.join(module_parts, ".")

    as_name =
      case line do
        [{:as_kw, _}, {:upper_id, _, alias_name} | _] -> alias_name
        _ -> nil
      end

    exposing = parse_exposing_from_lines(lines, idx)

    %{
      "module" => module_name,
      "as" => as_name,
      "exposing" => exposing
    }
  end

  defp parse_import_entry(_, _, _), do: nil

  defp take_module_path([{:dot, _}, {:upper_id, _, segment} | rest], acc) do
    take_module_path(rest, acc ++ [segment])
  end

  defp take_module_path(rest, []), do: {[], rest}
  defp take_module_path(rest, acc), do: {acc, rest}

  @spec normalize_metadata_exposing_tail(tokens()) :: tokens()
  defp normalize_metadata_exposing_tail(tokens) when is_list(tokens) do
    case Enum.split_while(tokens, &(token_kind(&1) != :exposing_kw)) do
      {_prefix, []} ->
        tokens

      {prefix, [{:exposing_kw, line} = exposing_tok | rest]} ->
        case Enum.split_while(rest, &(token_kind(&1) != :lparen)) do
          {_between, []} ->
            tokens

          {between, [{:lparen, open_line} | after_open]} ->
            case take_balanced_tokens_with_rest(after_open, 1, []) do
              {:ok, inner, rest_after_close} ->
                prefix ++
                  [exposing_tok] ++
                  between ++
                  [{:lparen, open_line}] ++
                  normalize_metadata_exposing_items(inner, line) ++
                  [{:rparen, open_line}] ++
                  rest_after_close

              :error ->
                tokens
            end
        end
    end
  end

  @spec normalize_metadata_exposing_items(tokens(), non_neg_integer()) :: tokens()
  defp normalize_metadata_exposing_items(tokens, line) do
    tokens
    |> split_top_level_comma_tokens(0, [])
    |> Enum.map(&normalize_metadata_exposing_item(&1, line))
    |> Enum.reject(&(&1 == []))
    |> join_with_comma(line)
  end

  @spec normalize_metadata_exposing_item(tokens(), non_neg_integer()) :: tokens()
  defp normalize_metadata_exposing_item(tokens, line) do
    tokens = trim_metadata_item_tokens(tokens)

    cond do
      tokens == [] ->
        []

      metadata_operator_expose?(tokens) ->
        [{:lower_id, line, "__operator__"}]

      metadata_constructor_expose?(tokens) ->
        [{:upper_id, _, name} | _] = tokens
        [{:upper_id, line, name}, {:lparen, line}, {:dotdot, line}, {:rparen, line}]

      true ->
        tokens
    end
  end

  @spec metadata_operator_expose?(tokens()) :: boolean()
  defp metadata_operator_expose?(tokens) do
    tokens
    |> Enum.reject(&(token_kind(&1) == :newline))
    |> case do
      [{:lparen, _}, {:rparen, _}] -> true
      _ -> false
    end
  end

  @spec metadata_constructor_expose?(tokens()) :: boolean()
  defp metadata_constructor_expose?([{:upper_id, _, _}, {:lparen, _} | _]), do: true
  defp metadata_constructor_expose?(_tokens), do: false

  @spec trim_metadata_item_tokens(tokens()) :: tokens()
  defp trim_metadata_item_tokens(tokens) do
    tokens
    |> Enum.drop_while(&(token_kind(&1) == :newline))
    |> Enum.reverse()
    |> Enum.drop_while(&(token_kind(&1) == :newline))
    |> Enum.reverse()
  end

  @spec join_with_comma([tokens()], non_neg_integer()) :: tokens()
  defp join_with_comma(parts, line) do
    parts
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {part, 0} -> part
      {part, _idx} -> [{:comma, line} | part]
    end)
  end

  @spec parse_exposing_from_lines(term(), term()) :: term()
  defp parse_exposing_from_lines(lines, start_idx) when is_list(lines) do
    line = Enum.at(lines, start_idx, [])
    rest_lines = lines |> Enum.drop(start_idx + 1) |> Enum.take(120)

    case find_exposing_open(line) do
      nil ->
        nil

      after_open ->
        parse_exposing_from_open(after_open, rest_lines, 0)
    end
  end

  @spec parse_exposing_from_open(term(), term(), term()) :: term()
  defp parse_exposing_from_open(tokens_after_open, rest_lines, used_lines) do
    case take_balanced_tokens(tokens_after_open, 1, []) do
      {:ok, inner} ->
        parse_exposing_tokens(inner)

      :error ->
        case rest_lines do
          [next | rest] when used_lines < 120 ->
            parse_exposing_from_open(tokens_after_open ++ next, rest, used_lines + 1)

          _ ->
            nil
        end
    end
  end

  @spec find_exposing_open(tokens()) :: tokens() | nil
  defp find_exposing_open(tokens) do
    tokens
    |> Enum.drop_while(fn
      {:exposing_kw, _} -> false
      _ -> true
    end)
    |> case do
      [{:exposing_kw, _} | rest] ->
        case Enum.drop_while(rest, &(token_kind(&1) != :lparen)) do
          [{:lparen, _} | after_open] -> after_open
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec take_balanced_tokens(tokens(), non_neg_integer(), tokens()) :: {:ok, tokens()} | :error
  defp take_balanced_tokens([], _depth, _acc), do: :error

  defp take_balanced_tokens([tok | rest], depth, acc) do
    case token_kind(tok) do
      :lparen ->
        take_balanced_tokens(rest, depth + 1, [tok | acc])

      :rparen when depth == 1 ->
        {:ok, Enum.reverse(acc)}

      :rparen ->
        take_balanced_tokens(rest, depth - 1, [tok | acc])

      _ ->
        take_balanced_tokens(rest, depth, [tok | acc])
    end
  end

  @spec take_balanced_tokens_with_rest(tokens(), non_neg_integer(), tokens()) ::
          {:ok, tokens(), tokens()} | :error
  defp take_balanced_tokens_with_rest([], _depth, _acc), do: :error

  defp take_balanced_tokens_with_rest([tok | rest], depth, acc) do
    case token_kind(tok) do
      :lparen ->
        take_balanced_tokens_with_rest(rest, depth + 1, [tok | acc])

      :rparen when depth == 1 ->
        {:ok, Enum.reverse(acc), rest}

      :rparen ->
        take_balanced_tokens_with_rest(rest, depth - 1, [tok | acc])

      _ ->
        take_balanced_tokens_with_rest(rest, depth, [tok | acc])
    end
  end

  @spec parse_exposing_tokens(term()) :: term()
  defp parse_exposing_tokens([{:dotdot, _}]), do: ".."

  defp parse_exposing_tokens(tokens) when is_list(tokens) do
    tokens
    |> split_top_level_comma_tokens(0, [])
    |> Enum.map(&tokens_to_text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      xs -> xs
    end
  end

  @spec split_top_level_comma_tokens(tokens(), non_neg_integer(), [[token()]]) :: [[token()]]
  defp split_top_level_comma_tokens(tokens, depth, _acc) do
    {parts, current, _depth} =
      Enum.reduce(tokens, {[], [], depth}, fn tok, {parts, current, d} ->
        case token_kind(tok) do
          :lparen ->
            {parts, [tok | current], d + 1}

          :rparen ->
            {parts, [tok | current], max(d - 1, 0)}

          :comma when d == 0 ->
            {[Enum.reverse(current) | parts], [], d}

          _ ->
            {parts, [tok | current], d}
        end
      end)

    Enum.reverse(parts) ++ [Enum.reverse(current)]
  end

  @spec tokens_to_text(tokens()) :: String.t()
  defp tokens_to_text(tokens) do
    tokens
    |> Enum.map(fn
      {:upper_id, _, value} -> value
      {:lower_id, _, value} -> value
      {:dotdot, _} -> ".."
      {:comma, _} -> ","
      {:lparen, _} -> "("
      {:rparen, _} -> ")"
      _ -> ""
    end)
    |> Enum.join()
  end

  @spec token_kind(token()) :: atom()
  defp token_kind({kind, _line}) when is_atom(kind), do: kind
  defp token_kind({kind, _line, _value}) when is_atom(kind), do: kind
end
