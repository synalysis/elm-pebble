defmodule ElmEx.Frontend.GeneratedContractBuilder do
  @moduledoc """
  Generated-parser-owned builder that emits the frontend module/declaration/
  expression contract consumed by lowering and codegen.
  """

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes
  alias ElmEx.Frontend.GeneratedDeclarationParser
  alias ElmEx.Frontend.GeneratedDeclarationParser, as: DeclParser
  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.Module
  alias ElmEx.Frontend.SourceRegions

  @typep union_constructor :: %{required(:name) => String.t(), required(:arg) => String.t() | nil}

  @typep union_builder :: %{
          required(:name) => String.t(),
          required(:constructors) => [union_constructor()],
          required(:start_line) => pos_integer(),
          required(:end_line) => pos_integer(),
          required(:source_lines) => [String.t()],
          optional(:type_params) => [String.t()]
        }

  @typep function_builder :: %{
          required(:name) => String.t(),
          required(:args) => [String.t()],
          required(:body_lines) => [String.t()],
          required(:start_line) => pos_integer(),
          required(:end_line) => pos_integer(),
          required(:in_multiline_string?) => boolean(),
          required(:in_glsl_literal?) => boolean(),
          required(:block_comment_depth) => non_neg_integer(),
          optional(:header_source) => String.t()
        }

  @typep expr :: AstTypes.expr() | nil
  @typep decl :: AstTypes.declaration()
  @typep scanned_line :: DeclParser.scanned_line()

  @spec build(String.t(), String.t(), String.t(), [String.t()]) :: Module.t()
  def build(path, source, module_name, imports) do
    regions = SourceRegions.extract(source)

    scanned_lines =
      source
      |> dedent_uniform_leading_whitespace()
      |> GeneratedDeclarationParser.scan_lines()
      |> hydrate_multiline_non_function_decls()
      |> hydrate_multiline_function_headers()

    %{type_aliases: type_aliases, unions: unions, signatures: signatures} =
      collect_non_function_declarations(scanned_lines)

    declarations =
      sort_declarations_by_source_order(
        type_aliases ++
          unions ++
          signatures ++
          parse_function_definitions(scanned_lines) ++
          collect_raw_top_level_declarations(scanned_lines, regions.body_line_start)
      )

    %Module{
      name: module_name,
      path: path,
      imports: imports,
      declarations: declarations
    }
  end

  @spec dedent_uniform_leading_whitespace(String.t()) :: String.t()
  defp dedent_uniform_leading_whitespace(source) when is_binary(source) do
    lines = String.split(source, "\n")

    min_indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&leading_whitespace_count/1)
      |> case do
        [] -> 0
        counts -> Enum.min(counts)
      end

    if min_indent > 0 do
      lines
      |> Enum.map(fn line ->
        if String.trim(line) == "" do
          line
        else
          String.slice(line, min_indent..-1//1)
        end
      end)
      |> Enum.join("\n")
    else
      source
    end
  end

  @spec leading_whitespace_count(String.t()) :: non_neg_integer()
  defp leading_whitespace_count(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 in [" ", "\t"]))
    |> length()
  end

  @spec hydrate_multiline_non_function_decls([scanned_line()]) :: [scanned_line()]
  defp hydrate_multiline_non_function_decls(scanned_lines) do
    do_hydrate_multiline_non_function_decls(scanned_lines, [])
  end

  @spec do_hydrate_multiline_non_function_decls([scanned_line()], [scanned_line()]) :: [scanned_line()]
  defp do_hydrate_multiline_non_function_decls([], acc), do: Enum.reverse(acc)

  defp do_hydrate_multiline_non_function_decls([line_info | rest], acc) do
    {continuation, tail_after_continuation} = Enum.split_while(rest, &multiline_continuation_line?/1)

    cond do
      multiline_signature_start?(line_info, continuation) ->
        hydrated = hydrate_multiline_signature_decl(line_info, continuation)
        consumed = mark_hydrated_union_consumed(continuation)

        do_hydrate_multiline_non_function_decls(
          tail_after_continuation,
          Enum.reverse([hydrated | consumed]) ++ acc
        )

      multiline_type_alias_start?(line_info, continuation) ->
        {type_alias_continuation, tail_after_type_alias} = take_type_alias_continuation_lines(rest)
        hydrated = hydrate_multiline_type_alias_decl(line_info, type_alias_continuation)
        consumed = mark_hydrated_union_consumed(type_alias_continuation)

        do_hydrate_multiline_non_function_decls(
          tail_after_type_alias,
          Enum.reverse([hydrated | consumed]) ++ acc
        )

      multiline_union_start?(line_info, continuation) ->
        {hydrated, consumed} = hydrate_multiline_union_decl(line_info, continuation)
        do_hydrate_multiline_non_function_decls(tail_after_continuation, Enum.reverse([hydrated | consumed]) ++ acc)

      true ->
        do_hydrate_multiline_non_function_decls(rest, [line_info | acc])
    end
  end

  @spec hydrate_multiline_function_headers([scanned_line()]) :: [scanned_line()]
  defp hydrate_multiline_function_headers(scanned_lines) do
    do_hydrate_multiline_function_headers(scanned_lines, [])
  end

  @spec do_hydrate_multiline_function_headers([scanned_line()], [scanned_line()]) :: [scanned_line()]
  defp do_hydrate_multiline_function_headers([], acc), do: Enum.reverse(acc)

  defp do_hydrate_multiline_function_headers([line_info | rest], acc) do
    if multiline_function_name_start?(line_info) do
      {hydrated, consumed, tail} = hydrate_multiline_function_header_decl(line_info, rest)

      do_hydrate_multiline_function_headers(
        tail,
        Enum.reverse([hydrated | consumed]) ++ acc
      )
    else
      do_hydrate_multiline_function_headers(rest, [line_info | acc])
    end
  end

  @spec multiline_function_name_start?(scanned_line()) :: boolean()
  defp multiline_function_name_start?(line_info) do
    line_info.function_header == :none and line_info.decl == :none and not line_info.indented? and
      not String.contains?(line_info.trimmed, "=") and
      not declaration_keyword_line?(line_info.trimmed) and
      (Regex.match?(~r/^[a-z][A-Za-z0-9_']*$/u, line_info.trimmed) or
         Regex.match?(~r/^[a-z][A-Za-z0-9_']*\s+[\(\{]/u, line_info.trimmed))
  end

  @spec declaration_keyword_line?(String.t()) :: boolean()
  defp declaration_keyword_line?(trimmed) when is_binary(trimmed) do
    trimmed in ["type", "alias", "port", "effect"] or
      String.starts_with?(trimmed, "type ") or
      String.starts_with?(trimmed, "infix ") or
      String.starts_with?(trimmed, "effect ")
  end

  @spec hydrate_multiline_function_header_decl(scanned_line(), [scanned_line()]) ::
          {scanned_line(), [scanned_line()], [scanned_line()]}
  defp hydrate_multiline_function_header_decl(line_info, continuation) do
    case Enum.find_index(continuation, &(&1.trimmed == "=")) do
      nil ->
        {line_info, [], continuation}

      idx ->
        {pattern_lines, [eq_line | tail]} = Enum.split(continuation, idx)

        raw_header =
          ([line_info | pattern_lines] ++ [eq_line])
          |> Enum.map(& &1.raw_line)
          |> Enum.join("\n")
          |> String.trim_trailing()

        hydrated = %{
          line_info
          | function_header:
              {:ok,
               %{
                 name: line_info.trimmed,
                 args: [],
                 body: "",
                 header_source: raw_header
               }}
        }

        consumed =
          Enum.map(pattern_lines ++ [eq_line], fn consumed_line ->
            %{consumed_line | function_header: :none, decl: :none, trimmed: "", raw_line: ""}
          end)

        {hydrated, consumed, tail}
    end
  end

  @spec multiline_signature_start?(scanned_line(), [scanned_line()]) :: boolean()
  defp multiline_signature_start?(line_info, continuation) do
    line_info.decl == :none and not line_info.indented? and
      (Regex.match?(~r/^[a-z][A-Za-z0-9_']*\s*:\s*$/u, line_info.trimmed) or
         multiline_signature_name_start?(line_info, continuation))
  end

  @spec multiline_signature_name_start?(scanned_line(), [scanned_line()]) :: boolean()
  defp multiline_signature_name_start?(line_info, continuation) do
    Regex.match?(~r/^[a-z][A-Za-z0-9_']*$/u, line_info.trimmed) and
      Enum.any?(continuation, &signature_colon_line?/1)
  end

  @spec signature_colon_line?(scanned_line()) :: boolean()
  defp signature_colon_line?(line_info) do
    trimmed = String.trim(line_info.trimmed)
    trimmed == ":" or String.ends_with?(trimmed, ":")
  end

  @spec multiline_type_alias_start?(scanned_line(), [scanned_line()]) :: boolean()
  defp multiline_type_alias_start?(line_info, continuation) do
    line_info.decl == :none and not line_info.indented? and
      (type_alias_header_line?(line_info.trimmed) or
         (line_info.trimmed == "type" and type_alias_multiline_follows?(continuation)))
  end

  @spec type_alias_header_line?(String.t()) :: boolean()
  defp type_alias_header_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^type\s+alias\b/u, trimmed)
  end

  @spec type_alias_multiline_follows?([scanned_line()]) :: boolean()
  defp type_alias_multiline_follows?([%{trimmed: trimmed} | rest]) when is_binary(trimmed) do
    trimmed == "alias" or String.starts_with?(trimmed, "alias ") or
      type_alias_multiline_follows?(rest)
  end

  defp type_alias_multiline_follows?(_), do: false

  @spec multiline_union_start?(scanned_line(), [scanned_line()]) :: boolean()
  defp multiline_union_start?(line_info, continuation) do
    match?({:ok, {:union_start, _, :none}}, line_info.decl) or
      (line_info.decl == :none and not line_info.indented? and
         (Regex.match?(~r/^type\s+[A-Z][A-Za-z0-9_']*(?:\s+[a-z][A-Za-z0-9_']*)*\s*=\s*$/u, line_info.trimmed) or
            (line_info.trimmed == "type" and not type_alias_multiline_follows?(continuation))))
  end

  @spec multiline_continuation_line?(scanned_line()) :: boolean()
  defp multiline_continuation_line?(line_info) do
    line_info.indented? or union_trivia_line?(line_info)
  end

  @spec take_type_alias_continuation_lines([scanned_line()]) :: {[scanned_line()], [scanned_line()]}
  defp take_type_alias_continuation_lines([]), do: {[], []}

  defp take_type_alias_continuation_lines([line | rest]) do
    next_line = List.first(rest)

    if type_alias_continuation_line?(line, next_line) do
      {more, tail} = take_type_alias_continuation_lines(rest)
      {[line | more], tail}
    else
      {[], [line | rest]}
    end
  end

  @spec type_alias_continuation_line?(scanned_line(), scanned_line() | nil) :: boolean()
  defp type_alias_continuation_line?(line_info, next_line) do
    line_info.indented? or type_alias_trivia_line?(line_info) or
      (line_info.trimmed == "" and not line_info.indented? and
         match?(%{indented?: true}, next_line))
  end

  @spec type_alias_trivia_line?(scanned_line()) :: boolean()
  defp type_alias_trivia_line?(line_info) do
    line_info.indented? and String.starts_with?(line_info.trimmed, "--")
  end

  @spec continues_function_body?(scanned_line(), scanned_line() | nil, boolean()) :: boolean()
  defp continues_function_body?(line_info, next_line, in_glsl_literal?) do
    cond do
      in_glsl_literal? ->
        true

      line_info.indented? ->
        true

      line_info.trimmed == "" and not line_info.indented? ->
        next_line != nil and next_line.indented?

      comment_line_inside_function_body?(line_info, next_line) ->
        true

      true ->
        false
    end
  end

  @spec comment_line_inside_function_body?(scanned_line(), scanned_line() | nil) :: boolean()
  defp comment_line_inside_function_body?(line_info, next_line) do
    not line_info.indented? and String.starts_with?(line_info.trimmed, "--") and
      next_line != nil and next_line.indented?
  end

  @spec hydrate_multiline_signature_decl(scanned_line(), [scanned_line()]) :: scanned_line()
  defp hydrate_multiline_signature_decl(line_info, continuation) do
    raw_source =
      ([line_info | continuation] |> Enum.map(& &1.raw_line) |> Enum.join("\n"))
      |> String.trim_trailing()

    name = line_info.trimmed |> String.trim_trailing(":") |> String.trim()

    type_tail =
      continuation
      |> Enum.filter(&(not (&1.trimmed == "" or String.starts_with?(&1.trimmed, "--"))))
      |> Enum.map(& &1.trimmed)
      |> Enum.join(" ")

    case GeneratedDeclarationParser.parse_line("#{name} : #{type_tail}") do
      {:ok, {:function_signature, _, _type} = sig} ->
        line_info
        |> Map.put(:decl, {:ok, sig})
        |> Map.put(:signature_source, raw_source)
        |> Map.put(:signature_end_line, line_info.line_no + length(continuation))

      {:ok, other} ->
        line_info
        |> Map.put(:decl, {:ok, other})
        |> Map.put(:signature_source, raw_source)
        |> Map.put(:signature_end_line, line_info.line_no + length(continuation))

      _ ->
        line_info
        |> Map.put(:decl, {:ok, {:function_signature, name, type_tail}})
        |> Map.put(:signature_source, raw_source)
        |> Map.put(:signature_end_line, line_info.line_no + length(continuation))
    end
  end

  @spec hydrate_multiline_type_alias_decl(scanned_line(), [scanned_line()]) :: scanned_line()
  defp hydrate_multiline_type_alias_decl(line_info, continuation) do
    raw_source =
      ([line_info | continuation] |> Enum.map(& &1.raw_line) |> Enum.join("\n"))
      |> String.trim_trailing()

    alias_tail =
      continuation
      |> Enum.filter(&(not (&1.trimmed == "" or String.starts_with?(&1.trimmed, "--"))))
      |> Enum.map(& &1.trimmed)
      |> Enum.join(" ")

    candidate =
      [line_info.trimmed, alias_tail]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    case GeneratedDeclarationParser.parse_line(candidate) do
      {:ok, {:type_alias, _} = alias_decl} ->
        line_info
        |> Map.put(:type_alias_source, raw_source)
        |> Map.put(:type_alias_end_line, line_info.line_no + length(continuation))
        |> Map.put(:decl, {:ok, alias_decl})

      _ ->
        with {:ok, name} <- type_alias_name_from_source(raw_source) do
          line_info
          |> Map.put(:type_alias_source, raw_source)
          |> Map.put(:type_alias_end_line, line_info.line_no + length(continuation))
          |> Map.put(:decl, {:ok, {:type_alias, name}})
        else
          _ -> line_info
        end
    end
  end

  @spec type_alias_name_from_source(String.t()) :: {:ok, String.t()} | :error
  defp type_alias_name_from_source(source) when is_binary(source) do
    case Regex.run(~r/^type\s+alias\s+([A-Z][A-Za-z0-9_']*)\s*=/u, String.trim(source)) do
      [_, name] ->
        {:ok, name}

      _ ->
        case multiline_type_alias_name_from_source(source) do
          nil ->
            case inline_type_alias_name_from_source(source) do
              nil ->
                case trick_type_alias_name_from_source(source) do
                  nil -> :error
                  name -> {:ok, name}
                end

              name ->
                {:ok, name}
            end

          name ->
            {:ok, name}
        end
    end
  end

  @spec inline_type_alias_name_from_source(String.t()) :: String.t() | nil
  defp inline_type_alias_name_from_source(source) when is_binary(source) do
    text =
      source
      |> String.split("\n", trim: false)
      |> Enum.map(&GeneratedDeclarationParser.strip_declaration_comments/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    case Regex.run(~r/type\s+alias\s+([A-Z][A-Za-z0-9_']*)/u, text) do
      [_, name] -> name
      _ -> nil
    end
  end

  @spec multiline_type_alias_name_from_source(String.t()) :: String.t() | nil
  defp multiline_type_alias_name_from_source(source) when is_binary(source) do
    lines =
      source
      |> String.split("\n", trim: false)
      |> Enum.map(&String.trim/1)

    unless Enum.any?(lines, &type_alias_header_line?/1) do
      nil
    else
      lines
      |> Enum.drop_while(&(not type_alias_header_line?(&1)))
      |> Enum.drop(1)
      |> Enum.take_while(&(&1 != "="))
      |> Enum.reject(&( &1 == "" or String.starts_with?(&1, "--")))
      |> Enum.find_value(fn line ->
        case Regex.run(~r/^([A-Z][A-Za-z0-9_']*)/u, line) do
          [_, name] -> name
          _ -> nil
        end
      end)
    end
  end

  @spec trick_type_alias_name_from_source(String.t()) :: String.t() | nil
  defp trick_type_alias_name_from_source(source) when is_binary(source) do
    lines =
      source
      |> String.split("\n", trim: false)
      |> Enum.map(&String.trim/1)

    alias_idx =
      Enum.find_index(lines, fn line ->
        line == "alias" or String.starts_with?(line, "alias ")
      end)

    if alias_idx do
      lines
      |> Enum.drop(alias_idx + 1)
      |> Enum.reject(&( &1 == "" or String.starts_with?(&1, "--") or &1 == "="))
      |> Enum.find_value(fn line ->
        case Regex.run(~r/^([A-Z][A-Za-z0-9_']*)/u, line) do
          [_, name] -> name
          _ -> nil
        end
      end)
    else
      nil
    end
  end

  @spec hydrate_multiline_union_decl(scanned_line(), [scanned_line()]) :: {scanned_line(), [scanned_line()]}
  defp hydrate_multiline_union_decl(line_info, continuation) do
    raw_source =
      ([line_info | continuation] |> Enum.map(& &1.raw_line) |> Enum.join("\n"))
      |> String.trim_trailing()

    union_tail =
      continuation
      |> Enum.filter(&(not (&1.trimmed == "" or String.starts_with?(&1.trimmed, "--"))))
      |> Enum.map(& &1.trimmed)
      |> Enum.map(&strip_union_line_comment/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    candidate =
      [line_info.trimmed, union_tail]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    case GeneratedDeclarationParser.parse_line(candidate) do
      {:ok, {:union_start_many, _, _} = union_decl} ->
        {line_info
         |> Map.put(:decl, {:ok, union_decl})
         |> Map.put(:union_source, raw_source)
         |> Map.put(:union_end_line, line_info.line_no + length(continuation)),
         mark_hydrated_union_consumed(continuation)}

      _ ->
        if multiline_type_declaration_source?(line_info, raw_source) do
          name = union_name_from_multiline_source(raw_source)

          {line_info
           |> Map.put(:decl, {:ok, {:union_start, name, :none}})
           |> Map.put(:union_source, raw_source)
           |> Map.put(:union_end_line, line_info.line_no + length(continuation)),
           mark_hydrated_union_consumed(continuation)}
        else
          {line_info, continuation}
        end
    end
  end

  @spec multiline_type_declaration_source?(scanned_line(), String.t()) :: boolean()
  defp multiline_type_declaration_source?(line_info, raw_source) do
    line_info.trimmed == "type" or
      (String.starts_with?(line_info.trimmed, "type ") and String.contains?(raw_source, "="))
  end

  @spec union_name_from_multiline_source(String.t()) :: String.t()
  defp union_name_from_multiline_source(source) when is_binary(source) do
    lines =
      source
      |> String.split("\n", trim: false)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case Enum.find_value(lines, &union_type_name_from_line/1) do
      nil -> union_type_name_before_equals(lines) || "UnknownType"
      name -> name
    end
  end

  @spec union_type_name_from_line(String.t()) :: String.t() | nil
  defp union_type_name_from_line("type " <> rest) do
    case Regex.run(~r/^([A-Z][A-Za-z0-9_']*)/u, String.trim(rest)) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp union_type_name_from_line(_), do: nil

  @spec union_type_name_before_equals([String.t()]) :: String.t() | nil
  defp union_type_name_before_equals(lines) do
    lines
    |> Enum.take_while(&( &1 != "=" and not String.starts_with?(&1, "=")))
    |> Enum.find_value(fn line ->
      if String.starts_with?(line, "--") do
        nil
      else
        case Regex.run(~r/^([A-Z][A-Za-z0-9_']*)$/u, line) do
          [_, name] -> name
          _ -> nil
        end
      end
    end)
  end

  @spec mark_hydrated_union_consumed([scanned_line()]) :: [scanned_line()]
  defp mark_hydrated_union_consumed(continuation) do
    Enum.map(continuation, fn line_info ->
      %{line_info | decl: :none, trimmed: "", raw_line: ""}
    end)
  end

  @spec collect_non_function_declarations([scanned_line()]) :: %{
          type_aliases: [decl()],
          unions: [decl()],
          signatures: [decl()]
        }
  defp collect_non_function_declarations(scanned_lines) do
    {type_aliases, unions, signatures, current_union} =
      Enum.reduce(scanned_lines, {[], [], [], nil}, fn line_info,
                                                       {aliases_acc, unions_acc, sigs_acc,
                                                        union_current} ->
        case line_info.decl do
          {:ok, {:type_alias, name}} ->
            record_info =
              type_alias_record_info(
                Map.get(line_info, :type_alias_source) || line_info.trimmed
              )

            {
              [
                %{
                  kind: :type_alias,
                  name: name,
                  fields: Enum.map(record_info.fields, & &1.name),
                  field_types: Map.new(record_info.fields, &{&1.name, &1.type}),
                  extensible_base: record_info.extensible_base,
                  alias_type: Map.get(record_info, :alias_type),
                  source: Map.get(line_info, :type_alias_source),
                  span: %{
                    start_line: line_info.line_no,
                    end_line: Map.get(line_info, :type_alias_end_line, line_info.line_no)
                  }
                }
                | aliases_acc
              ],
              flush_union(unions_acc, union_current),
              sigs_acc,
              nil
            }

          {:ok, {:function_signature, name, type}} ->
            signature_source =
              Map.get(line_info, :signature_source) ||
                (line_info.raw_line |> String.trim_trailing())

            end_line = Map.get(line_info, :signature_end_line, line_info.line_no)

            {aliases_acc, flush_union(unions_acc, union_current),
             [
               %{
                 kind: :function_signature,
                 name: name,
                 type: String.trim(type),
                 source: signature_source,
                 span: %{start_line: line_info.line_no, end_line: end_line}
               }
               | sigs_acc
             ], nil}

          {:ok, {:port_signature, name, type}} ->
            {aliases_acc, flush_union(unions_acc, union_current),
             [
               %{
                 kind: :function_signature,
                 name: name,
                 type: String.trim(type),
                 source: line_info.raw_line |> String.trim_trailing(),
                 span: %{start_line: line_info.line_no, end_line: line_info.line_no}
               }
               | sigs_acc
             ], nil}

          _ ->
            {next_unions, next_current} = parse_union_line(line_info, unions_acc, union_current)
            {aliases_acc, next_unions, sigs_acc, next_current}
        end
      end)

    %{
      type_aliases: Enum.reverse(type_aliases),
      unions: Enum.reverse(flush_union(unions, current_union)),
      signatures: Enum.reverse(signatures)
    }
  end

  @typep type_alias_record_info :: %{
          required(:fields) => [%{name: String.t(), type: String.t()}],
          required(:extensible_base) => String.t() | nil,
          optional(:alias_type) => String.t() | nil
        }

  @spec type_alias_record_info(String.t()) :: type_alias_record_info()
  defp type_alias_record_info(source) when is_binary(source) do
    with {:ok, rhs} <- split_type_alias_rhs(source),
         {:ok, inner} <- record_type_body(rhs) do
      {extensible_base, fields_source} =
        case split_top_level(inner, "|", []) do
          [base, fields] -> {String.trim(base), String.trim(fields)}
          _ -> {nil, inner}
        end

      field_specs =
        fields_source
        |> split_top_level(",", [])
        |> Enum.flat_map(&record_field_spec/1)

      %{fields: field_specs, extensible_base: extensible_base, alias_type: nil}
    else
      _ ->
        case split_type_alias_rhs(source) do
          {:ok, rhs} -> %{fields: [], extensible_base: nil, alias_type: String.trim(rhs)}
          :error -> %{fields: [], extensible_base: nil, alias_type: nil}
        end
    end
  end

  defp type_alias_record_info(_source), do: %{fields: [], extensible_base: nil, alias_type: nil}

  @spec split_type_alias_rhs(String.t()) :: {:ok, String.t()} | :error
  defp split_type_alias_rhs(source) do
    case split_top_level(source, "=", []) do
      [_left, right] -> {:ok, String.trim(right)}
      _ -> :error
    end
  end

  @spec record_type_body(String.t()) :: {:ok, String.t()} | :error
  defp record_type_body(source) do
    trimmed = String.trim(source)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      {:ok, trimmed |> String.slice(1, String.length(trimmed) - 2) |> String.trim()}
    else
      :error
    end
  end

  @spec record_field_spec(String.t()) :: [%{name: String.t(), type: String.t()}]
  defp record_field_spec(source) do
    case split_top_level(source, ":", []) do
      [name, type] ->
        name = String.trim(name)
        type = String.trim(type)

        if valid_record_field_name?(name) and type != "" do
          [%{name: name, type: type}]
        else
          []
        end

      _ ->
        []
    end
  end

  @spec valid_record_field_name?(String.t()) :: boolean()
  defp valid_record_field_name?(<<first::utf8, rest::binary>>) when first in ?a..?z do
    String.printable?(rest)
  end

  defp valid_record_field_name?(_), do: false

  @spec split_top_level(String.t(), String.t(), [String.t()]) :: [String.t()]
  defp split_top_level(source, separator, acc)
       when is_binary(source) and is_binary(separator) and byte_size(separator) == 1 do
    do_split_top_level(source, separator, acc, "", 0, nil)
  end

  defp do_split_top_level(<<>>, _separator, acc, current, _depth, _quote) do
    Enum.reverse([String.trim(current) | acc])
  end

  defp do_split_top_level(<<char::utf8, rest::binary>>, separator, acc, current, depth, quote) do
    char_text = <<char::utf8>>

    cond do
      quote == nil and char_text == separator and depth == 0 ->
        do_split_top_level(rest, separator, [String.trim(current) | acc], "", depth, quote)

      quote == nil and char_text in ["\"", "'"] ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, char_text)

      quote == char_text ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, nil)

      quote == nil and char_text in ["(", "[", "{"] ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth + 1, quote)

      quote == nil and char_text in [")", "]", "}"] ->
        do_split_top_level(rest, separator, acc, current <> char_text, max(depth - 1, 0), quote)

      true ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, quote)
    end
  end

  @spec parse_function_definitions([scanned_line()]) :: [decl()]
  defp parse_function_definitions(scanned_lines) do
    scanned_lines
    |> Enum.with_index()
    |> Enum.reduce({[], nil}, fn {line_info, idx}, {acc, current} ->
      next_line = Enum.at(scanned_lines, idx + 1)
      parsed_header = line_info.function_header
      is_signature = match?({:ok, {:function_signature, _, _}}, line_info.decl)

      cond do
        current != nil and
            (current.block_comment_depth > 0 or current.in_multiline_string? or
               continues_function_body?(line_info, next_line, current.in_glsl_literal?)) ->
          next_in_multiline_string =
            update_multiline_string_state(current.in_multiline_string?, line_info.raw_line)

          next_in_glsl_literal =
            update_glsl_literal_state(current.in_glsl_literal?, line_info.raw_line)

          next_block_comment_depth =
            advance_block_comment_depth(current.block_comment_depth, line_info.raw_line)

          {acc,
           %{
             current
             | body_lines: current.body_lines ++ [line_info.raw_line],
               end_line: line_info.line_no,
               in_multiline_string?: next_in_multiline_string,
               in_glsl_literal?: next_in_glsl_literal,
               block_comment_depth: next_block_comment_depth
           }}

        current != nil and raw_top_level_declaration_line?(line_info) ->
          flushed = maybe_flush_function(acc, current)
          {flushed, nil}

        match?({:ok, _}, parsed_header) and not is_signature ->
          {:ok, %{name: name, args: args, body: first_body} = parsed} = parsed_header

          flushed = maybe_flush_function(acc, current)

          {flushed,
           %{
             name: name,
             args: args,
             header_source: Map.get(parsed, :header_source),
             body_lines: if(first_body == "", do: [], else: [first_body]),
             in_multiline_string?: update_multiline_string_state(false, first_body),
             in_glsl_literal?: update_glsl_literal_state(false, first_body),
             block_comment_depth: advance_block_comment_depth(0, first_body),
             start_line: line_info.line_no,
             end_line: line_info.line_no
           }}

        true ->
          flushed = maybe_flush_function(acc, current)
          {flushed, nil}
      end
    end)
    |> then(fn {acc, current} ->
      final = maybe_flush_function(acc, current)
      Enum.reverse(final)
    end)
  end

  @spec maybe_flush_function([decl()], function_builder() | nil) :: [decl()]
  defp maybe_flush_function(acc, nil), do: acc

  defp maybe_flush_function(acc, current) do
    body =
      current.body_lines
      |> Enum.join("\n")
      |> String.trim_trailing()

    if String.trim(body) == "" do
      acc
    else
        [
          %{
            kind: :function_definition,
            name: current.name,
            args: current.args,
            body: body,
            header_source: Map.get(current, :header_source),
            expr: parse_expression(current.name, body),
            span: %{start_line: current.start_line, end_line: current.end_line}
          }
          | acc
        ]
    end
  end

  @spec update_multiline_string_state(boolean(), String.t()) :: boolean()
  defp update_multiline_string_state(current_state, line) when is_binary(line) do
    delimiters = Regex.scan(~r/\"\"\"/u, line) |> length()

    if rem(delimiters, 2) == 1 do
      not current_state
    else
      current_state
    end
  end

  @spec update_glsl_literal_state(boolean(), String.t()) :: boolean()
  defp update_glsl_literal_state(current_state, line) when is_binary(line) do
    cond do
      current_state ->
        not glsl_literal_close_line?(line)

      glsl_literal_open_line?(line) ->
        true

      true ->
        false
    end
  end

  @spec glsl_literal_open_line?(String.t()) :: boolean()
  defp glsl_literal_open_line?(line) do
    String.contains?(line, "[glsl|") and not glsl_literal_closed_on_line?(line)
  end

  @spec glsl_literal_close_line?(String.t()) :: boolean()
  defp glsl_literal_close_line?(line), do: String.contains?(line, "|]")

  @spec glsl_literal_closed_on_line?(String.t()) :: boolean()
  defp glsl_literal_closed_on_line?(line) do
    case :binary.split(line, "[glsl|", []) do
      [_single] -> String.contains?(line, "|]")
      [_prefix, rest] -> String.contains?(rest, "|]")
    end
  end

  @spec advance_block_comment_depth(non_neg_integer(), String.t()) :: non_neg_integer()
  defp advance_block_comment_depth(depth, line) when is_integer(depth) and is_binary(line) do
    do_advance_block_comment_depth(line, depth)
  end

  defp do_advance_block_comment_depth(<<>>, depth), do: depth

  defp do_advance_block_comment_depth(<<"{-", rest::binary>>, depth) do
    do_advance_block_comment_depth(rest, depth + 1)
  end

  defp do_advance_block_comment_depth(<<"-}", rest::binary>>, depth) when depth > 0 do
    do_advance_block_comment_depth(rest, depth - 1)
  end

  defp do_advance_block_comment_depth(<<_char::utf8, rest::binary>>, depth) do
    do_advance_block_comment_depth(rest, depth)
  end

  @spec parse_expression(String.t() | nil, String.t()) :: AstTypes.expr()
  defp parse_expression(_name, body) do
    body = String.trim(body)
    generated_expr = maybe_generated_expr(body)

    generated_expr || unsupported_expr(body)
  end

  defp unsupported_expr(body) when is_binary(body) do
    case GeneratedExpressionParser.parse(body) do
      {:error, reason} ->
        %{op: :unsupported, source: body, reason: inspect(reason)}

      _ ->
        %{op: :unsupported, source: body}
    end
  end

  @spec maybe_generated_expr(String.t()) :: expr()
  defp maybe_generated_expr("(&&)"), do: bool_intrinsic_lambda(:and)
  defp maybe_generated_expr("(||)"), do: bool_intrinsic_lambda(:or)

  defp maybe_generated_expr(body) do
    if body == "" do
      nil
    else
      case GeneratedExpressionParser.parse(body) do
        {:ok, expr} ->
          normalized = normalize_generated_expr(expr)

          if allow_generated_expr?(normalized) do
            normalized
          else
            nil
          end

        _ ->
          nil
      end
    end
  end

  @spec normalize_generated_expr(AstTypes.expr()) :: AstTypes.expr()
  defp normalize_generated_expr(%{op: :qualified_ref, target: target})
       when is_binary(target) do
    if Regex.match?(~r/^[a-z][A-Za-z0-9_]*(\.[a-z][A-Za-z0-9_]*)+$/, target) do
      nested_field_access_expr(String.split(target, "."))
    else
      %{op: :qualified_call, target: target, args: []}
    end
  end

  defp normalize_generated_expr(%{op: :qualified_ref, target: target}) do
    %{op: :qualified_call, target: target, args: []}
  end

  defp normalize_generated_expr(%{op: :constructor_ref, target: target}) do
    %{op: :constructor_call, target: target, args: []}
  end

  defp normalize_generated_expr(%{op: :qualified_call, target: "Tuple.second", args: [arg]}) do
    %{op: :tuple_second_expr, arg: normalize_generated_expr(arg)}
  end

  defp normalize_generated_expr(%{op: :qualified_call, target: "Tuple.first", args: [arg]}) do
    %{op: :tuple_first_expr, arg: normalize_generated_expr(arg)}
  end

  defp normalize_generated_expr(%{op: :qualified_call, target: "String.length", args: [arg]}) do
    %{op: :string_length_expr, arg: normalize_generated_expr(arg)}
  end

  defp normalize_generated_expr(%{op: :qualified_call, target: "Char.fromCode", args: [arg]}) do
    %{op: :char_from_code_expr, arg: normalize_generated_expr(arg)}
  end

  defp normalize_generated_expr(%{op: :qualified_call, target: "Cmd.none", args: []}) do
    %{op: :cmd_none}
  end

  defp normalize_generated_expr(%{op: :qualified_call, target: target, args: args}) do
    %{op: :qualified_call, target: target, args: Enum.map(args, &normalize_generated_expr/1)}
  end

  defp normalize_generated_expr(%{op: :pipe_chain, steps: steps, base: base}) do
    %{
      op: :pipe_chain,
      steps: Enum.map(steps, &normalize_generated_expr/1),
      base: normalize_generated_expr(base)
    }
  end

  defp normalize_generated_expr(%{op: :apply_left, fn_expr: fn_expr, arg: arg}) do
    %{
      op: :apply_left,
      fn_expr: normalize_generated_expr(fn_expr),
      arg: normalize_generated_expr(arg)
    }
  end

  defp normalize_generated_expr(%{op: :bool_and, left: left, right: right}) do
    %{
      op: :bool_and,
      left: normalize_generated_expr(left),
      right: normalize_generated_expr(right)
    }
  end

  defp normalize_generated_expr(%{op: :bool_or, left: left, right: right}) do
    %{
      op: :bool_or,
      left: normalize_generated_expr(left),
      right: normalize_generated_expr(right)
    }
  end

  defp normalize_generated_expr(%{op: :constructor_call, target: target, args: args}) do
    %{op: :constructor_call, target: target, args: Enum.map(args, &normalize_generated_expr/1)}
  end

  defp normalize_generated_expr(%{op: :call, name: name, args: args}) do
    %{op: :call, name: name, args: Enum.map(args, &normalize_generated_expr/1)}
  end

  defp normalize_generated_expr(%{op: :compare, kind: kind, left: left, right: right}) do
    %{
      op: :compare,
      kind: kind,
      left: normalize_generated_expr(left),
      right: normalize_generated_expr(right)
    }
  end

  defp normalize_generated_expr(%{op: :tuple2, left: left, right: right}) do
    %{op: :tuple2, left: normalize_generated_expr(left), right: normalize_generated_expr(right)}
  end

  defp normalize_generated_expr(%{op: :list_literal, items: items}) when is_list(items) do
    %{op: :list_literal, items: Enum.map(items, &normalize_generated_expr/1)}
  end

  defp normalize_generated_expr(%{op: :list_literal} = expr), do: expr

  defp normalize_generated_expr(%{op: :field_access, arg: arg, field: field}) do
    %{op: :field_access, arg: arg, field: field}
  end

  defp normalize_generated_expr(%{op: :field_call, arg: arg, field: field, args: args}) do
    %{op: :field_call, arg: arg, field: field, args: Enum.map(args, &normalize_generated_expr/1)}
  end

  defp normalize_generated_expr(%{op: :lambda, args: args, body: body}) do
    %{op: :lambda, args: args, body: normalize_generated_expr(body)}
  end

  defp normalize_generated_expr(%{
         op: :let_in,
         name: name,
         value_expr: value_expr,
         in_expr: in_expr
       }) do
    %{
      op: :let_in,
      name: name,
      value_expr: normalize_generated_expr(value_expr),
      in_expr: normalize_generated_expr(in_expr)
    }
  end

  defp normalize_generated_expr(%{
         op: :if,
         cond: cond_expr,
         then_expr: then_expr,
         else_expr: else_expr
       }) do
    %{
      op: :if,
      cond: normalize_generated_expr(cond_expr),
      then_expr: normalize_generated_expr(then_expr),
      else_expr: normalize_generated_expr(else_expr)
    }
  end

  defp normalize_generated_expr(%{op: :case, subject: subject, branches: branches}) do
    %{
      op: :case,
      subject: subject,
      branches:
        Enum.map(branches, fn
          %{pattern: pattern, expr: expr} ->
            %{pattern: pattern, expr: normalize_generated_expr(expr)}

          branch ->
            branch
        end)
    }
  end

  defp normalize_generated_expr(%{op: :record_literal, fields: fields}) do
    %{
      op: :record_literal,
      fields:
        Enum.map(fields, fn
          %{name: name, expr: expr} -> %{name: name, expr: normalize_generated_expr(expr)}
          field -> field
        end)
    }
  end

  defp normalize_generated_expr(%{op: :record_update, base: base, fields: fields}) do
    %{
      op: :record_update,
      base: normalize_generated_expr(base),
      fields:
        Enum.map(fields, fn
          %{name: name, expr: expr} -> %{name: name, expr: normalize_generated_expr(expr)}
          field -> field
        end)
    }
  end

  defp normalize_generated_expr(expr), do: expr

  @spec nested_field_access_expr([String.t()]) :: AstTypes.expr()
  defp nested_field_access_expr([base | fields]) do
    Enum.reduce(fields, %{op: :var, name: base}, fn field, arg ->
      %{op: :field_access, arg: arg, field: field}
    end)
  end

  @spec allow_generated_expr?(expr()) :: boolean()
  defp allow_generated_expr?(%{op: op})
       when op in [
              :int_literal,
              :float_literal,
              :bool_literal,
              :order_literal,
              :string_literal,
              :char_literal,
              :var,
              :add_const,
              :add_vars,
              :sub_const,
              :sub_vars,
              :cmd_none,
              :field_access,
              :qualified_ref,
              :constructor_ref,
              :tuple_second_expr,
              :tuple_first_expr,
              :string_length_expr,
              :char_from_code_expr
            ],
       do: true

  defp allow_generated_expr?(%{op: :qualified_call, args: args}) do
    Enum.all?(args, &allow_generated_expr?/1)
  end

  defp allow_generated_expr?(%{op: :pipe_chain, steps: steps, base: base}) do
    allow_generated_expr?(base) and Enum.all?(steps, &allow_generated_expr?/1)
  end

  defp allow_generated_expr?(%{op: :apply_left, fn_expr: fn_expr, arg: arg}) do
    allow_generated_expr?(fn_expr) and allow_generated_expr?(arg)
  end

  defp allow_generated_expr?(%{op: :bool_and, left: left, right: right}) do
    allow_generated_expr?(left) and allow_generated_expr?(right)
  end

  defp allow_generated_expr?(%{op: :bool_or, left: left, right: right}) do
    allow_generated_expr?(left) and allow_generated_expr?(right)
  end

  defp allow_generated_expr?(%{op: :constructor_call, args: args}) do
    Enum.all?(args, &allow_generated_expr?/1)
  end

  defp allow_generated_expr?(%{op: :call, args: args}) do
    Enum.all?(args, &allow_generated_expr?/1)
  end

  defp allow_generated_expr?(%{op: :compare, left: left, right: right}) do
    allow_generated_expr?(left) and allow_generated_expr?(right)
  end

  defp allow_generated_expr?(%{op: :list_literal, items: items}) do
    Enum.all?(items, &allow_generated_expr?/1)
  end

  defp allow_generated_expr?(%{op: :tuple2, left: left, right: right}) do
    allow_generated_expr?(left) and allow_generated_expr?(right)
  end

  defp allow_generated_expr?(%{op: :field_call, args: args}) do
    Enum.all?(args, &allow_generated_expr?/1)
  end

  defp allow_generated_expr?(%{op: :lambda, body: body}) do
    allow_generated_expr?(body)
  end

  defp allow_generated_expr?(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}) do
    allow_generated_expr?(value_expr) and allow_generated_expr?(in_expr)
  end

  defp allow_generated_expr?(%{op: :let_bindings, bindings: bindings, in_expr: in_expr}) do
    Enum.all?(bindings, fn
      %{value: value} -> allow_generated_expr?(value)
      _ -> false
    end) and allow_generated_expr?(in_expr)
  end

  defp allow_generated_expr?(%{
         op: :if,
         cond: cond_expr,
         then_expr: then_expr,
         else_expr: else_expr
       }) do
    allow_generated_expr?(cond_expr) and allow_generated_expr?(then_expr) and
      allow_generated_expr?(else_expr)
  end

  defp allow_generated_expr?(%{op: :case, branches: branches}) do
    Enum.all?(branches, fn
      %{expr: expr} -> allow_generated_expr?(expr)
      _ -> false
    end)
  end

  defp allow_generated_expr?(%{op: :record_literal, fields: fields}) do
    Enum.all?(fields, fn
      %{expr: expr} -> allow_generated_expr?(expr)
      _ -> false
    end)
  end

  defp allow_generated_expr?(%{op: :record_update, base: base, fields: fields}) do
    allow_generated_expr?(base) and
      Enum.all?(fields, fn
        %{expr: expr} -> allow_generated_expr?(expr)
        _ -> false
      end)
  end

  defp allow_generated_expr?(%{op: :compose_left, f: f, g: g}),
    do: allow_compose_side?(f) and allow_compose_side?(g)

  defp allow_generated_expr?(%{op: :compose_right, f: f, g: g}),
    do: allow_compose_side?(f) and allow_compose_side?(g)

  defp allow_generated_expr?(_), do: false

  defp allow_compose_side?(side) when is_binary(side), do: true
  defp allow_compose_side?(side), do: allow_generated_expr?(side)

  defp bool_intrinsic_lambda(:and) do
    %{
      op: :lambda,
      args: ["arg1", "arg2"],
      body: %{
        op: :if,
        cond: %{op: :var, name: "arg1"},
        then_expr: %{op: :var, name: "arg2"},
        else_expr: %{op: :constructor_call, target: "False", args: []}
      }
    }
  end

  defp bool_intrinsic_lambda(:or) do
    %{
      op: :lambda,
      args: ["arg1", "arg2"],
      body: %{
        op: :if,
        cond: %{op: :var, name: "arg1"},
        then_expr: %{op: :constructor_call, target: "True", args: []},
        else_expr: %{op: :var, name: "arg2"}
      }
    }
  end

  @spec parse_union_line(scanned_line(), [decl()], union_builder() | nil) ::
          {[decl()], union_builder() | nil}
  defp parse_union_line(line_info, acc, current) do
    line_no = line_info.line_no

    case line_info.decl do
      {:ok, {:union_start, union_name, :none}} ->
        {
          flush_union(acc, current),
          new_union_builder(line_info, union_name, [])
        }

      {:ok, {:union_start_many, union_name, constructors}} ->
        {flush_union(acc, current),
         new_union_builder(line_info, union_name, constructors)}

      {:ok, {:union_constructors, constructors}} when current != nil ->
        {acc,
         %{
           current
           | constructors: current.constructors ++ normalize_union_ctors(constructors),
             end_line: line_no,
             source_lines: current.source_lines ++ [line_info.raw_line]
         }}

      {:ok, {:union_constructors, _constructors}} ->
        {acc, current}

      _ when current != nil ->
        if union_trivia_line?(line_info) do
          {acc,
           %{
             current
             | end_line: line_no,
               source_lines: current.source_lines ++ [line_info.raw_line]
           }}
        else
          {flush_union(acc, current), nil}
        end

      _ ->
        {acc, current}
    end
  end

  @spec new_union_builder(scanned_line(), String.t(), list()) :: union_builder()
  defp new_union_builder(line_info, union_name, constructors) do
    source_lines = union_source_lines(line_info)

    %{
      name: union_name,
      constructors: normalize_union_ctors(constructors),
      start_line: line_info.line_no,
      end_line: Map.get(line_info, :union_end_line, line_info.line_no),
      source_lines: source_lines,
      type_params: union_type_params_from_source(Enum.join(source_lines, "\n"), union_name)
    }
  end

  @spec union_source_lines(scanned_line()) :: [String.t()]
  defp union_source_lines(line_info) do
    case Map.get(line_info, :union_source) do
      source when is_binary(source) -> String.split(source, "\n", trim: false)
      _ -> [line_info.raw_line]
    end
  end

  @spec union_type_params_from_source(String.t(), String.t()) :: [String.t()]
  defp union_type_params_from_source(source, union_name) when is_binary(source) do
    pattern =
      ~r/^type(?:\s+\{-[^}]*-\})*\s+#{Regex.escape(union_name)}(?:\s+\{-[^}]*-\})*\s+((?:[a-z][A-Za-z0-9_']*\s*)+)=/mu

    case Regex.run(pattern, source) do
      [_, params] ->
        params
        |> String.split(~r/\s+/u, trim: true)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  @spec normalize_union_ctors(list()) :: [union_constructor()]
  defp normalize_union_ctors(constructors) when is_list(constructors) do
    constructors
    |> Enum.reduce([], fn
      {:constructor, name, arg}, acc when is_binary(name) ->
        # Preserve the full parser payload type spec so later phases can
        # differentiate constructor shape without re-parsing source text.
        normalized_arg =
          case arg do
            value when is_binary(value) -> String.trim(value)
            _ -> arg
          end

        acc ++ [%{name: name, arg: normalized_arg}]

      _other, acc ->
        acc
    end)
  end

  @spec union_trivia_line?(scanned_line()) :: boolean()
  defp union_trivia_line?(line_info) do
    trimmed = line_info.trimmed
    raw_trimmed = String.trim(line_info.raw_line)

    cond do
      trimmed == "" and raw_trimmed == "" -> true
      String.starts_with?(trimmed, "--") -> true
      true -> false
    end
  end

  @spec strip_union_line_comment(String.t()) :: String.t()
  defp strip_union_line_comment(line) when is_binary(line) do
    line
    |> String.split(~r/\s+--\s/u, parts: 2)
    |> List.first()
    |> to_string()
    |> String.trim()
  end

  @spec flush_union([decl()], union_builder() | nil) :: [decl()]
  defp flush_union(acc, nil), do: acc

  defp flush_union(acc, current) do
    source =
      current.source_lines
      |> Enum.join("\n")
      |> String.trim_trailing()

    [
      %{
        kind: :union,
        name: current.name,
        constructors: current.constructors,
        type_params: Map.get(current, :type_params, []),
        source: source,
        span: %{
          start_line: current.start_line || 0,
          end_line: current.end_line || current.start_line || 0
        }
      }
      | acc
    ]
  end

  @spec sort_declarations_by_source_order([decl()]) :: [decl()]
  defp sort_declarations_by_source_order(declarations) do
    Enum.sort_by(declarations, fn decl ->
      case Map.get(decl, :span) do
        %{start_line: line} when is_integer(line) -> line
        _ -> 0
      end
    end)
  end

  @spec collect_raw_top_level_declarations([scanned_line()], pos_integer()) :: [decl()]
  defp collect_raw_top_level_declarations(scanned_lines, body_line_start) do
    scanned_lines
    |> Enum.drop_while(&(&1.line_no < body_line_start))
    |> collect_raw_declarations([])
    |> Enum.reverse()
  end

  @spec collect_raw_declarations([scanned_line()], [decl()]) :: [decl()]
  defp collect_raw_declarations([], acc), do: acc

  defp collect_raw_declarations([line | rest], acc) do
    raw_trimmed = String.trim(line.raw_line)

    cond do
      comment_trick_opener?(raw_trimmed) and not line.indented? ->
        {block_lines, remaining} = take_source_block_until_close(rest, [line], raw_trimmed)
        collect_raw_declarations(remaining, [build_raw_decl(block_lines) | acc])

      raw_top_level_declaration_line?(line) ->
        if comment_only_raw_line?(raw_trimmed) do
          {block_lines, remaining} = take_consecutive_comment_raw_lines([line | rest])
          collect_raw_declarations(remaining, [build_raw_decl(block_lines) | acc])
        else
          collect_raw_declarations(rest, [build_raw_decl([line]) | acc])
        end

      true ->
        collect_raw_declarations(rest, acc)
    end
  end

  @spec take_consecutive_comment_raw_lines([scanned_line()]) ::
          {[scanned_line()], [scanned_line()]}
  defp take_consecutive_comment_raw_lines([line | rest]) do
    do_take_consecutive_comment_raw_lines(rest, [line])
  end

  defp do_take_consecutive_comment_raw_lines([], acc), do: {Enum.reverse(acc), []}

  defp do_take_consecutive_comment_raw_lines([line | rest], acc) do
    raw_trimmed = String.trim(line.raw_line)

    if not line.indented? and comment_only_raw_line?(raw_trimmed) do
      do_take_consecutive_comment_raw_lines(rest, [line | acc])
    else
      {Enum.reverse(acc), [line | rest]}
    end
  end

  @spec build_raw_decl([scanned_line()]) :: decl()
  defp build_raw_decl(lines) do
    first = hd(lines)
    last = List.last(lines)

    %{
      kind: :raw,
      source:
        lines
        |> Enum.map(& &1.raw_line)
        |> Enum.join("\n")
        |> String.trim_trailing(),
      span: %{start_line: first.line_no, end_line: last.line_no}
    }
  end

  @spec take_source_block_until_close([scanned_line()], [scanned_line()], String.t()) ::
          {[scanned_line()], [scanned_line()]}
  defp take_source_block_until_close(lines, acc, opener_trimmed) do
    close_line? = comment_trick_close_line?(opener_trimmed)

    case lines do
      [] ->
        {acc, []}

      [line | rest] ->
        acc = acc ++ [line]

        if close_line?.(String.trim(line.raw_line)) do
          {acc, rest}
        else
          take_source_block_until_close(rest, acc, opener_trimmed)
        end
    end
  end

  @spec comment_trick_close_line?(String.t()) :: (String.t() -> boolean())
  defp comment_trick_close_line?(opener_trimmed) when is_binary(opener_trimmed) do
    if String.starts_with?(opener_trimmed, "{--") do
      &(&1 == "--}")
    else
      &(&1 == "-}")
    end
  end

  @spec comment_trick_opener?(String.t()) :: boolean()
  defp comment_trick_opener?(trimmed) do
    (String.starts_with?(trimmed, "{--") and trimmed != "{--}") or
      multiline_block_comment_opener?(trimmed)
  end

  @spec multiline_block_comment_opener?(String.t()) :: boolean()
  defp multiline_block_comment_opener?(trimmed) when is_binary(trimmed) do
    String.starts_with?(trimmed, "{-") and not String.starts_with?(trimmed, "{-|") and
      not String.ends_with?(trimmed, "-}")
  end

  @spec raw_top_level_declaration_line?(scanned_line()) :: boolean()
  defp raw_top_level_declaration_line?(line_info) do
    raw_trimmed = String.trim(line_info.raw_line)

    not line_info.indented? and raw_trimmed != "" and
      (infix_declaration_line?(raw_trimmed) or comment_only_raw_line?(raw_trimmed))
  end

  @spec infix_declaration_line?(String.t()) :: boolean()
  defp infix_declaration_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^infix(?:l|r)?\s+/u, trimmed)
  end

  @spec comment_only_raw_line?(String.t()) :: boolean()
  defp comment_only_raw_line?(trimmed) do
    section_border_line?(trimmed) or
      (String.starts_with?(trimmed, "--") and not section_border_line?(trimmed)) or
      (String.starts_with?(trimmed, "{-") and not String.starts_with?(trimmed, "{-|"))
  end

  @spec section_border_line?(String.t()) :: boolean()
  defp section_border_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^-+$/u, trimmed)
  end
end
