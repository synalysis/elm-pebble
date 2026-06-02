defmodule Elmx.Runtime.Core.Strings do
  @moduledoc false

  alias Elmx.Runtime.Core

  @spec append(term(), term()) :: binary()
  def append(left, right), do: to_string(left) <> to_string(right)

  @spec is_empty(term()) :: boolean()
  def is_empty(value), do: value == "" or value == [] or value == nil

  @spec length_val(term()) :: integer()
  def length_val(value) when is_binary(value), do: String.length(value)
  def length_val(value) when is_list(value), do: length(value)
  def length_val(_), do: 0

  @spec from_int(integer()) :: binary()
  def from_int(n) when is_integer(n), do: Integer.to_string(n)

  @spec from_float(term()) :: binary()
  def from_float(n) when is_float(n), do: :erlang.float_to_binary(n, [:compact, decimals: 16])
  def from_float(n) when is_integer(n), do: Integer.to_string(n)
  def from_float(_), do: "0"

  @spec to_int(term()) :: term()
  def to_int(text) when is_binary(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} -> {:Just, n}
      _ -> :Nothing
    end
  end

  def to_int(_), do: :Nothing

  @spec to_float(term()) :: term()
  def to_float(text) when is_binary(text) do
    case Float.parse(String.trim(text)) do
      {f, ""} -> {:Ok, f}
      _ -> {:Err, "NOT_A_FLOAT"}
    end
  end

  @spec to_list(binary()) :: list()
  def to_list(text) when is_binary(text) do
    for <<c::utf8 <- text>>, do: <<c::utf8>>
  end

  @spec from_list(list()) :: binary()
  def from_list(chars) when is_list(chars), do: Enum.join(chars, "")

  @spec from_char(term()) :: binary()
  def from_char(ch) when is_binary(ch), do: ch
  def from_char(ch) when is_integer(ch), do: <<ch::utf8>>
  def from_char(_), do: ""

  @spec cons(term(), binary()) :: binary()
  def cons(head, tail) when is_binary(tail), do: to_string(head) <> tail

  @spec uncons(binary()) :: term()
  def uncons(""), do: :Nothing

  def uncons(<<h::utf8, rest::binary>>), do: {:Just, {<<h::utf8>>, rest}}
  def uncons(binary) when is_binary(binary), do: {:Just, {binary, ""}}

  @spec reverse(binary()) :: binary()
  def reverse(text) when is_binary(text), do: String.reverse(text)

  @spec split(term(), binary()) :: list()
  def split(sep, text) when is_binary(text), do: String.split(text, to_string(sep))

  @spec join(term(), list()) :: binary()
  def join(sep, parts) when is_list(parts), do: Enum.map_join(parts, to_string(sep))

  @spec slice(term(), term(), binary()) :: binary()
  def slice(start, length, text) when is_binary(text) do
    start = to_int(start, 0)
    len = to_int(length, 0)
    String.slice(text, start, len)
  end

  @spec left(term(), binary()) :: binary()
  def left(n, text) when is_binary(text), do: String.slice(text, 0, to_int(n, 0))

  @spec right(term(), binary()) :: binary()
  def right(n, text) when is_binary(text) do
    len = to_int(n, 0)
    String.slice(text, -len, len)
  end

  @spec drop_left(term(), binary()) :: binary()
  def drop_left(n, text) when is_binary(text), do: String.slice(text, to_int(n, 0)..-1//1)

  @spec drop_right(term(), binary()) :: binary()
  def drop_right(n, text) when is_binary(text) do
    count = to_int(n, 0)
    String.slice(text, 0, max(String.length(text) - count, 0))
  end

  @spec trim(binary()) :: binary()
  def trim(text) when is_binary(text), do: String.trim(text)

  @spec trim_left(binary()) :: binary()
  def trim_left(text) when is_binary(text), do: String.trim_leading(text)

  @spec trim_right(binary()) :: binary()
  def trim_right(text) when is_binary(text), do: String.trim_trailing(text)

  @spec to_upper(binary()) :: binary()
  def to_upper(text) when is_binary(text), do: String.upcase(text)

  @spec to_lower(binary()) :: binary()
  def to_lower(text) when is_binary(text), do: String.downcase(text)

  @spec starts_with(term(), binary()) :: boolean()
  def starts_with(prefix, text) when is_binary(text), do: String.starts_with?(text, to_string(prefix))

  @spec ends_with(term(), binary()) :: boolean()
  def ends_with(suffix, text) when is_binary(text), do: String.ends_with?(text, to_string(suffix))

  @spec contains(term(), binary()) :: boolean()
  def contains(substr, text) when is_binary(text), do: String.contains?(text, to_string(substr))

  @spec repeat(term(), binary()) :: binary()
  def repeat(n, text) when is_binary(text) do
    String.duplicate(text, max(to_int(n, 0), 0))
  end

  @spec replace(term(), term(), binary()) :: binary()
  def replace(before, after_str, text) when is_binary(text) do
    String.replace(text, to_string(before), to_string(after_str))
  end

  @spec map(term(), binary()) :: binary()
  def map(fun, text) when is_binary(text) do
    text |> String.graphemes() |> Enum.map(&Core.apply1(fun, &1)) |> Enum.join()
  end

  @spec filter(term(), binary()) :: binary()
  def filter(fun, text) when is_binary(text) do
    text |> String.graphemes() |> Enum.filter(&Core.apply1(fun, &1)) |> Enum.join()
  end

  @spec foldl(term(), term(), binary()) :: term()
  def foldl(fun, acc, text) when is_binary(text) do
    Enum.reduce(String.graphemes(text), acc, fn ch, acc0 -> Core.apply2(fun, ch, acc0) end)
  end

  @spec foldr(term(), term(), binary()) :: term()
  def foldr(fun, acc, text) when is_binary(text) do
    Enum.reduce(Enum.reverse(String.graphemes(text)), acc, fn ch, acc0 ->
      Core.apply2(fun, ch, acc0)
    end)
  end

  @spec any(term(), binary()) :: boolean()
  def any(fun, text) when is_binary(text),
    do: Enum.any?(String.graphemes(text), &Core.apply1(fun, &1))

  @spec all(term(), binary()) :: boolean()
  def all(fun, text) when is_binary(text),
    do: Enum.all?(String.graphemes(text), &Core.apply1(fun, &1))

  @spec lines(binary()) :: list()
  def lines(text) when is_binary(text), do: String.split(text, "\n")

  @spec words(binary()) :: list()
  def words(text) when is_binary(text), do: String.split(text, ~r/\s+/, trim: true)

  @spec indexes(term(), binary()) :: list()
  def indexes(substr, text) when is_binary(text) do
    needle = to_string(substr)

    if needle == "" do
      []
    else
      text
      |> :binary.matches(needle)
      |> Enum.map(fn {pos, _len} -> pos end)
    end
  end

  @spec pad(term(), term(), binary()) :: binary()
  def pad(n, ch, text), do: pad_left(n, ch, text)

  @spec pad_left(term(), term(), binary()) :: binary()
  def pad_left(n, ch, text) when is_binary(text) do
    count = max(to_int(n, 0) - String.length(text), 0)
    String.duplicate(to_string(ch), count) <> text
  end

  @spec pad_right(term(), term(), binary()) :: binary()
  def pad_right(n, ch, text) when is_binary(text) do
    count = max(to_int(n, 0) - String.length(text), 0)
    text <> String.duplicate(to_string(ch), count)
  end

  defp to_int(n, _default) when is_integer(n), do: n
  defp to_int(n, _default) when is_float(n), do: trunc(n)
  defp to_int(_other, default), do: default
end
