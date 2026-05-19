defmodule IdeWeb.ProjectsLiveTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.GitHub.Credentials

  setup do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_projects_live_github_#{System.unique_integer([:positive])}.json"
      )

    original = Application.get_env(:ide, Ide.GitHub, [])
    Application.put_env(:ide, Ide.GitHub, credentials_path: temp_path)
    Credentials.clear()

    on_exit(fn ->
      Application.put_env(:ide, Ide.GitHub, original)
      File.rm(temp_path)
    end)

    :ok
  end

  test "projects page shows GitHub import option in import panel", %{conn: conn} do
    assert {:ok, view, html} = live(conn, ~p"/projects")
    assert html =~ "Import"

    view |> element("button", "Import") |> render_click()
    html = view |> element("button", "From GitHub") |> render_click()

    assert html =~ "From folder"
    assert html =~ "From GitHub"
    assert html =~ "Repository URL"
    assert html =~ "Import from GitHub"
  end

  test "GitHub import submit is disabled when GitHub is not connected", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/projects")

    view |> element("button", "Import") |> render_click()
    html = view |> element("button", "From GitHub") |> render_click()

    assert html =~ "Connect GitHub"
    assert html =~ "Import from GitHub"
    assert html =~ "disabled"
  end
end
