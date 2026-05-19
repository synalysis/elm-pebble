defmodule Ide.ProjectReadmeTest do
  use ExUnit.Case, async: true

  alias Ide.ProjectReadme
  alias Ide.Projects.Project

  test "content describes project and links to elm-pebble.dev" do
    project = %Project{
      name: "Tangram Time",
      target_type: "watchface",
      release_defaults: %{"description" => "A geometric watchface."}
    }

    body = ProjectReadme.content(project)

    assert body =~ "# Tangram Time"
    assert body =~ "A geometric watchface."
    assert body =~ "https://elm-pebble.dev"
    assert body =~ "screenshots/"
    assert body =~ "<!-- elm-pebble-ide:readme -->"
  end

  test "write creates README.md in workspace" do
    root = Path.join(System.tmp_dir!(), "ide_readme_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    File.mkdir_p!(root)

    project = %Project{name: "Demo", target_type: "app"}

    assert :ok = ProjectReadme.write(root, project)
    readme = File.read!(Path.join(root, "README.md"))
    assert readme =~ "**Elm Pebble** watch app"
    assert readme =~ ProjectReadme.site_url()
  end

  test "write updates marked block without clobbering custom prefix" do
    root = Path.join(System.tmp_dir!(), "ide_readme_merge_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    File.mkdir_p!(root)

    path = Path.join(root, "README.md")

    File.write!(
      path,
      """
      # My notes

      Custom intro kept by the author.

      <!-- elm-pebble-ide:readme -->
      old generated block
      <!-- /elm-pebble-ide:readme -->
      """
    )

    project = %Project{name: "Updated", target_type: "watchface"}

    assert :ok = ProjectReadme.write(root, project)
    readme = File.read!(path)
    assert readme =~ "# My notes"
    assert readme =~ "Custom intro kept by the author."
    assert readme =~ "# Updated"
    refute readme =~ "old generated block"
  end
end
