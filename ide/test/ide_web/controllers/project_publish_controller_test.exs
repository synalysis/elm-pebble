defmodule IdeWeb.ProjectPublishControllerTest do
  use IdeWeb.ConnCase, async: false

  alias Ide.Projects

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    Application.put_env(:ide, Ide.Auth, mode: :local)
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "PBW download uses slug and version as the filename", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        "name" => "Publish Filename",
        "slug" => "pbw-download-name",
        "target_type" => "watchface",
        "release_defaults" => %{"version_label" => "1.0.0"}
      })

    build_dir = Path.join(Projects.project_workspace_path(project), ".pebble-sdk/app/build")
    File.mkdir_p!(build_dir)
    File.write!(Path.join(build_dir, "app.pbw"), "pbw-bytes")

    conn = get(conn, ~p"/projects/#{project.slug}/publish/pbw")

    assert conn.status == 200
    assert conn.resp_body == "pbw-bytes"

    disposition = List.keyfind(conn.resp_headers, "content-disposition", 0)
    assert disposition
    assert elem(disposition, 1) =~ ~s(filename="pbw-download-name-1.0.0.pbw")
  end

  test "PBW download redirects when no artifact exists", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        "name" => "Publish Missing Pbw",
        "slug" => "publish-missing-pbw",
        "target_type" => "watchface"
      })

    conn = get(conn, ~p"/projects/#{project.slug}/publish/pbw")

    assert redirected_to(conn) == ~p"/projects/#{project.slug}/publish"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No PBW found"
  end
end
