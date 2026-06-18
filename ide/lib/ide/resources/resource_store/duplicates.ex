defmodule Ide.Resources.ResourceStore.Duplicates do
  @moduledoc false

  alias Ide.Resources.BitmapVariants
  alias Ide.Resources.Types

  @spec duplicate_asset_entry([Types.manifest_wire_row()], String.t(), binary()) ::
          Types.manifest_wire_row() | nil
  def duplicate_asset_entry(entries, assets_dir, bytes) when is_list(entries) and is_binary(bytes) do
    Enum.find(entries, fn row ->
      Enum.any?(BitmapVariants.filenames_for_row(row), fn filename ->
        match?({:ok, ^bytes}, File.read(Path.join(assets_dir, filename)))
      end)
    end)
  end

  @spec duplicate_variant_color_mode_entry(
          [Types.manifest_wire_row()],
          String.t(),
          binary(),
          String.t()
        ) :: Types.manifest_wire_row() | nil
  def duplicate_variant_color_mode_entry(entries, assets_dir, bytes, color_mode)
      when is_list(entries) and is_binary(bytes) and is_binary(color_mode) do
    Enum.find(entries, fn row ->
      case get_in(row, ["variants", color_mode, "filename"]) do
        filename when is_binary(filename) and filename != "" ->
          match?({:ok, ^bytes}, File.read(Path.join(assets_dir, filename)))

        _ ->
          false
      end
    end)
  end
end
