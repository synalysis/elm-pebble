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
end
