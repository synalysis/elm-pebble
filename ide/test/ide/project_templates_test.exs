defmodule Ide.ProjectTemplatesTest do
  use Ide.DataCase, async: false

  alias Ide.ProjectTemplates
  alias Ide.Projects

  setup do
    root = Path.join(System.tmp_dir!(), "ide_templates_test_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "templates without metadata enable all supported platforms" do
    platforms = ProjectTemplates.target_platforms_for_template("watchface-digital")

    assert "aplite" in platforms
    assert "basalt" in platforms
    assert "gabbro" in platforms
  end

  test "watchface-tangram-time template excludes aplite" do
    platforms = ProjectTemplates.target_platforms_for_template("watchface-tangram-time")

    refute "aplite" in platforms
    assert platforms == ["basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end

  test "watch demo templates with metadata restrict target platforms" do
    compass = ProjectTemplates.target_platforms_for_template("watch-demo-compass")
    dictation = ProjectTemplates.target_platforms_for_template("watch-demo-dictation")
    health = ProjectTemplates.target_platforms_for_template("watch-demo-health")

    assert compass == ["aplite"]
    assert dictation == ["diorite", "emery", "flint"]
    assert health == ["basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end

  test "create_project applies template target platform defaults" do
    slug = "tangram-platforms-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Platforms",
               "slug" => slug,
               "template" => "watchface-tangram-time"
             })

    assert project.release_defaults["target_platforms"] == [
             "basalt",
             "chalk",
             "diorite",
             "emery",
             "flint",
             "gabbro"
           ]
  end

  test "explicit release_defaults override template defaults" do
    slug = "tangram-override-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Override",
               "slug" => slug,
               "template" => "watchface-tangram-time",
               "release_defaults" => %{"target_platforms" => ["basalt"]}
             })

    assert project.release_defaults["target_platforms"] == ["basalt"]
  end
end
