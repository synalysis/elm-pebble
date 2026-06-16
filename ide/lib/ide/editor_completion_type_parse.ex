defmodule Ide.EditorCompletionTypeParse do
  @moduledoc false

  @spec record_field_specs(String.t()) :: [%{name: String.t(), type: String.t()}]
  def record_field_specs(source) when is_binary(source) do
    trimmed = String.trim(source)

    with {:ok, inner} <- record_type_body(trimmed) do
      inner
      |> strip_extensible_record_base()
      |> split_top_level(",", [])
      |> Enum.flat_map(&record_field_spec/1)
    else
      _ -> []
    end
  end

  def record_field_specs(_), do: []

  @spec function_param_types(String.t()) :: [String.t()]
  def function_param_types(type) when is_binary(type) do
    type
    |> String.trim()
    |> split_function_type_parts()
    |> case do
      [_only] -> []
      parts -> parts |> Enum.drop(-1) |> Enum.map(&String.trim/1)
    end
  end

  def function_param_types(_), do: []

  defp split_function_type_parts(type) do
    do_split_function_type_parts(type, "", 0, nil, [])
  end

  defp do_split_function_type_parts(<<>>, current, _depth, _quote, acc) do
    Enum.reverse([String.trim(current) | acc])
  end

  defp do_split_function_type_parts(<<char::utf8, rest::binary>>, current, depth, quote, acc) do
    char_text = <<char::utf8>>

    cond do
      quote == nil and depth == 0 and char_text == "-" and String.starts_with?(rest, ">") ->
        do_split_function_type_parts(
          rest |> String.trim_leading(">") |> String.trim_leading(),
          "",
          depth,
          quote,
          [String.trim(current) | acc]
        )

      quote == nil and char_text in ["\"", "'"] ->
        do_split_function_type_parts(rest, current <> char_text, depth, char_text, acc)

      quote == char_text ->
        do_split_function_type_parts(rest, current <> char_text, depth, nil, acc)

      quote == nil and char_text in ["(", "[", "{"] ->
        do_split_function_type_parts(rest, current <> char_text, depth + 1, quote, acc)

      quote == nil and char_text in [")", "]", "}"] ->
        do_split_function_type_parts(rest, current <> char_text, max(depth - 1, 0), quote, acc)

      true ->
        do_split_function_type_parts(rest, current <> char_text, depth, quote, acc)
    end
  end

  defp record_type_body(source) do
    trimmed = String.trim(source)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      {:ok, trimmed |> String.slice(1, String.length(trimmed) - 2) |> String.trim()}
    else
      :error
    end
  end

  defp strip_extensible_record_base(source) do
    case split_top_level(source, "|", []) do
      [_base, fields] -> String.trim(fields)
      _ -> source
    end
  end

  defp record_field_spec(source) do
    case split_top_level(source, ":", []) do
      [name, type] ->
        name = String.trim(name)
        type = String.trim(type)

        if valid_record_field_name?(name) and type != "" do
          [%{name: name, type: type}]
        else
          []
        end

      _ ->
        []
    end
  end

  defp valid_record_field_name?(<<first::utf8, rest::binary>>) when first in ?a..?z do
    String.printable?(rest)
  end

  defp valid_record_field_name?(_), do: false

  defp split_top_level(source, separator, acc)
       when is_binary(source) and is_binary(separator) and byte_size(separator) == 1 do
    do_split_top_level(source, separator, acc, "", 0, nil)
  end

  defp do_split_top_level(<<>>, _separator, acc, current, _depth, _quote) do
    Enum.reverse([String.trim(current) | acc])
  end

  defp do_split_top_level(<<char::utf8, rest::binary>>, separator, acc, current, depth, quote) do
    char_text = <<char::utf8>>

    cond do
      quote == nil and char_text == separator and depth == 0 ->
        do_split_top_level(rest, separator, [String.trim(current) | acc], "", depth, quote)

      quote == nil and char_text in ["\"", "'"] ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, char_text)

      quote == char_text ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, nil)

      quote == nil and char_text in ["(", "[", "{"] ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth + 1, quote)

      quote == nil and char_text in [")", "]", "}"] ->
        do_split_top_level(rest, separator, acc, current <> char_text, max(depth - 1, 0), quote)

      true ->
        do_split_top_level(rest, separator, acc, current <> char_text, depth, quote)
    end
  end
end
