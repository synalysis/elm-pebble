defmodule ElmEx.IR.TypeSignature do
  @moduledoc """
  Lightweight parsing helpers for Elm type signatures used by call-site checks.
  """

  @builtin_types ~w(
    Int Float String Bool Char Order Maybe Result List Array Tuple Program Cmd Sub Task Platform
  )

  @spec arity(String.t()) :: non_neg_integer()
  def arity(type) when is_binary(type), do: param_types(type) |> length()

  @spec param_types(String.t()) :: [String.t()]
  def param_types(type) when is_binary(type) do
    type
    |> split_top_level_arrows()
    |> case do
      [] -> []
      [_only] -> []
      parts -> Enum.drop(parts, -1)
    end
  end

  @spec return_type(String.t()) :: String.t() | nil
  def return_type(type) when is_binary(type) do
    type
    |> split_top_level_arrows()
    |> List.last()
  end

  @spec type_variable?(String.t()) :: boolean()
  def type_variable?(type) when is_binary(type) do
    trimmed = String.trim(type)

    Regex.match?(~r/^[a-z][a-zA-Z0-9_']*$/, trimmed) and trimmed not in @builtin_types
  end

  @spec split_top_level_arrows(String.t()) :: [String.t()]
  def split_top_level_arrows(type) when is_binary(type) do
    type
    |> String.trim()
    |> split_top_level("->", [])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec record_field_names(String.t()) :: [String.t()]
  def record_field_names(type) when is_binary(type) do
    if record_type?(type) do
      type
      |> String.trim()
      |> String.trim_leading("{")
      |> String.trim_trailing("}")
      |> split_top_level(",", [])
      |> Enum.map(fn field ->
        field
        |> String.split(":", parts: 2)
        |> List.first()
        |> to_string()
        |> String.trim()
      end)
      |> Enum.reject(&(&1 == ""))
    else
      []
    end
  end

  @spec record_type?(String.t()) :: boolean()
  def record_type?(type) when is_binary(type) do
    String.starts_with?(String.trim(type), "{") and String.ends_with?(String.trim(type), "}")
  end

  @spec split_top_level(String.t(), String.t(), [String.t()]) :: [String.t()]
  defp split_top_level(source, separator, acc) when is_binary(source) and is_binary(separator) do
    do_split_top_level(source, separator, acc, "", 0, nil)
  end

  @spec do_split_top_level(
          String.t(),
          String.t(),
          [String.t()],
          String.t(),
          integer(),
          nil | integer()
        ) ::
          [String.t()]
  defp do_split_top_level(<<>>, _separator, acc, current, _depth, _quote) do
    finalize_token(acc, current)
  end

  defp do_split_top_level(<<char::utf8, rest::binary>>, separator, acc, current, depth, quote) do
    char_text = <<char::utf8>>

    cond do
      quote != nil and char == quote ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, nil)

      quote == nil and char in [?", ?'] ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, char)

      quote == nil and char in [?(, ?[, ?{] ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth + 1, quote)

      quote == nil and char in [?), ?], ?}] ->
        do_split_top_level(rest, separator, acc, current <> char_text, max(depth - 1, 0), quote)

      quote == nil and depth == 0 ->
        case separator_match(char_text, rest, separator) do
          {:yes, next_rest} ->
            token = String.trim(current)

            next_acc =
              if token == "" do
                acc
              else
                [token | acc]
              end

            do_split_top_level(next_rest, separator, next_acc, "", depth, quote)

          :no ->
            do_split_top_level(rest, separator, acc, current <> char_text, depth, quote)
        end

      true ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, quote)
    end
  end

  @spec separator_match(String.t(), String.t(), String.t()) :: {:yes, String.t()} | :no
  defp separator_match(char_text, rest, separator) when byte_size(separator) == 1 do
    if char_text == separator, do: {:yes, rest}, else: :no
  end

  defp separator_match(char_text, rest, separator) do
    combined = char_text <> rest

    if String.starts_with?(combined, separator) do
      {:yes, String.slice(combined, byte_size(separator)..-1//1)}
    else
      :no
    end
  end

  @spec finalize_token([String.t()], String.t()) :: [String.t()]
  defp finalize_token(acc, current) do
    token = String.trim(current)

    acc =
      if token == "" do
        acc
      else
        [token | acc]
      end

    acc |> Enum.reverse()
  end
end
