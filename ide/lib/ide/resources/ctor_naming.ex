defmodule Ide.Resources.CtorNaming do
  @moduledoc """
  Generated Elm resource constructor names: fixed kind prefix + editable base name.

  Examples: `BitmapStaticHourHand`, `BitmapAnimatedSparkle`, `VectorStaticBird`.
  """

  @prefixes %{
    bitmap_static: "BitmapStatic",
    bitmap_animated: "BitmapAnimated",
    vector_static: "VectorStatic",
    vector_animated: "VectorAnimated"
  }

  @type kind :: :bitmap_static | :bitmap_animated | :vector_static | :vector_animated

  @spec prefixes() :: %{kind() => String.t()}
  def prefixes, do: @prefixes

  @spec prefix(kind()) :: String.t()
  def prefix(kind) when is_map_key(@prefixes, kind), do: Map.fetch!(@prefixes, kind)

  @spec ctor(kind(), String.t()) :: String.t()
  def ctor(kind, base_name) when is_map_key(@prefixes, kind) and is_binary(base_name) do
    prefix(kind) <> normalize_base_name(base_name)
  end

  @spec normalize_base_name(String.t()) :: String.t()
  def normalize_base_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" ->
        "Resource"

      pascal_case_identifier?(trimmed) ->
        trimmed

      true ->
        trimmed
        |> String.split(~r/[^A-Za-z0-9]+/, trim: true)
        |> Enum.map(&capitalize_segment/1)
        |> Enum.join()
        |> case do
          "" -> "Resource"
          value -> value
        end
    end
  end

  @spec pascal_case_identifier?(String.t()) :: boolean()
  defp pascal_case_identifier?(name) when is_binary(name) do
    name != "" and
      String.match?(name, ~r/^[A-Z][A-Za-z0-9]*$/) and
      not String.match?(name, ~r/[^A-Za-z0-9]/)
  end

  @spec base_name_from_filename(String.t()) :: String.t()
  def base_name_from_filename(filename) when is_binary(filename) do
    filename
    |> Path.basename()
    |> Path.rootname()
    |> normalize_base_name()
  end

  @spec resolve_base_name(map(), kind()) :: String.t()
  def resolve_base_name(row, kind) when is_map(row) and is_map_key(@prefixes, kind) do
    case Map.get(row, "base_name") || Map.get(row, :base_name) do
      base when is_binary(base) and base != "" ->
        normalize_base_name(base)

      _ ->
        legacy_base_from_ctor(Map.get(row, "ctor") || Map.get(row, :ctor) || "", kind)
    end
  end

  @spec ensure_row!(map(), kind()) :: map()
  def ensure_row!(row, kind) when is_map(row) and is_map_key(@prefixes, kind) do
    base = resolve_base_name(row, kind)
    ctor = ctor(kind, base)

    row
    |> Map.put("base_name", base)
    |> Map.put("ctor", ctor)
  end

  @spec unique_ctor(kind(), String.t(), [map()], keyword()) :: String.t()
  def unique_ctor(kind, base_name, entries, opts \\ []) when is_list(entries) do
    exclude = Keyword.get(opts, :exclude_ctor)

    used =
      entries
      |> Enum.reject(fn row ->
        exclude != nil and Map.get(row, "ctor") == exclude
      end)
      |> Enum.map(&Map.get(&1, "ctor", ""))
      |> MapSet.new()

    base = normalize_base_name(base_name)
    pick_unique(kind, base, used, 0)
  end

  @spec legacy_base_from_ctor(String.t(), kind()) :: String.t()
  def legacy_base_from_ctor(ctor, kind) when is_binary(ctor) and is_map_key(@prefixes, kind) do
    p = prefix(kind)

    cond do
      ctor != "" and String.starts_with?(ctor, p) ->
        String.replace_prefix(ctor, p, "")

      kind == :bitmap_animated and String.starts_with?(ctor, "Anim") ->
        String.replace_prefix(ctor, "Anim", "")

      ctor != "" ->
        ctor
        |> String.split(~r/[^A-Za-z0-9]+/, trim: true)
        |> Enum.map(&capitalize_segment/1)
        |> Enum.join()

      true ->
        "Resource"
    end
    |> normalize_base_name()
  end

  @spec vector_kind_from_row(map()) :: kind()
  def vector_kind_from_row(row) when is_map(row) do
    case Map.get(row, "kind") || Map.get(row, :kind) do
      "sequence" -> :vector_animated
      _ -> :vector_static
    end
  end

  defp pick_unique(kind, base, used, suffix) do
    candidate_base =
      if suffix == 0 do
        base
      else
        base <> Integer.to_string(suffix)
      end

    candidate = ctor(kind, candidate_base)

    if MapSet.member?(used, candidate) do
      pick_unique(kind, base, used, suffix + 1)
    else
      candidate
    end
  end

  defp capitalize_segment(<<first::utf8, rest::binary>>) do
    String.upcase(<<first::utf8>>) <> rest
  end

  defp capitalize_segment(""), do: ""
end
