defmodule IdeWeb.WorkspaceLive.ResourcesFlowTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias Ide.Resources.ResourceStore
  alias IdeWeb.WorkspaceLive.ResourcesFlow

  setup do
    root = Path.join(System.tmp_dir!(), "resources_flow_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "load_bitmap_resources returns rows after color variant import" do
    slug = "resources-flow-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Resources Flow",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    png = write_png()

    assert {:ok, _} =
             ResourceStore.import_bitmap(project, png, "sprite.png", color_mode: "Color")

    assert {[%{} = row], nil} = ResourcesFlow.load_bitmap_resources(project)
    assert row.ctor == "Sprite"
    assert length(row.variant_slots) == 2
    assert Enum.any?(row.variant_slots, &(&1.color_mode == "Color" and &1.filename == "Sprite~color.png"))
  end

  test "load_bitmap_resources reports invalid manifest instead of silent empty list" do
    slug = "resources-flow-bad-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Bad Manifest",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    manifest = Path.join(Projects.project_workspace_path(project), "watch/resources/bitmaps.json")
    File.mkdir_p!(Path.dirname(manifest))
    File.write!(manifest, "{not valid json")

    assert {[], error} = ResourcesFlow.load_bitmap_resources(project)
    assert error =~ "invalid JSON"
  end

  defp write_png do
    path = Path.join(System.tmp_dir!(), "flow_#{System.unique_integer([:positive])}.png")
    File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>)
    path
  end
end
