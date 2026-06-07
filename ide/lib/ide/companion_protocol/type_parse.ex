defmodule Ide.CompanionProtocol.TypeParse do
  @moduledoc false

  @type constructor :: %{name: String.t(), args: [String.t()]}
  @type alias_field :: %{name: String.t(), type: String.t()}

  @spec parse_unions(String.t()) :: %{optional(String.t()) => [constructor()]}
  def parse_unions(source) when is_binary(source) do
    ~r/(?:^|\n)type\s+([A-Z][A-Za-z0-9_]*)\s*\n((?:\s{4}=\s+[A-Z][^\n]*(?:\n\s{4}\|\s+[A-Z][^\n]*)*|\s+=\s+[A-Z][^\n]*(?:\n\s+\|\s+[A-Z][^\n]*)*))/m
    |> Regex.scan(source)
    |> Map.new(fn [_all, name, body] ->
      constructors =
        body
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.trim_leading(&1, "="))
        |> Enum.map(&String.trim_leading(&1, "|"))
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&parse_constructor_line/1)

      {name, constructors}
    end)
  end

  @spec parse_type_aliases(String.t()) :: %{optional(String.t()) => [alias_field()]}
  def parse_type_aliases(source) when is_binary(source) do
    ~r/(?:^|\n)type\s+alias\s+([A-Z][A-Za-z0-9_]*)\s*=\s*\{([^}]*)\}/m
    |> Regex.scan(source)
    |> Map.new(fn [_all, name, body] ->
      fields =
        body
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn field ->
          case String.split(field, ":", parts: 2) do
            [field_name, type] ->
              %{name: String.trim(field_name), type: normalize_type(type)}

            _ ->
              %{name: field, type: "Int"}
          end
        end)

      {name, fields}
    end)
  end

  @spec normalize_constructor_args([String.t()]) :: [String.t()]
  def normalize_constructor_args(raw_args) when is_list(raw_args) do
    raw_args
    |> Enum.join(" ")
    |> split_type_args()
    |> Enum.map(&normalize_type/1)
  end

  @spec normalize_type(String.t()) :: String.t()
  def normalize_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> strip_wrapping_parens()
    |> String.replace(~r/\s+/, " ")
    |> normalize_container_type()
  end

  defp parse_constructor_line(line) do
    [ctor | raw_args] = String.split(line, ~r/\s+/, trim: true)
    %{name: ctor, args: normalize_constructor_args(raw_args)}
  end

  defp split_type_args(source) do
    source
    |> String.trim()
    |> do_split_type_args([], "", 0)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_type_args("", acc, current, _depth) do
    current = String.trim(current)
    if current == "", do: acc, else: [current | acc]
  end

  defp do_split_type_args(<<"(", rest::binary>>, acc, current, depth),
    do: do_split_type_args(rest, acc, current <> "(", depth + 1)

  defp do_split_type_args(<<")", rest::binary>>, acc, current, depth),
    do: do_split_type_args(rest, acc, current <> ")", max(depth - 1, 0))

  defp do_split_type_args(<<" ", rest::binary>>, acc, current, 0) do
    current = String.trim(current)

    if current == "" do
      do_split_type_args(rest, acc, "", 0)
    else
      do_split_type_args(rest, [current | acc], "", 0)
    end
  end

  defp do_split_type_args(<<char::binary-size(1), rest::binary>>, acc, current, depth),
    do: do_split_type_args(rest, acc, current <> char, depth)

  defp strip_wrapping_parens(type) do
    trimmed = String.trim(type)

    if String.starts_with?(trimmed, "(") and String.ends_with?(trimmed, ")") do
      inner = String.slice(trimmed, 1, byte_size(trimmed) - 2)

      if balanced_parens?(inner), do: strip_wrapping_parens(inner), else: trimmed
    else
      trimmed
    end
  end

  defp balanced_parens?(source) do
    source
    |> String.graphemes()
    |> Enum.reduce_while(0, fn
      "(", depth -> {:cont, depth + 1}
      ")", 0 -> {:halt, :error}
      ")", depth -> {:cont, depth - 1}
      _char, depth -> {:cont, depth}
    end)
    |> Kernel.==(0)
  end

  defp normalize_container_type("List " <> rest), do: "List " <> normalize_type(rest)

  defp normalize_container_type("Dict String " <> rest),
    do: "Dict String " <> normalize_type(rest)

  defp normalize_container_type(type), do: type
end
