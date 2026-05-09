defmodule IdeWeb.WorkspaceLivePackagesTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.Debugger
  alias Ide.Projects
  alias Ide.Settings

  defmodule MockPackageProvider do
    @behaviour Ide.Packages.Provider

    @impl true
    def search(_query, _opts) do
      {:ok, [%{name: "elm/http", summary: "HTTP", license: "BSD-3-Clause", version: "2.0.0"}]}
    end

    @impl true
    def package_details("elm-pebble/elm-watch", _opts) do
      {:ok,
       %{
         name: "elm-pebble/elm-watch",
         summary: "Pebble watch platform",
         latest_version: "2.0.0",
         versions: ["2.0.0"],
         exposed_modules: [],
         elm_json: %{}
       }}
    end

    def package_details(package, _opts) do
      {:ok,
       %{
         name: package,
         summary: "HTTP package",
         latest_version: "2.0.0",
         versions: ["1.0.0", "2.0.0"],
         exposed_modules: ["Http"],
         elm_json: %{}
       }}
    end

    @impl true
    def versions("elm-pebble/elm-watch", _opts), do: {:ok, ["1.0.0", "2.0.0"]}

    def versions("elm/http", _opts), do: {:ok, ["2.0.0"]}
    def versions("elm/url", _opts), do: {:ok, ["1.0.0"]}
    def versions("elm/core", _opts), do: {:ok, ["1.0.5"]}
    def versions("elm/json", _opts), do: {:ok, ["1.1.3"]}
    def versions(_package, _opts), do: {:ok, ["1.0.0"]}

    @impl true
    def package_release("elm/http", "2.0.0", _opts) do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/url" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/url", "1.0.0", _opts) do
      {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}
    end

    def package_release("elm-pebble/elm-watch", version, _opts)
        when version in ["1.0.0", "2.0.0"] do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/json" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/core", "1.0.5", _opts), do: {:ok, %{"dependencies" => %{}}}

    def package_release("elm/json", "1.1.3", _opts),
      do: {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

    def package_release(_package, _version, _opts), do: {:ok, %{"dependencies" => %{}}}

    @impl true
    def readme(_package, _version, _opts), do: {:ok, "# README"}
  end

  setup do
    previous_packages_env = Application.get_env(:ide, Ide.Packages)

    Application.put_env(:ide, Ide.Packages,
      provider_order: [:mock],
      providers: [mock: [module: MockPackageProvider]]
    )

    on_exit(fn ->
      if previous_packages_env == nil do
        Application.delete_env(:ide, Ide.Packages)
      else
        Application.put_env(:ide, Ide.Packages, previous_packages_env)
      end
    end)

    :ok
  end

  test "packages pane supports browse and add flow", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspacePackages",
               "slug" => "workspace-packages",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/packages")

    assert render(view) =~ "Dependencies"
    assert render(view) =~ "Catalog search"

    view
    |> form("#packages-search-form", %{"packages_search" => %{"query" => "elm/http"}})
    |> render_change()

    assert render_async(view) =~ "elm/http"

    render_click(view, "packages-select", %{"package" => "elm/http"})
    assert render_async(view) =~ "Dependency preview"
    assert render_async(view) =~ "Blocked"
    assert render_async(view) =~ "currently blocked for Pebble runtime compatibility"

    render_click(view, "packages-add", %{"package" => "elm/http"})
    assert render(view) =~ "Last add"

    assert {:ok, elm_json} = Projects.read_source_file(project, "watch", "elm.json")
    assert elm_json =~ "\"elm/http\": \"2.0.0\""
  end

  test "packages target root defaults to active phone tab when navigating from editor", %{
    conn: conn
  } do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspacePackagesPhoneDefault",
               "slug" => "workspace-packages-phone-default",
               "target_type" => "app"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/editor")

    render_click(view, "open-file", %{"source-root" => "phone", "rel-path" => "src/Engine.elm"})
    _ = render_async(view, 1_500)

    view
    |> element("a[href$=\"/settings\"]")
    |> render_click()

    view
    |> element("a[href$=\"/packages\"]")
    |> render_click()

    html = render(view)
    assert html =~ ~r/<option[^>]*selected[^>]*value="phone"/
  end

  test "packages pane removes a direct dependency and updates elm.json", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspacePackagesRm",
               "slug" => "workspace-packages-rm",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/packages")

    view
    |> form("#packages-search-form", %{"packages_search" => %{"query" => "elm/http"}})
    |> render_change()

    _ = render_async(view)

    render_click(view, "packages-select", %{"package" => "elm/http"})
    _ = render_async(view)

    render_click(view, "packages-add", %{"package" => "elm/http"})

    render_click(view, "packages-remove", %{"package" => "elm/http"})

    assert {:ok, elm_json} = Projects.read_source_file(project, "watch", "elm.json")
    refute elm_json =~ "\"elm/http\""
    assert render(view) =~ "Blocked"
  end

  test "packages pane marks required packages without remove buttons", %{
    conn: conn
  } do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspacePackagesRequired",
               "slug" => "workspace-packages-required",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/packages")

    html = render_async(view)

    assert html =~ "elm/core"
    assert html =~ "elm/json"
    assert html =~ "elm/time"
    assert html =~ "Required"
    assert html =~ "Required packages cannot be removed from elm.json."
    refute html =~ "Remove elm/core from elm.json?"
    refute html =~ "Remove elm/json from elm.json?"
    refute html =~ "Remove elm/time from elm.json?"

    render_click(view, "packages-remove", %{"package" => "elm/json"})
    assert render(view) =~ "Required packages"
  end

  test "build pane no longer renders Elm package management", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceBuild",
               "slug" => "workspace-build-ui",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/build")
    html = render(view)
    refute html =~ "Search packages"
    refute html =~ "Elm Packages"
  end

  test "editor exposes foldable documentation panel", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceEditorDocs",
               "slug" => "workspace-editor-docs-ui",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/editor")
    assert render(view) =~ "toggle-editor-docs-panel"
    assert has_element?(view, "button", "Show documentation")

    view |> element("button", "Show documentation") |> render_click()
    _ = render_async(view, 1_500)
    assert has_element?(view, "button", "Hide documentation")
    assert render(view) =~ "name=\"doc_pkg\""
    refute render(view) =~ "— Select —"

    html =
      view
      |> form("#editor-doc-package-form", %{"doc_pkg" => "elm-pebble/elm-watch"})
      |> render_change()

    assert html =~ "Pebble.Platform"
    assert html =~ ~s(value="Pebble.Ui")
  end

  test "debugger model renders nested Elm records inside constructors", %{conn: conn} do
    slug = "workspace-debugger-elm-records"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceDebuggerElmRecords",
               "slug" => slug,
               "target_type" => "app"
             })

    assert {:ok, _state} =
             Debugger.import_trace(project.slug, %{
               "export_version" => 1,
               "project_slug" => project.slug,
               "running" => true,
               "watch" => %{
                 "model" => %{
                   "runtime_model" => %{
                     "elm_executor_core_ir_b64" => String.duplicate("abc123", 20),
                     "currentDateTime" => %{
                       "ctor" => "Just",
                       "args" => [
                         %{
                           "day" => 26,
                           "dayOfWeek" => %{"ctor" => "Sun", "args" => []},
                           "hour" => 6,
                           "minute" => 7
                         }
                       ]
                     }
                   }
                 }
               },
               "companion" => %{},
               "phone" => %{},
               "events" => [],
               "debugger_timeline" => [],
               "seq" => 0
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/debugger")
    html = render(view)

    assert html =~ "currentDateTime"
    assert html =~ "Just {"
    assert html =~ "dayOfWeek = Sun"

    assert html =~
             ~s(title="elm_executor_core_ir_b64 = &quot;#{String.duplicate("abc123", 20)}&quot;")

    refute html =~ "Just %{"
  end

  test "debugger watch profile selection survives in-memory debugger restart", %{conn: conn} do
    slug = "workspace-debugger-watch-profile-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceDebuggerWatchProfile",
               "slug" => slug,
               "target_type" => "watchface"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/debugger")

    render_change(view, "debugger-set-watch-profile", %{"watch_profile_id" => "chalk"})

    assert %{"watch_profile_id" => "chalk"} =
             Projects.get_project_by_slug(project.slug).debugger_settings

    Debugger.forget_project(project.slug)

    assert {:ok, state} = Debugger.snapshot(project.slug, event_limit: 20)
    assert state.watch_profile_id == "chalk"

    assert {:ok, restarted_view, _html} = live(conn, ~p"/projects/#{project.slug}/debugger")
    assert has_element?(restarted_view, ~s(option[value="chalk"][selected]))
  end

  test "debugger renders companion configuration under companion model", %{conn: conn} do
    slug = "workspace-debugger-companion-config-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceDebuggerCompanionConfig",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tutorial-complete"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/debugger")
    render_click(view, "debugger-start")

    assert {:ok, state} = Debugger.snapshot(project.slug, event_limit: 20)

    assert get_in(state.companion, [:model, "runtime_model", "configuration", "title"]) ==
             "Tutorial Watchface"

    html = render(view)

    assert html =~ ~s(data-testid="debugger-companion-configuration")
    assert html =~ "Reset"
    refute html =~ "Tutorial Watchface"
    assert html =~ "Background"
    assert html =~ "Text"
    assert html =~ "Show date"
    assert html =~ "backgroundColor"
    assert html =~ "showDate"
    refute html =~ "configuration {"

    view
    |> form("form[phx-submit='debugger-save-configuration']", %{
      "configuration" => %{
        "backgroundColor" => "blue",
        "textColor" => "yellow",
        "showDate" => "false"
      }
    })
    |> render_submit()

    view
    |> form("form[phx-submit='debugger-save-configuration']", %{
      "configuration" => %{
        "backgroundColor" => "blue",
        "textColor" => "yellow",
        "showDate" => "true"
      }
    })
    |> render_submit()

    assert {:ok, saved_state} = Debugger.snapshot(project.slug, event_limit: 20)

    watch_runtime_model = get_in(saved_state.watch, [:model, "runtime_model"]) || %{}

    assert watch_runtime_model["showDate"] == %{
             "ctor" => "Just",
             "args" => [true]
           }

    assert get_in(watch_runtime_model, ["backgroundColor", "ctor"]) == "Just"
    assert get_in(watch_runtime_model, ["textColor", "ctor"]) == "Just"
    assert watch_runtime_model["isRound"] == false
    refute Map.has_key?(watch_runtime_model, "protocol_message_count")

    assert get_in(saved_state.watch, [:view_tree, "type"]) == "windowStack"
    view_tree_json = Jason.encode!(saved_state.watch.view_tree)
    assert view_tree_json =~ ~s("text":"0C Clear")
    assert view_tree_json =~ ~r/"text":"[A-Z][a-z]{2} [A-Z][a-z]{2} \d{1,2}"/
    assert view_tree_json =~ ~s("text_color":248)

    runtime_output = get_in(saved_state.watch, [:model, "runtime_view_output"]) || []
    assert runtime_output != []
    runtime_output_json = Jason.encode!(runtime_output)
    assert runtime_output_json =~ ~s("text":"0C Clear")
    assert runtime_output_json =~ ~s("color":248,"kind":"text_color")

    saved_html = render(view)

    assert get_in(saved_state.companion, [:model, "configuration", "values", "backgroundColor"]) ==
             "blue"

    assert get_in(saved_state.companion, [:model, "configuration", "values", "textColor"]) ==
             "yellow"

    assert get_in(saved_state.companion, [:model, "configuration", "values", "showDate"]) == true
    assert saved_html =~ ~r/<option(?=[^>]*selected)(?=[^>]*value="blue")/
    assert saved_html =~ ~r/<option(?=[^>]*selected)(?=[^>]*value="yellow")/
    assert saved_html =~ ~r/<input(?=[^>]*checked)(?=[^>]*name="configuration\[showDate\]")/
    refute saved_html =~ "Unresolved primitives"
    refute saved_html =~ "toUiNode"

    render_click(view, "debugger-start")
    assert {:ok, restarted_state} = Debugger.snapshot(project.slug, event_limit: 20)

    assert get_in(restarted_state.companion, [
             :model,
             "configuration",
             "values",
             "backgroundColor"
           ]) ==
             "blue"

    render_click(view, "debugger-reset-configuration")

    assert {:ok, reset_state} = Debugger.snapshot(project.slug, event_limit: 20)
    refute get_in(reset_state.companion, [:model, "configuration", "values", "backgroundColor"])

    messages = Enum.map(saved_state.debugger_timeline, & &1.message)
    assert Enum.any?(messages, &String.contains?(&1, "SetShowDate True"))

    bridge_seq =
      saved_state.debugger_timeline
      |> Enum.find(&(&1.message == "FromBridge"))
      |> Map.fetch!(:seq)

    assert Enum.any?(saved_state.debugger_timeline, fn row ->
             row.seq < bridge_seq and String.contains?(row.message, "ProvideTemperature")
           end)

    assert Enum.any?(saved_state.debugger_timeline, fn row ->
             row.seq < bridge_seq and String.contains?(row.message, "ProvideCondition")
           end)

    refute Enum.any?(saved_state.debugger_timeline, fn row ->
             row.seq > bridge_seq and
               (String.contains?(row.message, "ProvideTemperature") or
                  String.contains?(row.message, "ProvideCondition"))
           end)
  end

  test "debugger start loads watch main when protocol tab is active", %{conn: conn} do
    previous_http_executor = Application.get_env(:ide, Ide.Debugger.HttpExecutor)

    Application.put_env(:ide, Ide.Debugger.HttpExecutor,
      request_fun: fn command ->
        url = Map.get(command, "url") || ""

        cond do
          String.contains?(url, "api.open-meteo.com") ->
            {:ok,
             %{
               "status" => 200,
               "body" =>
                 Jason.encode!(%{"current" => %{"temperature_2m" => 19.2, "weather_code" => 0}})
             }}

          true ->
            {:ok, %{"status" => 200, "body" => "ok"}}
        end
      end
    )

    on_exit(fn ->
      if is_nil(previous_http_executor) do
        Application.delete_env(:ide, Ide.Debugger.HttpExecutor)
      else
        Application.put_env(:ide, Ide.Debugger.HttpExecutor, previous_http_executor)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceDebuggerWatchMainBootstrap",
               "slug" => "workspace-debugger-watch-main-bootstrap",
               "target_type" => "app",
               "template" => "watchface-tutorial-complete"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/editor")

    render_click(view, "open-file", %{
      "source-root" => "protocol",
      "rel-path" => "src/Companion/Types.elm"
    })

    _ = render_async(view, 1_500)

    render_click(view, "debugger-start")
    _ = render_async(view, 10_000)

    assert {:ok, state} = Debugger.snapshot(project.slug, event_limit: 50)
    watch_model = get_in(state, [:watch, :model]) || %{}

    assert watch_model["last_path"] == "src/Main.elm"
    assert watch_model["source_root"] == "watch"
    assert get_in(state.companion, [:model, "elm_executor", "execution_backend"]) == "external"

    timeline =
      state.debugger_timeline
      |> Enum.sort_by(& &1.seq)
      |> Enum.map(&{&1.target, &1.message_source})

    assert {"watch", "init"} in timeline
    assert Enum.any?(timeline, &(&1 == {"watch", "init_device_data"}))
    assert Enum.any?(timeline, &(&1 == {"protocol", "protocol_rx"}))
  end

  test "editor opens watch Main elm by default", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceEditorWatchMain",
               "slug" => "workspace-editor-watch-main",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/editor")
    html = render(view)

    assert html =~ ~s(data-tab-id="watch:src/Main.elm")
    assert html =~ "src/Main.elm"
  end

  test "editor propagates settings editor mode to hook dataset", %{conn: conn} do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "workspace_editor_mode_test_#{System.unique_integer([:positive])}.json"
      )

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)
    :ok = Settings.set_editor_mode("vim")

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceEditorMode",
               "slug" => "workspace-editor-mode",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/editor")
    render_click(view, "open-file", %{"source-root" => "watch", "rel-path" => "src/Main.elm"})
    html = render_async(view, 1_500)
    assert html =~ ~s(data-editor-mode="vim")
  end

  test "editor restores saved cursor and scroll state when switching tabs", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceEditorState",
               "slug" => "workspace-editor-state",
               "target_type" => "app"
             })

    :ok =
      Projects.write_source_file(
        project,
        "watch",
        "src/Second.elm",
        "module Second exposing (main)\n\nmain =\n    \"second\"\n"
      )

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/editor")

    render_click(view, "open-file", %{"source-root" => "watch", "rel-path" => "src/Main.elm"})
    _ = render_async(view, 1_500)

    render_hook(view, "editor-state-changed", %{
      "tab_id" => "watch:src/Main.elm",
      "cursor_offset" => 42,
      "scroll_top" => 240.5,
      "scroll_left" => 12.25
    })

    render_click(view, "open-file", %{"source-root" => "watch", "rel-path" => "src/Second.elm"})
    _ = render_async(view, 1_500)

    html = render_click(view, "select-tab", %{"id" => "watch:src/Main.elm"})

    assert html =~ ~s(data-restore-cursor-offset="42")
    assert html =~ ~s(data-restore-scroll-top="240.5")
    assert html =~ ~s(data-restore-scroll-left="12.25")
    assert html =~ ~s(data-tab-id="watch:src/Main.elm")
  end

  test "editor blocks renaming and deleting protected entry and protocol files", %{conn: conn} do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WorkspaceProtectedFiles",
               "slug" => "workspace-protected-files",
               "target_type" => "app"
             })

    assert {:ok, view, _} = live(conn, ~p"/projects/#{project.slug}/editor")

    protected_files = [
      {"watch", "src/Main.elm"},
      {"phone", "src/CompanionApp.elm"},
      {"protocol", "src/Companion/Types.elm"},
      {"watch", "src/Pebble/Ui/Resources.elm"}
    ]

    for {source_root, rel_path} <- protected_files do
      render_click(view, "open-file", %{"source-root" => source_root, "rel-path" => rel_path})
      _ = render_async(view, 1_500)
      html = render(view)

      assert html =~ "Rename active file"
      assert has_element?(view, "button[disabled]", "Rename active file…")

      rename_html =
        if rel_path == "src/Pebble/Ui/Resources.elm" do
          render_click(view, "open-rename-file-modal", %{})
        else
          render_submit(view, "rename-file", %{
            "rename" => %{
              "new_rel_path" => "src/Renamed#{System.unique_integer([:positive])}.elm"
            }
          })
        end

      assert rename_html =~ "cannot be renamed" or rename_html =~ "read-only"
      assert {:ok, _} = Projects.read_source_file(project, source_root, rel_path)

      delete_html = render_click(view, "delete-file", %{})
      assert delete_html =~ "cannot be deleted" or delete_html =~ "read-only"
      assert {:ok, _} = Projects.read_source_file(project, source_root, rel_path)
    end
  end
end
