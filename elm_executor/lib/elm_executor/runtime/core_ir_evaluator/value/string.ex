defmodule ElmExecutor.Runtime.CoreIREvaluator.Value.String do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult

  @spec char_from_code(term()) :: String.t()
  def char_from_code(value) when is_integer(value) and value >= 0 and value <= 0x10FFFF do
    if value in 0xD800..0xDFFF do
      <<0xFFFD::utf8>>
    else
      try do
        <<value::utf8>>
      rescue
        _ -> <<0xFFFD::utf8>>
      end
    end
  end

  def char_from_code(_), do: <<0xFFFD::utf8>>

  @spec normalize_char_binary(term()) :: String.t()
  def normalize_char_binary(char) when is_binary(char) do
    case String.graphemes(char) do
      [g | _] -> g
      [] -> ""
    end
  end

  def normalize_char_binary(char) when is_integer(char), do: char_from_code(char)
  def normalize_char_binary(_), do: ""

  @spec char_to_code(term()) :: non_neg_integer()
  def char_to_code(char) do
    char
    |> normalize_char_binary()
    |> String.to_charlist()
    |> case do
      [cp] -> cp
      _ -> 0
    end
  end

  @spec char_predicate(term(), term()) :: term()
  def char_predicate(char, fun) when is_function(fun, 1) do
    char
    |> normalize_char()
    |> case do
      nil -> false
      cp -> fun.(cp)
    end
  end

  @spec char_alpha?(term()) :: boolean()
  def char_alpha?(cp), do: (cp >= ?A and cp <= ?Z) or (cp >= ?a and cp <= ?z)

  @spec char_digit?(term()) :: boolean()
  def char_digit?(cp), do: cp >= ?0 and cp <= ?9

  @spec char_alphanum?(term()) :: boolean()
  def char_alphanum?(cp), do: char_alpha?(cp) or char_digit?(cp)

  @spec char_lower?(term()) :: boolean()
  def char_lower?(cp), do: cp >= ?a and cp <= ?z

  @spec char_octal_digit?(term()) :: boolean()
  def char_octal_digit?(cp), do: cp >= ?0 and cp <= ?7

  @spec char_upper?(term()) :: boolean()
  def char_upper?(cp), do: cp >= ?A and cp <= ?Z

  @spec string_left(term(), term()) :: String.t()
  def string_left(text, n) when is_binary(text) and is_integer(n) do
    text |> String.graphemes() |> Enum.take(max(n, 0)) |> Enum.join()
  end

  @spec string_right(term(), term()) :: String.t()
  def string_right(text, n) when is_binary(text) and is_integer(n) do
    graphemes = String.graphemes(text)
    graphemes |> Enum.drop(max(length(graphemes) - max(n, 0), 0)) |> Enum.join()
  end

  @spec string_drop_left(term(), term()) :: String.t()
  def string_drop_left(text, n) when is_binary(text) and is_integer(n) do
    text |> String.graphemes() |> Enum.drop(max(n, 0)) |> Enum.join()
  end

  @spec string_drop_right(term(), term()) :: String.t()
  def string_drop_right(text, n) when is_binary(text) and is_integer(n) do
    graphemes = String.graphemes(text)
    graphemes |> Enum.take(max(length(graphemes) - max(n, 0), 0)) |> Enum.join()
  end

  @spec string_pad_center(term(), term(), term()) :: String.t()
  def string_pad_center(text, width, fill) do
    text_len = String.length(text)
    total = max(width - text_len, 0)
    left = div(total, 2)
    string_pad_left(text, text_len + left, fill) |> string_pad_right(width, fill)
  end

  @spec string_pad_left(term(), term(), term()) :: String.t()
  def string_pad_left(text, width, fill) do
    ch = normalize_char_binary(fill)
    missing = max(width - String.length(text), 0)
    String.duplicate(ch, missing) <> text
  end

  @spec string_pad_right(term(), term(), term()) :: String.t()
  def string_pad_right(text, width, fill) do
    ch = normalize_char_binary(fill)
    missing = max(width - String.length(text), 0)
    text <> String.duplicate(ch, missing)
  end

  @spec string_slice(term(), term(), term()) :: String.t()
  def string_slice(text, start, stop)
      when is_binary(text) and is_integer(start) and is_integer(stop) do
    graphemes = String.graphemes(text)
    len = length(graphemes)
    from = normalize_slice_index(start, len)
    to = normalize_slice_index(stop, len)
    graphemes |> Enum.drop(from) |> Enum.take(max(to - from, 0)) |> Enum.join()
  end

  @spec string_indexes(term(), term()) :: [non_neg_integer()]
  def string_indexes("", _), do: []

  def string_indexes(needle, haystack) when is_binary(needle) and is_binary(haystack) do
    n = String.length(needle)
    h = String.graphemes(haystack)
    max_start = length(h) - n

    if n <= 0 or max_start < 0 do
      []
    else
      0..max_start
      |> Enum.filter(fn idx ->
        h |> Enum.drop(idx) |> Enum.take(n) |> Enum.join() == needle
      end)
      |> Enum.to_list()
    end
  end

  @spec string_uncons_ctor(term()) :: map()
  def string_uncons_ctor(text) when is_binary(text) do
    case String.graphemes(text) do
      [head | tail] -> MaybeResult.maybe_ctor({:just, {head, Enum.join(tail)}})
      [] -> MaybeResult.maybe_ctor(:nothing)
    end
  end

  @spec maybe_int_from_string(term()) :: map()
  def maybe_int_from_string(text) when is_binary(text) do
    case Integer.parse(text) do
      {value, ""} -> MaybeResult.maybe_ctor({:just, value})
      _ -> MaybeResult.maybe_ctor(:nothing)
    end
  end

  @spec maybe_float_from_string(term()) :: map()
  def maybe_float_from_string(text) when is_binary(text) do
    case Float.parse(text) do
      {value, ""} -> MaybeResult.maybe_ctor({:just, value})
      _ -> MaybeResult.maybe_ctor(:nothing)
    end
  end

  @spec float_to_elm_string(term()) :: String.t()
  def float_to_elm_string(value) when is_integer(value), do: Integer.to_string(value)

  def float_to_elm_string(value) when is_float(value) do
    if value == trunc(value) do
      Integer.to_string(trunc(value))
    else
      :erlang.float_to_binary(value, [:compact, decimals: 15])
    end
  end

  @spec normalize_char(term()) :: integer() | nil
  defp normalize_char(char) when is_binary(char) do
    case String.to_charlist(char) do
      [cp] -> cp
      _ -> nil
    end
  end

  defp normalize_char(_), do: nil

  @spec normalize_slice_index(term(), term()) :: non_neg_integer()
  defp normalize_slice_index(index, len) when is_integer(index) and is_integer(len) do
    normalized = if index < 0, do: len + index, else: index
    normalized |> max(0) |> min(len)
  end
end
