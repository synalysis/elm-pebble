defmodule Ide.Resources.BitmapVariantsStoreTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias Ide.Resources.ResourceStore

  setup do
    root = Path.join(System.tmp_dir!(), "bitmap_variants_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "import_bitmap stores monochrome and color variants for one ctor" do
    slug = "bitmap-variants-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Bitmap Variants",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    workspace = Projects.project_workspace_path(project)
    mono_png = write_png()
    color_png = write_png()

    assert {:ok, _} =
             ResourceStore.import_bitmap(project, mono_png, "charmander.png",
               color_mode: "BlackWhite"
             )

    assert {:ok, _} =
             ResourceStore.import_bitmap(project, color_png, "charmander.png",
               color_mode: "Color",
               ctor: "BitmapStaticCharmander"
             )

    manifest =
      Jason.decode!(File.read!(Path.join(workspace, "watch/resources/bitmaps.json")))

    assert [%{"ctor" => "BitmapStaticCharmander", "base_name" => "Charmander", "variants" => variants}] =
             manifest["entries"]
    assert variants["BlackWhite"]["filename"] == "BitmapStaticCharmander~bw.png"
    assert variants["Color"]["filename"] == "BitmapStaticCharmander~color.png"
    assert File.exists?(Path.join(workspace, "watch/resources/bitmaps/BitmapStaticCharmander~bw.png"))
    assert File.exists?(Path.join(workspace, "watch/resources/bitmaps/BitmapStaticCharmander~color.png"))
  end

  test "import_bitmaps_from_directory registers each png in assets dir" do
    slug = "bitmap-dir-sync-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Bitmap Dir Sync",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    workspace = Projects.project_workspace_path(project)
    assets = Path.join(workspace, "watch/resources/bitmaps")
    File.mkdir_p!(assets)
    File.write!(Path.join(assets, "Alpha.png"), write_png_bytes())
    File.write!(Path.join(assets, "Beta.png"), write_png_bytes() <> "x")

    assert {:ok, %{imported: 2, duplicates: 0, skipped: 0}} =
             ResourceStore.import_bitmaps_from_directory(project)

    assert {:ok, entries} = ResourceStore.list(project)
    assert Enum.sort(Enum.map(entries, & &1.ctor)) == ["BitmapStaticAlpha", "BitmapStaticBeta"]
  end

  test "legacy import uses untagged filename" do
    slug = "bitmap-legacy-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Bitmap Legacy",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    workspace = Projects.project_workspace_path(project)
    png = write_png()

    assert {:ok, _} = ResourceStore.import_bitmap(project, png, "logo.png")

    manifest =
      Jason.decode!(File.read!(Path.join(workspace, "watch/resources/bitmaps.json")))

    assert [%{"ctor" => "BitmapStaticLogo", "filename" => "BitmapStaticLogo.png"} = entry] =
             manifest["entries"]
    refute Ide.Resources.BitmapVariants.has_variants?(entry)
  end

  defp write_png do
    path = Path.join(System.tmp_dir!(), "bitmap_#{System.unique_integer([:positive])}.png")
    File.write!(path, write_png_bytes())
    path
  end

  defp write_png_bytes, do: <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>
end
