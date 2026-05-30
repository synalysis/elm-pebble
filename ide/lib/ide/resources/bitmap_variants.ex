defmodule Ide.Resources.BitmapVariants do
  @moduledoc """
  Monochrome and color bitmap variants for Pebble platform-specific resources.

  Variant files use Pebble SDK tilde tags (`Charmander~bw.png`, `Charmander~color.png`).
  `package.json` references the untagged base path (`bitmaps/Charmander.png`); the SDK
  selects the matching tagged file per platform at build time.
  """

  alias Ide.WatchModels

  @color_modes ~w(BlackWhite Color)

  @pebble_tags %{
    "BlackWhite" => "bw",
    "Color" => "color"
  }

  @doc false
  def color_modes, do: @color_modes

  @doc false
  def valid_color_mode?(mode) when is_binary(mode), do: mode in @color_modes

  @doc false
  def pebble_tag(color_mode) when is_binary(color_mode) do
    Map.fetch!(@pebble_tags, color_mode)
  end

  @doc """
  Filename for a stored variant, e.g. `Charmander~bw.png`.
  """
  @spec variant_filename(String.t(), String.t(), String.t()) :: String.t()
  def variant_filename(ctor, color_mode, ext) when is_binary(ctor) and is_binary(ext) do
    "#{ctor}~#{pebble_tag(color_mode)}#{ext}"
  end

  @doc """
  Legacy single-file name used on all platforms when no variants exist.
  """
  @spec legacy_filename(String.t(), String.t()) :: String.t()
  def legacy_filename(ctor, ext) when is_binary(ctor), do: "#{ctor}#{ext}"

  @doc """
  Relative package media path (under `resources/`) passed to Pebble `package.json`.
  """
  @spec package_media_file(String.t()) :: String.t()
  def package_media_file(ctor) when is_binary(ctor), do: "bitmaps/#{ctor}.png"

  @doc """
  Human-readable platform list for a color mode (for UI labels).
  """
  @spec platforms_label(String.t()) :: String.t()
  def platforms_label(color_mode) when is_binary(color_mode) do
    WatchModels.ordered_ids()
    |> Enum.filter(&(Map.get(WatchModels.profile_for(&1), "color_mode") == color_mode))
    |> Enum.map(&(Map.get(WatchModels.profile_for(&1), "name", &1)))
    |> Enum.join(", ")
  end

  @doc """
  All asset filenames referenced by a manifest row (variants + legacy).
  """
  @spec filenames_for_row(map()) :: [String.t()]
  def filenames_for_row(row) when is_map(row) do
    legacy =
      case Map.get(row, "filename") do
        filename when is_binary(filename) and filename != "" -> [filename]
        _ -> []
      end

    variants =
      row
      |> Map.get("variants", %{})
      |> variant_filenames_from_map()

    Enum.uniq(legacy ++ variants)
  end

  @doc """
  Normalizes a manifest row to schema version 2 shape with a `variants` map.
  """
  @spec normalize_row(map()) :: map()
  def normalize_row(row) when is_map(row) do
    ctor = to_string(Map.get(row, "ctor", ""))

    variants =
      case Map.get(row, "variants") do
        %{} = variants ->
          variants
          |> Enum.filter(fn {_mode, variant} -> is_map(variant) end)
          |> Map.new(fn {mode, variant} ->
            {to_string(mode), normalize_variant_row(variant)}
          end)

        _ ->
          %{}
      end

    legacy_filename = Map.get(row, "filename")

    row
    |> Map.put("schema_version", 2)
    |> Map.put("ctor", ctor)
    |> Map.put("id", to_string(Map.get(row, "id", "bitmap_" <> String.downcase(ctor))))
    |> Map.put("variants", variants)
    |> then(fn normalized ->
      if is_binary(legacy_filename) and legacy_filename != "" do
        Map.put(normalized, "filename", legacy_filename)
      else
        Map.drop(normalized, ["filename"])
      end
    end)
  end

  @doc """
  Picks preview dimensions: color variant, then monochrome, then legacy fields.
  """
  @spec primary_dimensions(map()) :: {non_neg_integer(), non_neg_integer()}
  def primary_dimensions(row) when is_map(row) do
    row = normalize_row(row)

    cond do
      variant_dims = variant_dimensions(row, "Color") ->
        variant_dims

      variant_dims = variant_dimensions(row, "BlackWhite") ->
        variant_dims

      true ->
        {integer_or_zero(Map.get(row, "width", 0)), integer_or_zero(Map.get(row, "height", 0))}
    end
  end

  @doc false
  def has_variants?(row) when is_map(row) do
    row |> normalize_row() |> Map.get("variants", %{}) |> map_size() > 0
  end

  @doc false
  def variant_row(row, color_mode) when is_map(row) do
    row
    |> normalize_row()
    |> Map.get("variants", %{})
    |> Map.get(color_mode)
  end

  defp variant_filenames_from_map(variants) when is_map(variants) do
    variants
    |> Enum.flat_map(fn
      {_mode, %{"filename" => filename}} when is_binary(filename) and filename != "" ->
        [filename]

      _ ->
        []
    end)
  end

  defp normalize_variant_row(variant) when is_map(variant) do
    %{
      "filename" => to_string(Map.get(variant, "filename", "")),
      "mime" => to_string(Map.get(variant, "mime", "image/png")),
      "bytes" => integer_or_zero(Map.get(variant, "bytes", 0)),
      "width" => integer_or_zero(Map.get(variant, "width", 0)),
      "height" => integer_or_zero(Map.get(variant, "height", 0))
    }
  end

  defp variant_dimensions(row, color_mode) do
    case variant_row(row, color_mode) do
      %{"width" => width, "height" => height} when is_integer(width) and is_integer(height) ->
        {width, height}

      _ ->
        nil
    end
  end

  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value

  defp integer_or_zero(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int >= 0 -> int
      _ -> 0
    end
  end

  defp integer_or_zero(_), do: 0
end
