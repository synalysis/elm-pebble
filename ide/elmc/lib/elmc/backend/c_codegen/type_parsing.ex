defmodule Elmc.Backend.CCodegen.TypeParsing do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  @cache_key :elmc_type_parsing_arrow_cache

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

  @spec set_type?(String.t()) :: boolean()
  def set_type?(type) when is_binary(type) do
    type = normalize_type_name(type)

    String.starts_with?(type, "Set ") or
      String.starts_with?(type, "Set.") or
      type == "Set"
  end

  def set_type?(_type), do: false

  @spec enum_type?(String.t()) :: boolean()
  def enum_type?(type) when is_binary(type) do
    Process.get(:elmc_enum_types, MapSet.new())
    |> MapSet.member?(normalize_type_name(type))
  end

  def enum_type?(_type), do: false

  @doc """
  Split a type string on top-level `->` (outside parentheses / brackets / braces).

  Results are memoized in the process dictionary for the current compile.
  """
  @spec split_top_level_arrows(String.t()) :: [String.t()]
  def split_top_level_arrows(type) when is_binary(type) do
    cache = Process.get(@cache_key, %{})

    case Map.fetch(cache, type) do
      {:ok, parts} ->
        parts

      :error ->
        parts = do_split_top_level_arrows(type)
        Process.put(@cache_key, Map.put(cache, type, parts))
        parts
    end
  end

  @spec do_split_top_level_arrows(String.t()) :: Types.ir_expr()

  defp do_split_top_level_arrows(type) when is_binary(type) do
    type
    |> split_top_level_arrows_bin(0, byte_size(type), 0, 0, [])
    |> Enum.map(&String.trim/1)
  end

  # Walk the binary once; emit slices without grapheme lists or O(n²) concat.
  @spec split_top_level_arrows_bin(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), non_neg_integer() | Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp split_top_level_arrows_bin(type, pos, size, _depth, start, parts) when pos >= size do
    Enum.reverse([binary_part(type, start, size - start) | parts])
  end

  defp split_top_level_arrows_bin(type, pos, size, 0, start, parts) when pos + 1 < size do
    case type do
      <<_::binary-size(^pos), ?-, ?>, _::binary>> ->
        part = binary_part(type, start, pos - start)
        split_top_level_arrows_bin(type, pos + 2, size, 0, pos + 2, [part | parts])

      _ ->
        split_top_level_arrows_bin_step(type, pos, size, 0, start, parts)
    end
  end

  defp split_top_level_arrows_bin(type, pos, size, depth, start, parts) do
    split_top_level_arrows_bin_step(type, pos, size, depth, start, parts)
  end

  @spec split_top_level_arrows_bin_step(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), non_neg_integer(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp split_top_level_arrows_bin_step(type, pos, size, depth, start, parts) do
    next_depth =
      case :binary.at(type, pos) do
        ?( -> depth + 1
        ?{ -> depth + 1
        ?[ -> depth + 1
        ?) -> max(depth - 1, 0)
        ?} -> max(depth - 1, 0)
        ?] -> max(depth - 1, 0)
        _ -> depth
      end

    split_top_level_arrows_bin(type, pos + 1, size, next_depth, start, parts)
  end

  @spec strip_wrapping_parens(String.t()) :: String.t()
  defp strip_wrapping_parens("(" <> rest = type) do
    if String.ends_with?(type, ")") do
      # Keep real tuples `(A, B)`. Unwrap `(Int)`, `(a -> b)`, and
      # `(Metadata -> a -> b)` — `tuple_type?/1` only checks outer parens, so it
      # must not block stripping parenthesized function types.
      if multi_element_tuple_type?(type) do
        String.trim(type)
      else
        rest
        |> String.slice(0, String.length(rest) - 1)
        |> normalize_type_name()
      end
    else
      type
    end
  end

  defp strip_wrapping_parens(type), do: type

  @spec multi_element_tuple_type?(String.t()) :: boolean()

  defp multi_element_tuple_type?(type) when is_binary(type) do
    case ElmEx.IR.TypeSignature.tuple_element_types(type) do
      [_first, _second | _] -> true
      _ -> false
    end
  end
end
