defmodule IdeWeb.WorkspaceLive.EmulatorProductionBuildTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.EmulatorFlow

  test "Production build checkbox persists in debugger_settings", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Prod Build Emulator",
               "slug" => "prod-build-emulator-#{System.unique_integer([:positive])}",
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")

    assert has_element?(view, "#emulator-production-build-form")
    assert render(view) =~ "Production build"

    view
    |> form("#emulator-production-build-form[phx-change='set-emulator-target']", %{
      "emulator" => %{
        "target" => EmulatorFlow.project_emulator_target(project),
        "mode" => EmulatorFlow.project_emulator_mode(project),
        "production_build" => "false"
      }
    })
    |> render_change()

    reloaded = Projects.get_project_by_slug(project.slug)
    assert reloaded.debugger_settings["emulator_production_build"] == false
    assert EmulatorFlow.project_emulator_production_build(reloaded) == false
  end

  test "defaults Production build to enabled for new projects" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Prod Build Default",
               "slug" => "prod-build-default-#{System.unique_integer([:positive])}",
               "target_type" => "watchface"
             })

    assert EmulatorFlow.project_emulator_production_build(project) == true
  end
end
