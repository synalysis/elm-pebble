defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.String do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.String, as: StringValue

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("append", [a, b], _ops) when is_binary(a) and is_binary(b), do: {:ok, a <> b}
  def eval("isEmpty", [text], _ops) when is_binary(text), do: {:ok, text == ""}
  def eval("isempty", [text], _ops) when is_binary(text), do: {:ok, text == ""}
  def eval("length", [text], _ops) when is_binary(text), do: {:ok, String.length(text)}

  def eval("reverse", [text], _ops) when is_binary(text),
    do: {:ok, text |> String.graphemes() |> Enum.reverse() |> Enum.join()}

  def eval("repeat", [n, text], _ops) when is_integer(n) and n >= 0 and is_binary(text),
    do: {:ok, String.duplicate(text, n)}

  def eval("replace", [before, replacement, text], _ops)
      when is_binary(before) and is_binary(replacement) and is_binary(text),
      do: {:ok, String.replace(text, before, replacement)}

  def eval("split", [sep, text], _ops) when is_binary(sep) and is_binary(text),
    do: {:ok, String.split(text, sep)}

  def eval("join", [sep, parts], _ops) when is_binary(sep) and is_list(parts),
    do: {:ok, Enum.map(parts, &to_string/1) |> Enum.join(sep)}

  def eval("words", [text], _ops) when is_binary(text),
    do: {:ok, String.split(text, ~r/\s+/, trim: true)}

  def eval("lines", [text], _ops) when is_binary(text),
    do: {:ok, String.split(text, ~r/\r\n|\r|\n/, trim: false)}

  def eval("slice", [start, stop, text], _ops)
      when is_integer(start) and is_integer(stop) and is_binary(text),
      do: {:ok, StringValue.string_slice(text, start, stop)}

  def eval("left", [n, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_left(text, n)}

  def eval("right", [n, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_right(text, n)}

  def eval("dropleft", [n, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_drop_left(text, n)}

  def eval("dropright", [n, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_drop_right(text, n)}

  def eval("contains", [needle, haystack], _ops) when is_binary(needle) and is_binary(haystack),
    do: {:ok, String.contains?(haystack, needle)}

  def eval("startswith", [prefix, text], _ops) when is_binary(prefix) and is_binary(text),
    do: {:ok, String.starts_with?(text, prefix)}

  def eval("endswith", [suffix, text], _ops) when is_binary(suffix) and is_binary(text),
    do: {:ok, String.ends_with?(text, suffix)}

  def eval("indexes", [needle, haystack], _ops) when is_binary(needle) and is_binary(haystack),
    do: {:ok, StringValue.string_indexes(needle, haystack)}

  def eval("indices", [needle, haystack], _ops) when is_binary(needle) and is_binary(haystack),
    do: {:ok, StringValue.string_indexes(needle, haystack)}

  def eval("toint", [text], _ops) when is_binary(text),
    do: {:ok, StringValue.maybe_int_from_string(text)}

  def eval("tofloat", [text], _ops) when is_binary(text),
    do: {:ok, StringValue.maybe_float_from_string(text)}

  def eval("fromint", [value], _ops) when is_integer(value), do: {:ok, Integer.to_string(value)}

  def eval("fromfloat", [value], _ops) when is_number(value),
    do: {:ok, StringValue.float_to_elm_string(value)}

  def eval("fromchar", [char], _ops), do: {:ok, StringValue.normalize_char_binary(char)}
  def eval("toList", [text], _ops) when is_binary(text), do: {:ok, String.graphemes(text)}
  def eval("tolist", [text], _ops) when is_binary(text), do: {:ok, String.graphemes(text)}

  def eval("fromList", [chars], _ops) when is_list(chars),
    do: {:ok, chars |> Enum.map(&StringValue.normalize_char_binary/1) |> Enum.join()}

  def eval("fromlist", [chars], _ops) when is_list(chars),
    do: {:ok, chars |> Enum.map(&StringValue.normalize_char_binary/1) |> Enum.join()}

  def eval("toUpper", [text], _ops) when is_binary(text), do: {:ok, String.upcase(text)}
  def eval("toupper", [text], _ops) when is_binary(text), do: {:ok, String.upcase(text)}
  def eval("toLower", [text], _ops) when is_binary(text), do: {:ok, String.downcase(text)}
  def eval("tolower", [text], _ops) when is_binary(text), do: {:ok, String.downcase(text)}

  def eval("pad", [n, fill, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_pad_center(text, n, fill)}

  def eval("padLeft", [n, fill, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_pad_left(text, n, fill)}

  def eval("padleft", [n, fill, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_pad_left(text, n, fill)}

  def eval("padRight", [n, fill, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_pad_right(text, n, fill)}

  def eval("padright", [n, fill, text], _ops) when is_integer(n) and is_binary(text),
    do: {:ok, StringValue.string_pad_right(text, n, fill)}

  def eval("trim", [text], _ops) when is_binary(text), do: {:ok, String.trim(text)}
  def eval("trimLeft", [text], _ops) when is_binary(text), do: {:ok, String.trim_leading(text)}
  def eval("trimleft", [text], _ops) when is_binary(text), do: {:ok, String.trim_leading(text)}
  def eval("trimRight", [text], _ops) when is_binary(text), do: {:ok, String.trim_trailing(text)}
  def eval("trimright", [text], _ops) when is_binary(text), do: {:ok, String.trim_trailing(text)}

  def eval("uncons", [text], _ops) when is_binary(text),
    do: {:ok, StringValue.string_uncons_ctor(text)}

  def eval("map", [fun, text], ops) when is_binary(text), do: ops.string_map.(fun, text)
  def eval("filter", [fun, text], ops) when is_binary(text), do: ops.string_filter.(fun, text)

  def eval("foldl", [fun, init, text], ops) when is_binary(text),
    do: ops.string_foldl.(fun, init, text)

  def eval("foldr", [fun, init, text], ops) when is_binary(text),
    do: ops.string_foldr.(fun, init, text)

  def eval("any", [fun, text], ops) when is_binary(text), do: ops.string_any.(fun, text)
  def eval("all", [fun, text], ops) when is_binary(text), do: ops.string_all.(fun, text)
  def eval(_function_name, _values, _ops), do: :no_builtin
end
