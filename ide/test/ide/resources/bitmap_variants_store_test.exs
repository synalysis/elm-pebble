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
               ctor: "Charmander"
             )

    manifest =
      Jason.decode!(File.read!(Path.join(workspace, "watch/resources/bitmaps.json")))

    assert [%{"ctor" => "Charmander", "variants" => variants}] = manifest["entries"]
    assert variants["BlackWhite"]["filename"] == "Charmander~bw.png"
    assert variants["Color"]["filename"] == "Charmander~color.png"
    assert File.exists?(Path.join(workspace, "watch/resources/bitmaps/Charmander~bw.png"))
    assert File.exists?(Path.join(workspace, "watch/resources/bitmaps/Charmander~color.png"))
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

    assert [%{"ctor" => "Logo", "filename" => "Logo.png"} = entry] = manifest["entries"]
    refute Ide.Resources.BitmapVariants.has_variants?(entry)
  end

  defp write_png do
    path = Path.join(System.tmp_dir!(), "bitmap_#{System.unique_integer([:positive])}.png")
    File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>)
    path
  end
end
