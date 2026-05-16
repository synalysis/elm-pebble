defmodule IdeWeb.WorkspaceLive.ProjectSettingsTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.Projects

  test "emulator pane remembers selected watch model in project settings", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceEmulatorSettings",
               "slug" => "workspace-emulator-settings",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")
    html = render(view)
    assert html =~ "data-emulator-launch"
    refute html =~ "data-emulator-stop"

    view
    |> form("form[phx-change='set-emulator-target']", %{
      "emulator" => %{"target" => "emery"}
    })
    |> render_change()

    updated = Projects.get_project_by_slug(project.slug)
    assert updated.debugger_settings["emulator_target"] == "emery"

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")
    assert has_element?(view, "select[name='emulator[target]'] option[selected][value='emery']")
  end

  test "emulator pane remembers wasm emulator mode in project settings", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceWasmEmulatorSettings",
               "slug" => "workspace-wasm-emulator-settings",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")

    view
    |> form("form[phx-change='set-emulator-target']", %{
      "emulator" => %{"target" => "emery", "mode" => "wasm"}
    })
    |> render_change()

    updated = Projects.get_project_by_slug(project.slug)
    assert updated.debugger_settings["emulator_mode"] == "wasm"
    assert render(view) =~ "WASM Emulator"

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")
    assert has_element?(view, "select[name='emulator[mode]'] option[selected][value='wasm']")
  end

  test "project settings pane saves release metadata and github config", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceProjectSettings",
               "slug" => "workspace-project-settings",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    view
    |> form("#project-settings-form", %{
      "project_settings" => %{
        "version_label" => "1.2.3",
        "tags" => "fitness,utility",
        "target_platforms" => ["basalt", "chalk"],
        "capabilities" => ["location", "health"],
        "github_owner" => "elm-pebble",
        "github_repo" => "watch",
        "github_branch" => "main"
      }
    })
    |> render_submit()

    assert render(view) =~ "Project settings saved."

    updated = Projects.get_project_by_slug(project.slug)
    assert updated.release_defaults["version_label"] == "1.2.3"
    assert updated.release_defaults["tags"] == "fitness,utility"
    assert updated.release_defaults["target_platforms"] == ["basalt", "chalk"]
    assert updated.release_defaults["capabilities"] == ["location", "health"]
    assert updated.github["owner"] == "elm-pebble"
    assert updated.github["repo"] == "watch"
    assert updated.github["branch"] == "main"
  end

  test "prepare release warns when workspace has uncommitted git changes", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspacePrepareWarn",
               "slug" => "workspace-prepare-warn",
               "target_type" => "app"
             })

    workspace_root = Projects.project_workspace_path(project)
    {_, 0} = System.cmd("git", ["init"], cd: workspace_root, stderr_to_stdout: true)

    assert :ok =
             File.write(
               Path.join(workspace_root, "watch/src/Main.elm"),
               "module Main exposing (..)\n\n"
             )

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/publish")

    render_click(view, "prepare-release")

    assert render(view) =~ "Prepare Release warning"
  end
end
