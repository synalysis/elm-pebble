defmodule Ide.StoreAssetsTest do
  use ExUnit.Case, async: true

  alias Ide.StoreAssets

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_store_assets_test_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)
    %{workspace_root: root}
  end

  test "save_icon validates dimensions and persists under store_assets/", %{workspace_root: root} do
    small = Path.join(System.tmp_dir!(), "icon_small.png")
    large = Path.join(System.tmp_dir!(), "icon_large.png")
    bad = Path.join(System.tmp_dir!(), "icon_bad.png")

    File.write!(small, png_header(80, 80))
    File.write!(large, png_header(144, 144))
    File.write!(bad, png_header(80, 81))

    on_exit(fn ->
      File.rm(small)
      File.rm(large)
      File.rm(bad)
    end)

    assert :ok = StoreAssets.save_icon(root, :icon_small, small)
    assert :ok = StoreAssets.save_icon(root, :icon_large, large)
    assert {:error, {:invalid_dimensions, _}} = StoreAssets.save_icon(root, :icon_small, bad)

    assert File.regular?(Path.join(root, "store_assets/icon_small.png"))
    assert File.regular?(Path.join(root, "store_assets/icon_large.png"))

    icons = StoreAssets.publish_icon_paths(root)
    assert Map.keys(icons) |> Enum.sort() == [:icon_large, :icon_small]

    status = StoreAssets.status(root)
    assert status.icon_small.valid
    assert status.icon_large.valid

    assert StoreAssets.size_label(:icon_small) == "80×80 px"
    assert StoreAssets.size_label(:icon_large) == "144×144 px"
    assert StoreAssets.required_sizes_summary() =~ "80×80 px"
    assert StoreAssets.required_sizes_summary() =~ "144×144 px"
    assert StoreAssets.banner_size_label() == "720×320 px"
  end

  defp png_header(width, height) do
    <<0x89, "PNG\r\n", 0x1A, "\n", 0::32, "IHDR", width::32, height::32, 0::32>>
  end
end
