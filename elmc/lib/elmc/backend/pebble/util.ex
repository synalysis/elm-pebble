defmodule Elmc.Backend.Pebble.Util do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec macro_name(String.t()) :: Types.c_macro_name()
  def macro_name(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.upcase()
  end

  @type payload_arity_spec :: String.t() | nil

  @doc """
  Elm constructor arity from the payload type string stored on the union.

  Multi-arg constructors use space-separated args (`"Int Int"`,
  `"Bounds (DrawFunction units …)"`). A bare function type (`"a -> b"`) is a
  single payload. Parenthesized groups count as one token.
  """
  @spec payload_arity_for_spec(payload_arity_spec()) :: non_neg_integer()
  def payload_arity_for_spec(nil), do: 0

  @spec payload_arity_for_spec(String.t()) :: non_neg_integer()
  def payload_arity_for_spec(spec) when is_binary(spec) do
    text = String.trim(spec)

    if text == "" do
      0
    else
      tokens = split_top_level_type_tokens(text)

      # Bare `a -> b` is one function-like payload; multi-arg ctors parenthesize
      # function args so `->` never appears as a top-level token between them.
      if Enum.any?(tokens, &(&1 == "->")) do
        1
      else
        length(tokens)
      end
    end
  end

  @spec split_top_level_type_tokens(String.t()) :: [String.t()]
  def split_top_level_type_tokens(text) when is_binary(text) do
    chars = String.to_charlist(String.trim(text))

    {parts, current, _, _, _} =
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

  @spec direct_command_macro(Types.entry_module(), Types.decl_name()) :: Types.c_macro_name()
  def direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
  end

  @spec entry_fn_name(Types.entry_module(), Types.decl_name()) :: Types.c_symbol()
  def entry_fn_name(entry_module, decl_name) do
    "elmc_fn_#{String.replace(entry_module, ".", "_")}_#{decl_name}"
  end
end
