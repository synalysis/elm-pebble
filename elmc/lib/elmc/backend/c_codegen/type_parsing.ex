defmodule Elmc.Backend.CCodegen.TypeParsing do
  @moduledoc false

  @spec function_arg_types(String.t()) :: [String.t()]
  def function_arg_types(type) when is_binary(type) do
    type
    |> split_top_level_arrows()
    |> Enum.drop(-1)
  end

  def function_arg_types(_type), do: []

  @spec function_return_type(String.t()) :: String.t()
  def function_return_type(type) when is_binary(type) do
    type
    |> split_top_level_arrows()
    |> List.last()
    |> normalize_type_name()
  end

  def function_return_type(_type), do: ""

  @spec normalize_type_name(String.t()) :: String.t()
  def normalize_type_name(type) when is_binary(type) do
    type
    |> String.trim()
    |> strip_wrapping_parens()
  end

  def normalize_type_name(_type), do: ""

  @spec enum_type?(String.t()) :: boolean()
  def enum_type?(type) when is_binary(type) do
    Process.get(:elmc_enum_types, MapSet.new())
    |> MapSet.member?(normalize_type_name(type))
  end

  def enum_type?(_type), do: false

  @spec split_top_level_arrows(String.t()) :: [String.t()]
  def split_top_level_arrows(type) when is_binary(type) do
    type
    |> String.graphemes()
    |> split_top_level_arrows([], "", 0)
    |> Enum.map(&String.trim/1)
  end

  defp split_top_level_arrows(["-" | [">" | rest]], parts, current, 0) do
    split_top_level_arrows(rest, [current | parts], "", 0)
  end

  defp split_top_level_arrows([char | rest], parts, current, depth) do
    next_depth =
      case char do
        "(" -> depth + 1
        "{" -> depth + 1
        "[" -> depth + 1
        ")" -> max(depth - 1, 0)
        "}" -> max(depth - 1, 0)
        "]" -> max(depth - 1, 0)
        _other -> depth
      end

    split_top_level_arrows(rest, parts, current <> char, next_depth)
  end

  defp split_top_level_arrows([], parts, current, _depth), do: Enum.reverse([current | parts])

  defp strip_wrapping_parens("(" <> rest = type) do
    if String.ends_with?(type, ")") do
      rest
      |> String.slice(0, String.length(rest) - 1)
      |> normalize_type_name()
    else
      type
    end
  end

  defp strip_wrapping_parens(type), do: type
end
