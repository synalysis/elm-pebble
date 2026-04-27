defmodule Ide.PebbleToolchainTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias Ide.PebbleToolchain

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_pebble_toolchain_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "infer_package_target_type follows Pebble.Platform watchface entrypoint" do
    slug = "toolchain-watchface-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Toolchain Watchface",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-digital"
             })

    project_root = Path.join(Projects.project_workspace_path(project), "watch")

    on_exit(fn -> Projects.delete_project(project) end)

    assert PebbleToolchain.infer_package_target_type(project_root, "app") == "watchface"
  end

  test "infer_package_target_type follows Pebble.Platform application entrypoint" do
    slug = "toolchain-application-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Toolchain Application",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "starter"
             })

    project_root = Path.join(Projects.project_workspace_path(project), "watch")

    on_exit(fn -> Projects.delete_project(project) end)

    assert PebbleToolchain.infer_package_target_type(project_root, "watchface") == "app"
  end
end
