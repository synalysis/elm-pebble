defmodule Elmx.Runtime.Core.Chars do
  @moduledoc false

  @spec to_code(term()) :: integer()
  def to_code(ch) when is_binary(ch) and byte_size(ch) > 0 do
    ch |> String.to_charlist() |> hd()
  end

  def to_code(ch) when is_integer(ch), do: ch
  def to_code(_), do: 0

  @spec to_lower(term()) :: binary()
  def to_lower(ch) when is_binary(ch), do: String.downcase(ch)
  def to_lower(ch) when is_integer(ch), do: <<ch::utf8>> |> String.downcase()
  def to_lower(_), do: ""

  @spec to_upper(term()) :: binary()
  def to_upper(ch) when is_binary(ch), do: String.upcase(ch)
  def to_upper(ch) when is_integer(ch), do: <<ch::utf8>> |> String.upcase()
  def to_upper(_), do: ""

  @spec is_digit(term()) :: boolean()
  def is_digit(ch), do: category?(ch, &String.match?(&1, ~r/^\d$/))

  @spec is_hex_digit(term()) :: boolean()
  def is_hex_digit(ch), do: category?(ch, &String.match?(&1, ~r/^[0-9A-Fa-f]$/))

  @spec is_oct_digit(term()) :: boolean()
  def is_oct_digit(ch), do: category?(ch, &String.match?(&1, ~r/^[0-7]$/))

  @spec is_lower(term()) :: boolean()
  def is_lower(ch), do: category?(ch, &String.match?(&1, ~r/^[a-z]$/))

  @spec is_upper(term()) :: boolean()
  def is_upper(ch), do: category?(ch, &String.match?(&1, ~r/^[A-Z]$/))

  @spec is_alpha(term()) :: boolean()
  def is_alpha(ch), do: is_lower(ch) or is_upper(ch)

  @spec is_alpha_num(term()) :: boolean()
  def is_alpha_num(ch), do: is_alpha(ch) or is_digit(ch)

  defp category?(ch, pred) do
    case normalize_char(ch) do
      {:ok, grapheme} -> pred.(grapheme)
      :error -> false
    end
  end

  defp normalize_char(ch) when is_binary(ch) and ch != "", do: {:ok, ch}
  defp normalize_char(ch) when is_integer(ch), do: {:ok, <<ch::utf8>>}
  defp normalize_char(_), do: :error
end
