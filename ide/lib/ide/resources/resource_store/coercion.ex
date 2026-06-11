defmodule Ide.Resources.ResourceStore.Coercion do
  @moduledoc false

  alias Ide.Resources.Types

  @spec positive_integer_or_default(Types.wire_input(), integer()) :: integer()
  def positive_integer_or_default(value, _default) when is_integer(value) and value > 0,
    do: value

  def positive_integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  def positive_integer_or_default(_value, default), do: default

  @spec integer_or_zero(Types.wire_input()) :: non_neg_integer()
  def integer_or_zero(value) when is_integer(value) and value >= 0, do: value
  def integer_or_zero(_), do: 0

  @spec integer_or_default(Types.wire_input(), integer()) :: integer()
  def integer_or_default(value, _default) when is_integer(value), do: value

  def integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> default
    end
  end

  def integer_or_default(_value, default), do: default

  @spec string_list(list() | String.t() | nil) :: [String.t()]
  def string_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def string_list(value) when is_binary(value) do
    value
    |> String.split([",", " ", "\n", "\t"], trim: true)
    |> string_list()
  end

  def string_list(_), do: []
end
