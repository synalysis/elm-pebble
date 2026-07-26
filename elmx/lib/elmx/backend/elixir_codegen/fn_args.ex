defmodule Elmx.Backend.ElixirCodegen.FnArgs do
  @moduledoc false

  # IR still stores non-simple function parameters as source snippets
  # (e.g. `"(Rotation angle)"`). Classify them into real patterns so emit can
  # bind payload names in the Elixir function head.

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Patterns.Match.{Bindings, Pattern}

  @type classified :: {:simple, String.t()} | {:pattern, map()}

  @spec classify(term()) :: classified()
  def classify(arg) when is_binary(arg) do
    trimmed = String.trim(arg)
    stripped = strip_outer_parens(trimmed)

    cond do
      simple_ident?(stripped) ->
        {:simple, stripped}

      true ->
        # Keep parentheses for tuple patterns — `(x, y)` parses, `x, y` does not.
        case parse_pattern(trimmed) do
          {:ok, pattern} ->
            {:pattern, pattern}

          :error ->
            case parse_pattern(stripped) do
              {:ok, pattern} -> {:pattern, pattern}
              :error -> {:simple, trimmed}
            end
        end
    end
  end

  def classify(arg), do: {:simple, Helpers.param_name(arg)}

  @spec classify_all([term()]) :: [classified()]
  def classify_all(args) when is_list(args), do: Enum.map(args, &classify/1)

  @spec binding_names(classified()) :: [String.t()]
  def binding_names({:simple, name}) when is_binary(name), do: [name]
  def binding_names({:pattern, pattern}), do: Bindings.pattern_binding_names(pattern)

  @spec all_binding_names([classified()]) :: [String.t()]
  def all_binding_names(classified_args) when is_list(classified_args) do
    classified_args
    |> Enum.flat_map(&binding_names/1)
    |> Enum.uniq()
  end

  @spec put_env(map(), [classified()]) :: map()
  def put_env(env, classified_args) when is_map(env) and is_list(classified_args) do
    Enum.reduce(all_binding_names(classified_args), env, fn name, acc ->
      Map.put(acc, String.to_atom(name), true)
    end)
  end

  @spec emit_param(classified(), non_neg_integer(), MapSet.t(String.t())) :: String.t()
  def emit_param({:simple, name}, index, used_bindings)
      when is_binary(name) and is_integer(index) do
    emit_name = Helpers.param_var_name(name, %{})

    if MapSet.member?(used_bindings, name) or MapSet.member?(used_bindings, emit_name) do
      emit_name
    else
      "_unused#{index}"
    end
  end

  def emit_param({:pattern, pattern}, _index, used_bindings) do
    Pattern.pattern_arg(pattern, %{used_pattern_bindings: used_bindings})
  end

  @spec emit_params([classified()], MapSet.t(String.t())) :: String.t()
  def emit_params(classified_args, used_bindings)
      when is_list(classified_args) do
    Enum.map_join(Enum.with_index(classified_args), ", ", fn {arg, index} ->
      emit_param(arg, index, used_bindings)
    end)
  end

  defp parse_pattern(source) when is_binary(source) do
    case GeneratedExpressionParser.parse("case elmxArg of #{source} -> 0") do
      {:ok, %{op: :case, branches: [%{pattern: pattern} | _]}} when is_map(pattern) ->
        {:ok, pattern}

      _ ->
        :error
    end
  end

  defp simple_ident?(name) when is_binary(name) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_']*$/, name)
  end

  defp strip_outer_parens(text) when is_binary(text) do
    trimmed = String.trim(text)

    if outer_parens_wrap_all?(trimmed) do
      trimmed
      |> String.slice(1..-2//1)
      |> String.trim()
    else
      trimmed
    end
  end

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
