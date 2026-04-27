defmodule ElmEx.Frontend.GeneratedContractBuilder do
  @moduledoc """
  Generated-parser-owned builder that emits the frontend module/declaration/
  expression contract consumed by lowering and codegen.
  """

  alias ElmEx.Frontend.Module
  alias ElmEx.Frontend.GeneratedDeclarationParser
  alias ElmEx.Frontend.GeneratedExpressionParser

  @typep expr() :: map() | nil
  @typep pattern() :: map()
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
      {:ok, {:type_alias, _} = alias_decl} -> %{line_info | decl: {:ok, alias_decl}}
      _ -> line_info
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
            {
              [
                %{
                  kind: :type_alias,
                  name: name,
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
    parts = split_top_level_spaces(body)
    generated_expr = maybe_generated_expr(body)

    tuple =
      if String.starts_with?(body, "(") and String.ends_with?(body, ")") do
        inner = String.slice(body, 1, String.length(body) - 2)
        items = split_top_level_items(inner)

        if length(items) >= 2 do
          items
          |> Enum.map(&parse_expression(nil, String.trim(&1)))
          |> tuple_chain_expr()
        else
          nil
        end
      else
        nil
      end

    cond do
      generated_expr != nil ->
        generated_expr

      Regex.match?(~r/^"(?:[^"\\]|\\.)*"$/, body) ->
        %{op: :string_literal, value: parse_string_literal(body)}

      Regex.match?(~r/^'(?:[^'\\]|\\.)'$/, body) ->
        %{op: :char_literal, value: parse_char_literal(body)}

      String.starts_with?(body, "{") and String.ends_with?(body, "}") ->
        parse_record_literal(body)

      Regex.match?(~r/^[a-z][A-Za-z0-9_]*\.[a-z][A-Za-z0-9_]*\s+.+$/, body) ->
        [arg, field, args_source] =
          Regex.run(
            ~r/^([a-z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)\s+(.+)$/,
            body,
            capture: :all_but_first
          )

        args =
          split_top_level_spaces(args_source)
          |> Enum.map(&parse_expression(nil, &1))

        %{op: :field_call, arg: arg, field: field, args: args}

      Regex.match?(~r/^[a-z][A-Za-z0-9_]*\.[a-z][A-Za-z0-9_]*$/, body) ->
        [arg, field] =
          Regex.run(
            ~r/^([a-z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)$/,
            body,
            capture: :all_but_first
          )

        %{op: :field_access, arg: arg, field: field}

      Regex.match?(~r/^let\s+[a-z][A-Za-z0-9_]*\s*=.+\sin\s+.+$/s, body) ->
        [name, value_source, in_source] =
          Regex.run(
            ~r/^let\s+([a-z][A-Za-z0-9_]*)\s*=\s*(.+?)\s+in\s+(.+)$/s,
            body,
            capture: :all_but_first
          )

        %{
          op: :let_in,
          name: name,
          value_expr: parse_expression(nil, String.trim(value_source)),
          in_expr: parse_expression(nil, String.trim(in_source))
        }

      Regex.match?(~r/^if\s+.+\s+then\s+.+\s+else\s+.+$/s, body) ->
        [cond_source, then_source, else_source] =
          Regex.run(
            ~r/^if\s+(.+?)\s+then\s+(.+?)\s+else\s+(.+)$/s,
            body,
            capture: :all_but_first
          )

        %{
          op: :if,
          cond: parse_expression(nil, String.trim(cond_source)),
          then_expr: parse_expression(nil, String.trim(then_source)),
          else_expr: parse_expression(nil, String.trim(else_source))
        }

      String.starts_with?(body, "[") and String.ends_with?(body, "]") ->
        parse_list_literal(body)

      tuple != nil ->
        tuple

      has_outer_parens?(body) ->
        inner = String.slice(body, 1, String.length(body) - 2) |> String.trim()
        parse_expression(nil, inner)

      String.starts_with?(body, "case ") and String.contains?(body, " of") ->
        parse_case_expression(body)

      String.contains?(body, "Maybe.withDefault 0 (List.head ") ->
        [_, arg] = Regex.run(~r/Maybe\.withDefault 0 \(List\.head ([a-z][A-Za-z0-9_]*)\)/, body)
        %{op: :maybe_with_default_list_head, arg: arg, default: 0}

      String.contains?(body, "List.foldl (+) 0 ") ->
        [_, arg] = Regex.run(~r/List\.foldl \(\+\) 0 ([a-z][A-Za-z0-9_]*)/, body)
        %{op: :list_foldl_add_zero, arg: arg}

      String.contains?(body, "Maybe.withDefault 0 (Maybe.map ((+) 1)") ->
        [_, arg] =
          Regex.run(
            ~r/Maybe\.withDefault 0 \(Maybe\.map \(\(\+\) 1\) ([a-z][A-Za-z0-9_]*)\)/,
            body
          )

        %{op: :maybe_inc, arg: arg}

      String.starts_with?(body, "Tuple.second ") ->
        arg_source = body |> String.replace_prefix("Tuple.second ", "") |> String.trim()
        %{op: :tuple_second_expr, arg: parse_expression(nil, arg_source)}

      String.starts_with?(body, "Tuple.first ") ->
        arg_source = body |> String.replace_prefix("Tuple.first ", "") |> String.trim()
        %{op: :tuple_first_expr, arg: parse_expression(nil, arg_source)}

      String.starts_with?(body, "String.length ") ->
        arg_source = body |> String.replace_prefix("String.length ", "") |> String.trim()
        %{op: :string_length_expr, arg: parse_expression(nil, arg_source)}

      String.starts_with?(body, "Char.fromCode ") ->
        arg_source = body |> String.replace_prefix("Char.fromCode ", "") |> String.trim()
        %{op: :char_from_code_expr, arg: parse_expression(nil, arg_source)}

      body == "Cmd.none" ->
        %{op: :cmd_none}

      Regex.match?(~r/^\\[a-z][A-Za-z0-9_]*\s*->\s*.+$/s, body) ->
        [arg, lambda_body] =
          Regex.run(~r/^\\([a-z][A-Za-z0-9_]*)\s*->\s*(.+)$/s, body, capture: :all_but_first)

        %{op: :lambda, args: [arg], body: parse_expression(nil, String.trim(lambda_body))}

      length(parts) > 1 and
          Regex.match?(~r/^[A-Z][A-Za-z0-9_.]*\.[a-z][A-Za-z0-9_]*$/, hd(parts)) ->
        [target | arg_parts] = parts

        %{
          op: :qualified_call,
          target: target,
          args: Enum.map(arg_parts, &parse_expression(nil, &1))
        }

      length(parts) > 1 and
          Regex.match?(~r/^[A-Z][A-Za-z0-9_.]*\.[A-Z][A-Za-z0-9_]*$/, hd(parts)) ->
        [target | arg_parts] = parts

        %{
          op: :constructor_call,
          target: target,
          args: Enum.map(arg_parts, &parse_expression(nil, &1))
        }

      length(parts) > 1 and Regex.match?(~r/^[A-Z][A-Za-z0-9_]*$/, hd(parts)) ->
        [target | arg_parts] = parts

        %{
          op: :constructor_call,
          target: target,
          args: Enum.map(arg_parts, &parse_expression(nil, &1))
        }

      Regex.match?(~r/^[A-Z][A-Za-z0-9_.]*\.[a-z][A-Za-z0-9_]*(\s+.+)?$/, body) ->
        [target | arg_parts] = parts

        args =
          arg_parts
          |> Enum.map(&parse_expression(nil, &1))

        %{op: :qualified_call, target: target, args: args}

      Regex.match?(~r/^[A-Z][A-Za-z0-9_.]*\.[A-Z][A-Za-z0-9_]*(\s+.+)?$/, body) ->
        [target | arg_parts] = parts

        args =
          arg_parts
          |> Enum.map(&parse_expression(nil, &1))

        %{op: :constructor_call, target: target, args: args}

      Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(\s+.+)?$/, body) ->
        [target | arg_parts] = parts

        args =
          arg_parts
          |> Enum.map(&parse_expression(nil, &1))

        %{op: :constructor_call, target: target, args: args}

      Regex.match?(~r/^[a-z][A-Za-z0-9_]*\s*(==|>|<)\s*[a-z][A-Za-z0-9_]*$/, body) ->
        parse_compare_expr(body)

      Regex.match?(~r/^[a-z][A-Za-z0-9_]*\s*(==|>|<)\s*[0-9]+$/, body) ->
        parse_compare_expr(body)

      Regex.match?(~r/^[a-z][A-Za-z0-9_]* \+ [0-9]+$/, body) ->
        [var, int] =
          Regex.run(~r/^([a-z][A-Za-z0-9_]*) \+ ([0-9]+)$/, body, capture: :all_but_first)

        %{op: :add_const, var: var, value: String.to_integer(int)}

      Regex.match?(~r/^-?[0-9]+$/, body) ->
        %{op: :int_literal, value: String.to_integer(body)}

      Regex.match?(~r/^[a-z][A-Za-z0-9_]* \+ [a-z][A-Za-z0-9_]*$/, body) ->
        [left, right] =
          Regex.run(
            ~r/^([a-z][A-Za-z0-9_]*) \+ ([a-z][A-Za-z0-9_]*)$/,
            body,
            capture: :all_but_first
          )

        %{op: :add_vars, left: left, right: right}

      Regex.match?(~r/^[a-z][A-Za-z0-9_]* - [0-9]+$/, body) ->
        [var, int] =
          Regex.run(~r/^([a-z][A-Za-z0-9_]*) - ([0-9]+)$/, body, capture: :all_but_first)

        %{op: :sub_const, var: var, value: String.to_integer(int)}

      Regex.match?(~r/^[a-z][A-Za-z0-9_]*$/, body) ->
        %{op: :var, name: body}

      Regex.match?(~r/^[a-z][A-Za-z0-9_]*\s+.+$/, body) ->
        [name, args_source] =
          Regex.run(~r/^([a-z][A-Za-z0-9_]*)\s+(.+)$/, body, capture: :all_but_first)

        args =
          split_top_level_spaces(args_source)
          |> Enum.map(&parse_expression(nil, &1))

        %{op: :call, name: name, args: args}

      true ->
        %{op: :unsupported, source: body}
    end
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

  defp normalize_generated_expr(%{
         op: :qualified_call,
         target: "List.foldl",
         args: [
           %{op: :var, name: "__add__"},
           %{op: :int_literal, value: 0},
           %{op: :var, name: arg}
         ]
       }) do
    %{op: :list_foldl_add_zero, arg: arg}
  end

  defp normalize_generated_expr(%{
         op: :qualified_call,
         target: "Maybe.withDefault",
         args: [
           %{op: :int_literal, value: 0},
           %{
             op: :qualified_call,
             target: "Maybe.map",
             args: [add_one_fun, %{op: :var, name: arg}]
           }
         ]
       }) do
    if generated_add_one_fun?(add_one_fun) do
      %{op: :maybe_inc, arg: arg}
    else
      %{
        op: :qualified_call,
        target: "Maybe.withDefault",
        args: [
          %{op: :int_literal, value: 0},
          %{
            op: :qualified_call,
            target: "Maybe.map",
            args: [normalize_generated_expr(add_one_fun), %{op: :var, name: arg}]
          }
        ]
      }
    end
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

  defp normalize_generated_expr(expr), do: expr

  @spec nested_field_access_expr([String.t()]) :: map()
  defp nested_field_access_expr([base | fields]) do
    Enum.reduce(fields, %{op: :var, name: base}, fn field, arg ->
      %{op: :field_access, arg: arg, field: field}
    end)
  end

  @spec generated_add_one_fun?(term()) :: boolean()
  defp generated_add_one_fun?(%{op: :call, name: "__add__", args: [%{op: :int_literal, value: 1}]}),
       do: true

  defp generated_add_one_fun?(_), do: false

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
              :tuple_second_expr,
              :tuple_first_expr,
              :string_length_expr,
              :char_from_code_expr,
              :cmd_none,
              :list_foldl_add_zero,
              :maybe_inc
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

  defp allow_generated_expr?(_), do: false

  @spec parse_string_literal(String.t()) :: String.t()
  defp parse_string_literal(body) do
    body
    |> String.slice(1, String.length(body) - 2)
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\", "\\")
  end

  @spec parse_char_literal(String.t()) :: non_neg_integer()
  defp parse_char_literal(body) do
    inner =
      body
      |> String.slice(1, String.length(body) - 2)
      |> String.replace("\\'", "'")
      |> String.replace("\\\\", "\\")

    case String.to_charlist(inner) do
      [code] -> code
      _ -> 0
    end
  end

  @spec parse_compare_expr(String.t()) :: map()
  defp parse_compare_expr(body) do
    [left, op, right] =
      Regex.run(
        ~r/^([a-z][A-Za-z0-9_]*)\s*(==|>|<)\s*([a-z][A-Za-z0-9_]*|[0-9]+)$/,
        body,
        capture: :all_but_first
      )

    right_expr =
      if Regex.match?(~r/^[0-9]+$/, right) do
        %{op: :int_literal, value: String.to_integer(right)}
      else
        %{op: :var, name: right}
      end

    kind =
      case op do
        "==" -> :eq
        ">" -> :gt
        "<" -> :lt
      end

    %{op: :compare, kind: kind, left: %{op: :var, name: left}, right: right_expr}
  end

  @spec parse_list_literal(String.t()) :: map()
  defp parse_list_literal(body) do
    inner = String.slice(body, 1, String.length(body) - 2)

    items =
      inner
      |> split_top_level_items()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_expression(nil, &1))

    %{op: :list_literal, items: items}
  end

  @spec parse_record_literal(String.t()) :: map()
  defp parse_record_literal(body) do
    inner = String.slice(body, 1, String.length(body) - 2)

    fields =
      inner
      |> split_top_level_items()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn field_source ->
        case Regex.run(~r/^([a-z][A-Za-z0-9_]*)\s*=\s*(.+)$/s, field_source,
               capture: :all_but_first
             ) do
          [name, value_source] ->
            %{name: name, expr: parse_expression(nil, String.trim(value_source))}

          _ ->
            %{name: "_invalid", expr: %{op: :unsupported, source: field_source}}
        end
      end)

    %{op: :record_literal, fields: fields}
  end

  @spec parse_case_expression(String.t()) :: map()
  defp parse_case_expression(body) do
    lines =
      body
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [header | rest] ->
        case Regex.run(
               ~r/^case\s+([a-z][A-Za-z0-9_]*(?:\.[a-z][A-Za-z0-9_]*)*)\s+of$/,
               header,
               capture: :all_but_first
             ) do
          [subject] ->
            %{op: :case, subject: subject, branches: parse_case_branches(rest)}

          _ ->
            %{op: :unsupported, source: body}
        end

      _ ->
        %{op: :unsupported, source: body}
    end
  end

  @spec parse_case_branches([String.t()]) :: [map()]
  defp parse_case_branches(lines) do
    lines
    |> Enum.reduce({[], nil}, fn line, {acc, current} ->
      case Regex.run(~r/^(.+?)\s*->\s*(.*)$/, line, capture: :all_but_first) do
        [pattern, rhs] ->
          flushed = flush_branch(acc, current)

          expr_lines =
            if String.trim(rhs) == "" do
              []
            else
              [String.trim(rhs)]
            end

          {flushed, %{pattern: parse_pattern(String.trim(pattern)), expr_lines: expr_lines}}

        _ ->
          if current do
            {acc, %{current | expr_lines: current.expr_lines ++ [line]}}
          else
            {acc, current}
          end
      end
    end)
    |> then(fn {acc, current} -> Enum.reverse(flush_branch(acc, current)) end)
  end

  @spec flush_branch([map()], map() | nil) :: [map()]
  defp flush_branch(acc, nil), do: acc

  defp flush_branch(acc, current) do
    expr =
      current.expr_lines
      |> Enum.join("\n")
      |> String.trim()
      |> then(&parse_expression(nil, &1))

    [%{pattern: current.pattern, expr: expr} | acc]
  end

  @spec parse_pattern(term()) :: pattern()
  defp parse_pattern(pattern) when not is_binary(pattern), do: %{kind: :unknown, source: pattern}
  defp parse_pattern("_"), do: %{kind: :wildcard}

  defp parse_pattern(pattern) do
    grouped =
      if String.starts_with?(pattern, "(") and String.ends_with?(pattern, ")") do
        String.slice(pattern, 1, String.length(pattern) - 2) |> String.trim()
      else
        nil
      end

    case split_tuple(pattern) do
      {left, right} ->
        %{kind: :tuple, elements: [parse_pattern(left), parse_pattern(right)]}

      :not_tuple ->
        if grouped != nil do
          parse_pattern(grouped)
        else
          parse_non_tuple_pattern(pattern)
        end
    end
  end

  @spec parse_non_tuple_pattern(String.t()) :: pattern()
  defp parse_non_tuple_pattern(pattern) do
    constructor =
      Regex.run(
        ~r/^([A-Z][A-Za-z0-9_]*)(?:\s+([a-z_][A-Za-z0-9_]*))?$/,
        pattern,
        capture: :all_but_first
      )

    case constructor do
      [name, bind] ->
        bind_name = if bind == "_", do: nil, else: bind
        %{kind: :constructor, name: name, bind: bind_name, arg_pattern: nil}

      [name] ->
        %{kind: :constructor, name: name, bind: nil, arg_pattern: nil}

      _ ->
        case Regex.run(~r/^([A-Z][A-Za-z0-9_]*)\s+(.+)$/, pattern, capture: :all_but_first) do
          [name, arg_pattern] ->
            %{
              kind: :constructor,
              name: name,
              bind: nil,
              arg_pattern: parse_pattern(String.trim(arg_pattern))
            }

          _ ->
            parse_var_or_unknown(pattern)
        end
    end
  end

  @spec parse_var_or_unknown(String.t()) :: pattern()
  defp parse_var_or_unknown(pattern) do
    if Regex.match?(~r/^[a-z][A-Za-z0-9_]*$/, pattern) do
      %{kind: :var, name: pattern}
    else
      %{kind: :unknown, source: pattern}
    end
  end

  @spec split_tuple(term()) :: {String.t(), String.t()} | :not_tuple
  defp split_tuple(body) do
    if not is_binary(body) do
      :not_tuple
    else
      body = String.trim(body)

      if String.starts_with?(body, "(") and String.ends_with?(body, ")") do
        inner = String.slice(body, 1, String.length(body) - 2)

        case split_top_level_comma(inner) do
          {left, right} when is_binary(left) and is_binary(right) ->
            {String.trim(left), String.trim(right)}

          _ ->
            :not_tuple
        end
      else
        :not_tuple
      end
    end
  end

  @spec tuple_chain_expr([expr()]) :: map()
  defp tuple_chain_expr([left, right]), do: %{op: :tuple2, left: left, right: right}

  defp tuple_chain_expr([head | rest]) do
    %{op: :tuple2, left: head, right: tuple_chain_expr(rest)}
  end

  @spec split_top_level_comma(String.t()) :: {String.t(), String.t()} | :none
  defp split_top_level_comma(text) do
    chars = String.to_charlist(text)

    {idx, _paren_depth, _bracket_depth, _brace_depth} =
      Enum.reduce_while(
        Enum.with_index(chars),
        {nil, 0, 0, 0},
        fn {char, i}, {_idx, paren_depth, bracket_depth, brace_depth} ->
          cond do
            char == ?( ->
              {:cont, {nil, paren_depth + 1, bracket_depth, brace_depth}}

            char == ?) ->
              {:cont, {nil, max(paren_depth - 1, 0), bracket_depth, brace_depth}}

            char == ?[ ->
              {:cont, {nil, paren_depth, bracket_depth + 1, brace_depth}}

            char == ?] ->
              {:cont, {nil, paren_depth, max(bracket_depth - 1, 0), brace_depth}}

            char == ?{ ->
              {:cont, {nil, paren_depth, bracket_depth, brace_depth + 1}}

            char == ?} ->
              {:cont, {nil, paren_depth, bracket_depth, max(brace_depth - 1, 0)}}

            char == ?, and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0 ->
              {:halt, {i, paren_depth, bracket_depth, brace_depth}}

            true ->
              {:cont, {nil, paren_depth, bracket_depth, brace_depth}}
          end
        end
      )

    if idx == nil do
      :none
    else
      left = String.slice(text, 0, idx)
      right = String.slice(text, idx + 1, String.length(text) - idx - 1)
      {left, right}
    end
  end

  @spec split_top_level_items(String.t()) :: [String.t()]
  defp split_top_level_items(text) do
    chars = String.to_charlist(text)

    {parts, current, _paren_depth, _bracket_depth, _brace_depth} =
      Enum.reduce(chars, {[], [], 0, 0, 0}, fn char,
                                               {parts, current, paren_depth, bracket_depth,
                                                brace_depth} ->
        cond do
          char == ?( ->
            {parts, [char | current], paren_depth + 1, bracket_depth, brace_depth}

          char == ?) ->
            {parts, [char | current], max(paren_depth - 1, 0), bracket_depth, brace_depth}

          char == ?[ ->
            {parts, [char | current], paren_depth, bracket_depth + 1, brace_depth}

          char == ?] ->
            {parts, [char | current], paren_depth, max(bracket_depth - 1, 0), brace_depth}

          char == ?{ ->
            {parts, [char | current], paren_depth, bracket_depth, brace_depth + 1}

          char == ?} ->
            {parts, [char | current], paren_depth, bracket_depth, max(brace_depth - 1, 0)}

          char == ?, and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0 ->
            part = current |> Enum.reverse() |> to_string() |> String.trim()
            {parts ++ [part], [], paren_depth, bracket_depth, brace_depth}

          true ->
            {parts, [char | current], paren_depth, bracket_depth, brace_depth}
        end
      end)

    last = current |> Enum.reverse() |> to_string() |> String.trim()
    all = if last == "", do: parts, else: parts ++ [last]
    Enum.reject(all, &(&1 == ""))
  end

  @spec split_top_level_spaces(String.t()) :: [String.t()]
  defp split_top_level_spaces(text) do
    chars = String.to_charlist(text)

    {parts, current, _paren_depth, _bracket_depth, _brace_depth} =
      Enum.reduce(chars, {[], [], 0, 0, 0}, fn char,
                                               {parts, current, paren_depth, bracket_depth,
                                                brace_depth} ->
        cond do
          char == ?( ->
            {parts, [char | current], paren_depth + 1, bracket_depth, brace_depth}

          char == ?) ->
            {parts, [char | current], max(paren_depth - 1, 0), bracket_depth, brace_depth}

          char == ?[ ->
            {parts, [char | current], paren_depth, bracket_depth + 1, brace_depth}

          char == ?] ->
            {parts, [char | current], paren_depth, max(bracket_depth - 1, 0), brace_depth}

          char == ?{ ->
            {parts, [char | current], paren_depth, bracket_depth, brace_depth + 1}

          char == ?} ->
            {parts, [char | current], paren_depth, bracket_depth, max(brace_depth - 1, 0)}

          (char == ?\s or char == ?\n or char == ?\t or char == ?\r) and paren_depth == 0 and
            bracket_depth == 0 and brace_depth == 0 ->
            token = current |> Enum.reverse() |> to_string() |> String.trim()

            if token == "" do
              {parts, [], paren_depth, bracket_depth, brace_depth}
            else
              {parts ++ [token], [], paren_depth, bracket_depth, brace_depth}
            end

          true ->
            {parts, [char | current], paren_depth, bracket_depth, brace_depth}
        end
      end)

    last = current |> Enum.reverse() |> to_string() |> String.trim()
    all = if last == "", do: parts, else: parts ++ [last]
    Enum.reject(all, &(&1 == ""))
  end

  @spec has_outer_parens?(String.t()) :: boolean()
  defp has_outer_parens?(text) when is_binary(text) do
    if String.length(text) < 2 or not String.starts_with?(text, "(") or
         not String.ends_with?(text, ")") do
      false
    else
      chars = String.to_charlist(text)

      {_depth, enclosed} =
        Enum.reduce(Enum.with_index(chars), {0, true}, fn {char, idx}, {depth, enclosed} ->
          cond do
            char == ?( ->
              {depth + 1, enclosed}

            char == ?) ->
              next_depth = depth - 1
              closes_early = next_depth == 0 and idx < length(chars) - 1
              {next_depth, enclosed and not closes_early}

            true ->
              {depth, enclosed}
          end
        end)

      enclosed
    end
  end

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
