defmodule Ide.Formatter.Semantics.HeaderMetadata do
  @moduledoc false

  @type metadata :: %{
          module: String.t() | nil,
          imports: [String.t()],
          module_exposing: nil | String.t() | [String.t()],
          import_entries: [map()],
          port_module: boolean(),
          ports: [String.t()],
          header_lines: %{module: integer() | nil, imports: [integer()]}
        }

  @spec from_values_and_tokens(String.t(), [tuple()], [tuple()]) :: metadata()
  def from_values_and_tokens(source, values, tokens)
      when is_binary(source) and is_list(values) and is_list(tokens) do
    lines = split_token_lines(tokens)
    first_idx = Enum.find_index(lines, &(&1 != []))
    first_line = if is_integer(first_idx), do: Enum.at(lines, first_idx), else: nil

    module_name =
      Enum.find_value(values, fn
        {:module, value, _exposing} when is_binary(value) and value != "" -> value
        {:module, value} when is_binary(value) and value != "" -> value
        _ -> nil
      end)

    imports =
      values
      |> Enum.filter(fn
        {:import, value, _tail} when is_binary(value) and value != "" -> true
        {:import, value} when is_binary(value) and value != "" -> true
        _ -> false
      end)
      |> Enum.map(fn
        {:import, value, _tail} -> value
        {:import, value} -> value
      end)
      |> Enum.uniq()

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
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_no} ->
        match?([{:import_kw, _}, {:upper_id, _, _} | _], line)
      end)
      |> Enum.map(fn {line, line_no} -> parse_import_entry(line, lines, line_no - 1, line_no) end)
      |> Enum.reject(&is_nil/1)

    ports =
      lines
      |> Enum.filter(&match?([{:port_kw, _}, {:lower_id, _, _} | _], &1))
      |> Enum.map(fn [{:port_kw, _}, {:lower_id, _, name} | _] -> name end)
      |> Enum.uniq()

    header_lines = locate_header_lines(source, module_name, length(import_entries))

    import_entries =
      import_entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        Map.put(entry, "line", Enum.at(header_lines.imports, idx))
      end)

    %{
      module: module_name,
      imports: imports,
      module_exposing: module_exposing,
      import_entries: import_entries,
      port_module: port_module,
      ports: ports,
      header_lines: header_lines
    }
  end

  @spec locate_header_lines(term(), term(), term()) :: term()
  defp locate_header_lines(source, module_name, import_count) do
    lines = String.split(source, "\n", trim: false)

    module_line =
      if is_binary(module_name) and module_name != "" do
        Enum.find_value(Enum.with_index(lines, 1), fn {line, idx} ->
          trimmed = String.trim_leading(line)

          if (String.starts_with?(trimmed, "module ") or
                String.starts_with?(trimmed, "effect module ") or
                String.starts_with?(trimmed, "port module ")) and
               String.contains?(trimmed, module_name) do
            idx
          end
        end)
      end

    import_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _idx} ->
        trimmed = String.trim_leading(line)
        String.starts_with?(trimmed, "import ")
      end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.take(import_count)

    %{module: module_line, imports: import_lines}
  end

  @spec split_token_lines(term()) :: term()
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

  @spec parse_import_entry(term(), term(), term(), term()) :: term()
  defp parse_import_entry(
         [{:import_kw, _}, {:upper_id, _, module_name} | line],
         lines,
         idx,
         _line_no
       ) do
    as_name =
      case line do
        [{:as_kw, _}, {:upper_id, _, alias_name} | _] -> alias_name
        _ -> nil
      end

    exposing = parse_exposing_from_lines(lines, idx)

    %{
      "module" => module_name,
      "as" => as_name,
      "exposing" => exposing,
      "line" => nil
    }
  end

  defp parse_import_entry(_, _, _, _), do: nil

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

  @spec find_exposing_open(term()) :: term()
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

  @spec take_balanced_tokens(term(), term(), term()) :: term()
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

  @spec parse_exposing_tokens(term()) :: term()
  defp parse_exposing_tokens([{:dotdot, _}]), do: ".."

  defp parse_exposing_tokens(tokens) when is_list(tokens) do
    tokens
    |> split_top_level_comma_tokens(0)
    |> Enum.map(&tokens_to_text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      xs -> xs
    end
  end

  @spec split_top_level_comma_tokens(term(), term()) :: term()
  defp split_top_level_comma_tokens(tokens, depth) do
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

  @spec tokens_to_text(term()) :: term()
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

  @spec token_kind(term()) :: term()
  defp token_kind({kind, _line}) when is_atom(kind), do: kind
  defp token_kind({kind, _line, _value}) when is_atom(kind), do: kind
end
