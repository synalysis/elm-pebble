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
    assert updated.debugger_settings["watch_profile_id"] == "emery"

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
    html = render(view)
    assert html =~ "WASM Emulator"
    assert has_element?(view, "span[data-wasm-firmware]")
    refute has_element?(view, "select[data-wasm-firmware]")

    assert has_element?(
             view,
             "a[data-phx-link='patch'][href='/projects/#{project.slug}/emulator']"
           )

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")
    assert has_element?(view, "select[name='emulator[mode]'] option[selected][value='wasm']")
  end

  test "emulator pane hides unsupported wasm mode for gabbro", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceGabbroWasmSettings",
               "slug" => "workspace-gabbro-wasm-settings",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")

    view
    |> form("form[phx-change='set-emulator-target']", %{
      "emulator" => %{"target" => "gabbro", "mode" => "wasm"}
    })
    |> render_change()

    updated = Projects.get_project_by_slug(project.slug)
    assert updated.debugger_settings["emulator_target"] == "gabbro"
    assert updated.debugger_settings["emulator_mode"] == "embedded"

    refute has_element?(view, "select[name='emulator[mode]'] option[value='wasm']")
    assert has_element?(view, "select[name='emulator[mode]'] option[selected][value='embedded']")
    refute render(view) =~ "WASM Emulator"
  end

  test "emulator pane hides wasm mode for chalk until the browser runtime boots it", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceChalkWasmSettings",
               "slug" => "workspace-chalk-wasm-settings",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/emulator")

    view
    |> form("form[phx-change='set-emulator-target']", %{
      "emulator" => %{"target" => "chalk", "mode" => "wasm"}
    })
    |> render_change()

    updated = Projects.get_project_by_slug(project.slug)
    assert updated.debugger_settings["emulator_target"] == "chalk"
    assert updated.debugger_settings["emulator_mode"] == "embedded"

    refute has_element?(view, "select[name='emulator[mode]'] option[value='wasm']")
    assert has_element?(view, "select[name='emulator[mode]'] option[selected][value='embedded']")
    refute render(view) =~ "WASM Emulator"
  end

  test "debugger visual preview remembers simulator settings per project", %{conn: conn} do
    slug = "workspace-debugger-simulator-settings"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceDebuggerSimulatorSettings",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "companion-demo-phone-status"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/debugger")

    view
    |> form("form#debugger-simulator-settings", %{
      "simulator" => %{
        "battery_percent" => "42",
        "charging" => "true",
        "clock_24h" => "false",
        "use_simulated_time" => "true",
        "simulated_date" => "2026-05-19",
        "simulated_time" => "07:08:09",
        "locale" => "de-DE",
        "network_online" => "false",
        "notifications_enabled" => "true",
        "quiet_hours" => "false"
      }
    })
    |> render_change()

    updated = Projects.get_project_by_slug(project.slug)
    simulator = updated.debugger_settings["simulator"]

    assert simulator["battery_percent"] == 42
    assert simulator["charging"] == true
    assert simulator["clock_24h"] == false
    assert simulator["use_simulated_time"] == true
    assert simulator["simulated_date"] == "2026-05-19"
    assert simulator["simulated_time"] == "07:08:09"
    assert simulator["locale"] == "de-DE"
    assert simulator["network_online"] == false
    assert simulator["notifications_enabled"] == true
    assert simulator["quiet_hours"] == false

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/debugger")
    assert has_element?(view, "input[name='simulator[battery_percent]'][value='42']")

    assert has_element?(
             view,
             "input[name='simulator[use_simulated_time]'][checked]"
           )

    assert has_element?(
             view,
             "input[name='simulator[simulated_date]'][value='2026-05-19']"
           )

    assert has_element?(
             view,
             "input[name='simulator[simulated_time]'][value='07:08:09']"
           )

    assert has_element?(view, "input[name='simulator[locale]'][value='de-DE']")
  end

  test "project settings release pane shows read-only detected capabilities", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceProjectCapabilities",
               "slug" => "workspace-project-capabilities",
               "target_type" => "app"
             })

    assert {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/settings")

    assert html =~ "Detected from Elm API usage"
    assert html =~ "Not used"
    refute html =~ "project_settings[capabilities]"
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
        "description" => "A small Pebble watchapp.",
        "tags" => "fitness,utility",
        "target_platforms" => ["basalt", "chalk"],
        "website_url" => "https://elm-pebble.dev",
        "source_url" => "https://github.com/elm-pebble/watch"
      }
    })
    |> render_submit()

    assert render(view) =~ "Project settings saved."

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings/store")

    view
    |> form("#project-settings-form", %{
      "project_settings" => %{"generate_store_graphics" => "true"}
    })
    |> render_submit()

    assert render(view) =~ "Generate App Store icons with AI"

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings/github")

    view
    |> form("#project-settings-form", %{
      "project_settings" => %{
        "github_owner" => "elm-pebble",
        "github_repo" => "watch",
        "github_branch" => "main",
        "github_visibility" => "public"
      }
    })
    |> render_submit()

    updated = Projects.get_project_by_slug(project.slug)
    assert updated.release_defaults["version_label"] == "1.2.3"
    assert updated.release_defaults["description"] == "A small Pebble watchapp."
    assert updated.release_defaults["tags"] == "fitness,utility"
    assert updated.release_defaults["target_platforms"] == ["basalt", "chalk"]
    assert updated.release_defaults["capabilities"] == []
    assert updated.release_defaults["generate_store_graphics"] == true
    assert updated.release_defaults["website_url"] == "https://elm-pebble.dev"
    assert updated.release_defaults["source_url"] == "https://github.com/elm-pebble/watch"
    assert updated.github["owner"] == "elm-pebble"
    assert updated.github["visibility"] == "public"
    assert updated.github["repo"] == "watch"
    assert updated.github["branch"] == "main"
  end

  test "project settings shows App Store metadata sync control", %{conn: conn} do
    original_auth = Application.get_env(:ide, Ide.Auth, [])
    Application.put_env(:ide, Ide.Auth, Keyword.put(original_auth, :mode, :public_pebble))

    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original_auth) end)

    {:ok, user} =
      %Ide.Auth.User{}
      |> Ide.Auth.User.changeset(%{firebase_uid: "store-listing-sync", email: "store@example.test"})
      |> Ide.Repo.insert()

    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    assert {:ok, project} =
             Projects.create_project(
               %{
                 "name" => "WorkspaceStoreListingSync",
                 "slug" => "workspace-store-listing-sync",
                 "target_type" => "app"
               },
               user
             )

    assert {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/settings")

    assert html =~ "Update App Store metadata"
    assert html =~ "App Store sync:"

    view
    |> form("#project-settings-form", %{
      "project_settings" => %{
        "version_label" => "1.0.0",
        "description" => "Sync me",
        "tags" => "",
        "website_url" => "",
        "source_url" => ""
      }
    })
    |> render_submit(%{"sync_store_listing" => "1"})

    assert render(view) =~ "Project settings saved."
    assert render(view) =~ "Refreshing App Store login"
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

    html = render(view)

    assert html =~ "Prepare Release warning"
    assert html =~ "Warning!"
    refute html =~ "Error!"
  end
end
