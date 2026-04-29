defmodule ElmEx.Frontend.GeneratedContractBuilder do
  @moduledoc """
  Generated-parser-owned builder that emits the frontend module/declaration/
  expression contract consumed by lowering and codegen.
  """

  alias ElmEx.Frontend.Module
  alias ElmEx.Frontend.GeneratedDeclarationParser
  alias ElmEx.Frontend.GeneratedExpressionParser

  @typep expr() :: map() | nil
  @typep decl() :: map()

  @spec build(String.t(), String.t(), String.t(), [String.t()]) :: Module.t()
  def build(path, source, module_name, imports) do
    scanned_lines =
      source
      |> GeneratedDeclarationParser.scan_lines()
      |> hydrate_multiline_non_function_decls()

    %{type_aliases: type_aliases, unions: unions, signatures: signatures} =
      collect_non_function_declarations(scanned_lines)

    declarations =
      type_aliases ++
        unions ++
        signatures ++
        parse_function_definitions(scanned_lines)

    %Module{
      name: module_name,
      path: path,
      imports: imports,
      declarations: declarations
    }
  end

  @spec hydrate_multiline_non_function_decls([map()]) :: [map()]
  defp hydrate_multiline_non_function_decls(scanned_lines) do
    do_hydrate_multiline_non_function_decls(scanned_lines, [])
  end

  @spec do_hydrate_multiline_non_function_decls([map()], [map()]) :: [map()]
  defp do_hydrate_multiline_non_function_decls([], acc), do: Enum.reverse(acc)

  defp do_hydrate_multiline_non_function_decls([line_info | rest], acc) do
    cond do
      multiline_signature_start?(line_info) ->
        {continuation, tail} = Enum.split_while(rest, &multiline_continuation_line?/1)
        hydrated = hydrate_multiline_signature_decl(line_info, continuation)

        do_hydrate_multiline_non_function_decls(
          tail,
          Enum.reverse([hydrated | continuation]) ++ acc
        )

      multiline_type_alias_start?(line_info) ->
        {continuation, tail} = Enum.split_while(rest, &multiline_continuation_line?/1)
        hydrated = hydrate_multiline_type_alias_decl(line_info, continuation)

        do_hydrate_multiline_non_function_decls(
          tail,
          Enum.reverse([hydrated | continuation]) ++ acc
        )

      multiline_union_start?(line_info) ->
        {continuation, tail} = Enum.split_while(rest, &multiline_continuation_line?/1)
        {hydrated, consumed} = hydrate_multiline_union_decl(line_info, continuation)
        do_hydrate_multiline_non_function_decls(tail, Enum.reverse([hydrated | consumed]) ++ acc)

      true ->
        do_hydrate_multiline_non_function_decls(rest, [line_info | acc])
    end
  end

  @spec multiline_signature_start?(map()) :: boolean()
  defp multiline_signature_start?(line_info) do
    line_info.decl == :none and
      not line_info.indented? and
      Regex.match?(~r/^[a-z][A-Za-z0-9_']*\s*:\s*$/u, line_info.trimmed)
  end

  @spec multiline_type_alias_start?(map()) :: boolean()
  defp multiline_type_alias_start?(line_info) do
    line_info.decl == :none and
      not line_info.indented? and
      String.starts_with?(line_info.trimmed, "type alias ")
  end

  @spec multiline_union_start?(map()) :: boolean()
  defp multiline_union_start?(line_info) do
    match?({:ok, {:union_start, _, :none}}, line_info.decl)
  end

  @spec multiline_continuation_line?(map()) :: boolean()
  defp multiline_continuation_line?(line_info) do
    line_info.indented? or line_info.trimmed == "" or String.starts_with?(line_info.trimmed, "--")
  end

  @spec hydrate_multiline_signature_decl(map(), [map()]) :: map()
  defp hydrate_multiline_signature_decl(line_info, continuation) do
    name = line_info.trimmed |> String.trim_trailing(":") |> String.trim()

    type_tail =
      continuation
      |> Enum.filter(&(not (&1.trimmed == "" or String.starts_with?(&1.trimmed, "--"))))
      |> Enum.map(& &1.trimmed)
      |> Enum.join(" ")

    case GeneratedDeclarationParser.parse_line("#{name} : #{type_tail}") do
      {:ok, {:function_signature, _, _} = sig} -> %{line_info | decl: {:ok, sig}}
      _ -> line_info
    end
  end

  @spec hydrate_multiline_type_alias_decl(map(), [map()]) :: map()
  defp hydrate_multiline_type_alias_decl(line_info, continuation) do
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
        |> Map.put(:type_alias_source, candidate)
        |> Map.put(:decl, {:ok, alias_decl})

      _ ->
        line_info
    end
  end

  @spec hydrate_multiline_union_decl(map(), [map()]) :: {map(), [map()]}
  defp hydrate_multiline_union_decl(line_info, continuation) do
    union_tail =
      continuation
      |> Enum.filter(&(not (&1.trimmed == "" or String.starts_with?(&1.trimmed, "--"))))
      |> Enum.map(& &1.trimmed)
      |> Enum.join(" ")

    candidate =
      [line_info.trimmed, union_tail]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    case GeneratedDeclarationParser.parse_line(candidate) do
      {:ok, {:union_start_many, _, _} = union_decl} ->
        {%{line_info | decl: {:ok, union_decl}}, mark_hydrated_union_consumed(continuation)}

      _ ->
        {line_info, continuation}
    end
  end

  @spec mark_hydrated_union_consumed([map()]) :: [map()]
  defp mark_hydrated_union_consumed(continuation) do
    Enum.map(continuation, fn line_info ->
      %{line_info | decl: :none, trimmed: ""}
    end)
  end

  @spec collect_non_function_declarations([map()]) :: %{
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
            fields =
              type_alias_record_fields(
                Map.get(line_info, :type_alias_source) || line_info.trimmed
              )

            {
              [
                %{
                  kind: :type_alias,
                  name: name,
                  fields: fields,
                  span: %{start_line: line_info.line_no, end_line: line_info.line_no}
                }
                | aliases_acc
              ],
              flush_union(unions_acc, union_current),
              sigs_acc,
              nil
            }

          {:ok, {:function_signature, name, type}} ->
            {aliases_acc, flush_union(unions_acc, union_current),
             [
               %{
                 kind: :function_signature,
                 name: name,
                 type: String.trim(type),
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

  @spec type_alias_record_fields(String.t()) :: [String.t()]
  defp type_alias_record_fields(source) when is_binary(source) do
    with {:ok, rhs} <- split_type_alias_rhs(source),
         {:ok, inner} <- record_type_body(rhs) do
      inner
      |> strip_extensible_record_base()
      |> split_top_level(",", [])
      |> Enum.flat_map(&record_field_name/1)
    else
      _ -> []
    end
  end

  defp type_alias_record_fields(_source), do: []

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

  @spec strip_extensible_record_base(String.t()) :: String.t()
  defp strip_extensible_record_base(source) do
    case split_top_level(source, "|", []) do
      [_base, fields] -> String.trim(fields)
      _ -> source
    end
  end

  @spec record_field_name(String.t()) :: [String.t()]
  defp record_field_name(source) do
    case split_top_level(source, ":", []) do
      [name, _type] ->
        name = String.trim(name)
        if valid_record_field_name?(name), do: [name], else: []

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

  @spec parse_function_definitions([map()]) :: [decl()]
  defp parse_function_definitions(scanned_lines) do
    scanned_lines
    |> Enum.reduce({[], nil}, fn line_info, {acc, current} ->
      parsed_header = line_info.function_header
      is_signature = match?({:ok, {:function_signature, _, _}}, line_info.decl)

      cond do
        current != nil and (line_info.indented? or current.in_multiline_string?) ->
          next_in_multiline_string =
            update_multiline_string_state(current.in_multiline_string?, line_info.raw_line)

          {acc,
           %{
             current
             | body_lines: current.body_lines ++ [String.trim(line_info.raw_line)],
               end_line: line_info.line_no,
               in_multiline_string?: next_in_multiline_string
           }}

        current != nil and line_info.trimmed == "" ->
          {acc, %{current | end_line: line_info.line_no}}

        match?({:ok, _}, parsed_header) and not is_signature ->
          {:ok, %{name: name, args: args, body: first_body}} = parsed_header
          flushed = maybe_flush_function(acc, current)

          {flushed,
           %{
             name: name,
             args: args,
             body_lines: [first_body],
             in_multiline_string?: update_multiline_string_state(false, first_body),
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

  @spec maybe_flush_function([decl()], map() | nil) :: [decl()]
  defp maybe_flush_function(acc, nil), do: acc

  defp maybe_flush_function(acc, current) do
    body =
      current.body_lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> String.trim()

    if body == "" do
      acc
    else
      [
        %{
          kind: :function_definition,
          name: current.name,
          args: current.args,
          body: body,
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

  @spec parse_expression(String.t() | nil, term()) :: map()
  defp parse_expression(_name, body) when not is_binary(body) do
    %{op: :unsupported, source: "non_binary"}
  end

  defp parse_expression(_name, body) do
    body = String.trim(body)
    generated_expr = maybe_generated_expr(body)

    generated_expr || %{op: :unsupported, source: body}
  end

  @spec maybe_generated_expr(String.t()) :: expr()
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

  @spec normalize_generated_expr(map()) :: map()
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

  @spec nested_field_access_expr([String.t()]) :: map()
  defp nested_field_access_expr([base | fields]) do
    Enum.reduce(fields, %{op: :var, name: base}, fn field, arg ->
      %{op: :field_access, arg: arg, field: field}
    end)
  end

  @spec allow_generated_expr?(expr()) :: boolean()
  defp allow_generated_expr?(%{op: op})
       when op in [
              :int_literal,
              :string_literal,
              :char_literal,
              :var,
              :add_const,
              :add_vars,
              :sub_const,
              :compare,
              :qualified_call,
              :constructor_call,
              :call,
              :tuple2,
              :list_literal,
              :field_access,
              :field_call,
              :compose_left,
              :compose_right,
              :lambda,
              :let_in,
              :if,
              :case,
              :record_literal,
              :record_update,
              :tuple_second_expr,
              :tuple_first_expr,
              :string_length_expr,
              :char_from_code_expr,
              :cmd_none
            ],
       do: true

  defp allow_generated_expr?(%{op: :qualified_call, args: args}) do
    Enum.all?(args, &allow_generated_expr?/1)
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

  defp allow_generated_expr?(_), do: false

  @spec parse_union_line(map(), [map()], map() | nil) :: {[map()], map() | nil}
  defp parse_union_line(line_info, acc, current) do
    line_no = line_info.line_no

    case line_info.decl do
      {:ok, {:union_start, union_name, :none}} ->
        {
          flush_union(acc, current),
          %{name: union_name, constructors: [], start_line: line_no, end_line: line_no}
        }

      {:ok, {:union_start_many, union_name, constructors}} ->
        {flush_union(acc, current),
         %{
           name: union_name,
           constructors: normalize_union_ctors(constructors),
           start_line: line_no,
           end_line: line_no
         }}

      {:ok, {:union_constructors, constructors}} when current != nil ->
        {acc,
         %{
           current
           | constructors: current.constructors ++ normalize_union_ctors(constructors),
             end_line: line_no
         }}

      {:ok, {:union_constructors, _constructors}} ->
        {acc, current}

      _ when current != nil ->
        if union_trivia_line?(line_info) do
          {acc, %{current | end_line: line_no}}
        else
          {flush_union(acc, current), nil}
        end

      _ ->
        {acc, current}
    end
  end

  @spec normalize_union_ctors(list()) :: [map()]
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

  @spec union_trivia_line?(map()) :: boolean()
  defp union_trivia_line?(line_info) do
    line_info.trimmed == "" or String.starts_with?(line_info.trimmed, "--")
  end

  @spec flush_union([decl()], map() | nil) :: [decl()]
  defp flush_union(acc, nil), do: acc

  defp flush_union(acc, current) do
    [
      %{
        kind: :union,
        name: current.name,
        constructors: current.constructors,
        span: %{
          start_line: current.start_line || 0,
          end_line: current.end_line || current.start_line || 0
        }
      }
      | acc
    ]
  end
end
