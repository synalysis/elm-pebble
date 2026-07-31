defmodule ElmEx.IR.FnArgDesugar do
  @moduledoc """
  Desugar non-simple top-level function parameters into simple idents + `case`.

  Frontend IR keeps complex header args as source snippets
  (e.g. `"(Array_elm_builtin len _ _ _)"`). Lambdas already normalize these in
  the expression parser; function decls did not. Rewrite once here so every
  backend sees C-/Elixir-safe param names and pattern bindings in the body.
  """
  alias ElmEx.Frontend.GeneratedExpressionParser

  @spec desugar_function(map()) :: map()
  def desugar_function(%{kind: :function, args: args, expr: expr} = decl)
      when is_list(args) and is_map(expr) do
    {new_args, new_expr} = desugar_args(args, expr)
    %{decl | args: new_args, expr: new_expr}
  end

  def desugar_function(decl), do: decl

  @spec desugar_args([term()], map()) :: {[String.t()], map()}
  def desugar_args(args, expr) when is_list(args) and is_map(expr) do
    {names, body, _counter} =
      Enum.reduce(args, {[], expr, 1}, fn arg, {acc_names, acc_expr, counter} ->
        case classify(arg) do
          {:simple, name} ->
            {acc_names ++ [name], acc_expr, counter}

          {:wildcard, _} ->
            name = ignored_arg_name(counter)
            {acc_names ++ [name], acc_expr, counter + 1}

          {:pattern, pattern} ->
            name = pattern_arg_name(counter)
            wrapped = wrap_case(name, pattern, acc_expr)
            {acc_names ++ [name], wrapped, counter + 1}
        end
      end)

    {names, body}
  end

  @spec classify(String.t() | term()) :: {:simple, String.t()} | {:wildcard, String.t()} | {:pattern, map()}

  defp classify(arg) when is_binary(arg) do
    trimmed = String.trim(arg)
    stripped = strip_outer_parens(trimmed)

    cond do
      stripped in ["_", ""] ->
        {:wildcard, stripped}

      simple_ident?(stripped) ->
        {:simple, stripped}

      true ->
        # Prefer the original (possibly parenthesized) source. Stripping
        # `(x, y)` → `x, y` makes tuple patterns fail to parse.
        case parse_pattern(trimmed) do
          {:ok, pattern} ->
            {:pattern, pattern}

          :error ->
            case parse_pattern(stripped) do
              {:ok, pattern} -> {:pattern, pattern}
              :error -> {:simple, sanitize_fallback(trimmed)}
            end
        end
    end
  end

  defp classify(_), do: {:simple, "arg"}

  @spec parse_pattern(String.t()) :: {:ok, map()} | :error

  defp parse_pattern(source) when is_binary(source) do
    # Subject must not contain `_` — the expr lexer treats `_…` as wildcards
    # (`__fnArg` fails; `elmxArg` / `fnArg` parse cleanly).
    case GeneratedExpressionParser.parse("case fnArg of #{source} -> 0") do
      {:ok, %{op: :case, branches: [%{pattern: pattern} | _]}} when is_map(pattern) ->
        {:ok, pattern}

      _ ->
        :error
    end
  end

  @spec wrap_case(String.t(), map(), map()) :: map()

  defp wrap_case(name, pattern, body) when is_binary(name) and is_map(pattern) and is_map(body) do
    %{
      op: :case,
      subject: %{op: :var, name: name},
      branches: [%{pattern: pattern, expr: body}]
    }
  end

  @spec pattern_arg_name(integer()) :: String.t()

  defp pattern_arg_name(1), do: "patternArg"
  defp pattern_arg_name(n) when is_integer(n), do: "patternArg#{n}"

  @spec ignored_arg_name(integer()) :: String.t()

  defp ignored_arg_name(1), do: "ignoredArg"
  defp ignored_arg_name(n) when is_integer(n), do: "ignoredArg#{n}"

  @spec simple_ident?(String.t()) :: boolean()

  defp simple_ident?(name) when is_binary(name),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_']*$/, name)

  # Last-resort: keep a C-/Elixir-safe token if pattern parse fails.
  @spec sanitize_fallback(String.t()) :: String.t()

  defp sanitize_fallback(name) when is_binary(name) do
    cleaned =
      name
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.trim("_")

    case cleaned do
      "" -> "arg"
      <<c::utf8, _::binary>> when c in ?0..?9 -> "arg_#{cleaned}"
      other -> other
    end
  end

  @spec strip_outer_parens(String.t()) :: String.t()

  defp strip_outer_parens(text) when is_binary(text) do
    trimmed = String.trim(text)

    if outer_parens_wrap_all?(trimmed) do
      trimmed
      |> String.slice(1..-2//1)
      |> String.trim()
      |> strip_outer_parens()
    else
      trimmed
    end
  end

  @spec outer_parens_wrap_all?(String.t()) :: boolean()

  defp outer_parens_wrap_all?(text) when is_binary(text) do
    graphemes = String.graphemes(text)
    last = length(graphemes) - 1

    case graphemes do
      ["(" | _] when last > 0 ->
        graphemes
        |> Enum.with_index()
        |> Enum.reduce_while({0, true}, fn {ch, idx}, {depth, _} ->
          depth =
            case ch do
              "(" -> depth + 1
              ")" -> depth - 1
              _ -> depth
            end

          cond do
            depth < 0 ->
              {:halt, :error}

            depth == 0 and idx != last ->
              {:halt, :error}

            true ->
              {:cont, {depth, true}}
          end
        end)
        |> case do
          {0, true} -> true
          _ -> false
        end

      _ ->
        false
    end
  end
end
