defmodule Ide.Mcp.ToolsTest do
  use Ide.DataCase, async: false

  alias Ide.Mcp.Audit
  alias Ide.Mcp.Tools
  alias Ide.Projects

  alias Ide.TestSupport.McpToolsMocks.MockCompiler
  alias Ide.TestSupport.McpToolsMocks.StructuredWarningCompiler
  alias Ide.TestSupport.McpToolsMocks.MockPackageProvider
  alias Ide.TestSupport.McpToolsMocks.MockPebbleToolchain
  alias Ide.TestSupport.McpToolsMocks.MockAppStorePublisher
  alias Ide.TestSupport.McpToolsMocks.MockScreenshots


  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_mcp_tools_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "templates.list returns catalog entries from ProjectTemplates" do
    assert {:ok, %{templates: templates}} = Tools.call("templates.list", %{}, [:read])
    assert length(templates) == length(Ide.ProjectTemplates.template_keys())

    assert Enum.any?(templates, fn entry ->
             entry.key == "companion-demo-geolocation" and entry.target_type == "watchface"
           end)
  end

  test "lists tools for provided capability scope" do
    tool_defs = Tools.tool_definitions([:read, :build])
    tool_names = Enum.map(tool_defs, & &1.name)

    assert Enum.all?(tool_names, &Regex.match?(~r/^[A-Za-z0-9_]+$/, &1))
    assert "projects_list" in tool_names
    assert "templates_list" in tool_names
    assert "projects_settings" in tool_names
    assert "files_read" in tool_names
    assert "files_stat" in tool_names
    assert "files_read_range" in tool_names
    assert "files_search" in tool_names
    assert "projects_diff" in tool_names
    assert "packages_search" in tool_names
    assert "packages_details" in tool_names
    assert "packages_versions" in tool_names
    assert "packages_readme" in tool_names
    assert "packages_module_docs" in tool_names
    assert "screenshots_list" in tool_names
    assert "screenshots_read" in tool_names
    assert "projects_graph" in tool_names
    assert "audit_recent" in tool_names
    assert "compiler_check_cached" in tool_names
    assert "compiler_check_recent" in tool_names
    assert "compiler_compile_cached" in tool_names
    assert "compiler_compile_recent" in tool_names
    assert "compiler_manifest_cached" in tool_names
    assert "compiler_manifest_recent" in tool_names
    assert "sessions_recent_activity" in tool_names
    assert "sessions_summary" in tool_names
    assert "sessions_trace_health" in tool_names
    assert "traces_bundle" in tool_names
    assert "traces_summary" in tool_names
    assert "traces_export" in tool_names
    assert "traces_exports_list" in tool_names
    assert "traces_policy" in tool_names
    assert "traces_policy_validate" in tool_names
    assert "debugger_state" in tool_names
    assert "debugger_cursor_inspect" in tool_names
    assert "debugger_render_tree" in tool_names
    assert "debugger_preview_diagnostics" in tool_names
    assert "debugger_models" in tool_names
    assert "debugger_timeline" in tool_names
    assert "debugger_surface_state" in tool_names
    assert "debugger_simulator_settings" in tool_names
    assert "debugger_configuration" in tool_names
    assert "debugger_auto_fire" in tool_names
    assert "debugger_disabled_subscriptions" in tool_names
    assert "debugger_watch_profiles" in tool_names
    assert "debugger_export_trace" in tool_names
    assert "pebble_package" in tool_names
    assert "pebble_install" in tool_names
    assert "emulator_launch" in tool_names
    assert "emulator_run" in tool_names
    assert "screenshots_capture" in tool_names
    refute "traces_export_write" in tool_names
    refute "traces_exports_prune" in tool_names
    refute "traces_maintenance" in tool_names
    refute "projects_create" in tool_names
    refute "projects_delete" in tool_names
    refute "projects_update_settings" in tool_names
    refute "debugger_start" in tool_names
    refute "debugger_reset" in tool_names
    refute "debugger_set_watch_profile" in tool_names
    refute "debugger_set_simulator_settings" in tool_names
    refute "debugger_save_configuration" in tool_names
    refute "debugger_set_auto_fire" in tool_names
    refute "debugger_set_subscription_enabled" in tool_names
    refute "debugger_import_trace" in tool_names
    refute "debugger_reload" in tool_names
    refute "debugger_step" in tool_names
    refute "debugger_tick" in tool_names
    refute "debugger_auto_tick_start" in tool_names
    refute "debugger_auto_tick_stop" in tool_names
    refute "debugger_replay_recent" in tool_names
    refute "debugger_continue_from_snapshot" in tool_names
    assert "compiler_check" in tool_names
    assert "compiler_check_source_root" in tool_names
    assert "compiler_compile" in tool_names
    assert "compiler_manifest" in tool_names
    assert "publish_prepare" in tool_names
    assert "publish_validate" in tool_names
    refute "files_write" in tool_names
    refute "files_patch" in tool_names
    refute "packages_add_to_elm_json" in tool_names
    refute "packages_remove_from_elm_json" in tool_names
    assert Enum.all?(tool_defs, &(is_binary(&1.version) and &1.version != ""))
    assert is_binary(Tools.catalog_version())

    edit_tool_names = Tools.tool_definitions([:edit]) |> Enum.map(& &1.name)
    assert "projects_update_settings" in edit_tool_names
    assert "debugger_set_simulator_settings" in edit_tool_names
    assert "debugger_save_configuration" in edit_tool_names
    assert "debugger_set_auto_fire" in edit_tool_names
    assert "debugger_set_subscription_enabled" in edit_tool_names
  end

  test "publish tools are capability scoped" do
    tool_defs = Tools.tool_definitions([:publish])
    tool_names = Enum.map(tool_defs, & &1.name)
    assert "publish_submit" in tool_names
    refute "publish_prepare" in tool_names
    refute "publish_validate" in tool_names

    assert {:error, reason} =
             Tools.call(
               "compiler.check",
               %{"slug" => "any"},
               [:publish]
             )

    assert String.contains?(reason, "not permitted")
  end

  test "project mutation and Pebble workflow tools enforce capabilities and return payloads" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)

    Application.put_env(:ide, Ide.Mcp.Tools,
      pebble_toolchain_module: MockPebbleToolchain,
      app_store_publisher_module: MockAppStorePublisher,
      screenshots_module: MockScreenshots
    )

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:error, create_denied} =
             Tools.call("projects.create", %{"name" => "Nope", "slug" => "nope"}, [:read])

    assert String.contains?(create_denied, "not permitted")

    assert {:ok, created} =
             Tools.call(
               "projects.create",
               %{
                 "name" => "McpMutate",
                 "slug" => "mcp-mutate",
                 "target_type" => "app",
                 "template" => "starter"
               },
               [:edit]
             )

    assert created.slug == "mcp-mutate"
    assert created.target_type == "app"

    assert {:error, package_denied} =
             Tools.call("pebble.package", %{"slug" => "mcp-mutate"}, [:read])

    assert String.contains?(package_denied, "not permitted")

    assert {:ok, packaged} = Tools.call("pebble.package", %{"slug" => "mcp-mutate"}, [:build])
    assert String.ends_with?(packaged.artifact_path, "mock-app.pbw")
    assert packaged.status == :ok

    assert {:ok, installed} =
             Tools.call(
               "pebble.install",
               %{"slug" => "mcp-mutate", "emulator_target" => "chalk"},
               [:build]
             )

    assert installed.slug == "mcp-mutate"
    assert String.ends_with?(installed.artifact_path, "mock-app.pbw")
    assert installed.install_result.status == :ok
    assert installed.install_result.exit_code == 0

    assert {:ok, screenshots} =
             Tools.call(
               "screenshots.list",
               %{"slug" => "mcp-mutate"},
               [:read]
             )

    assert screenshots.slug == "mcp-mutate"
    assert screenshots.count == 2
    mock_screenshot_root = Path.join(System.tmp_dir!(), "ide_mcp_mock_screenshots")
    chalk_screenshot_path = Path.join([mock_screenshot_root, "chalk", "shot-new.png"])
    basalt_screenshot_path = Path.join([mock_screenshot_root, "basalt", "shot-old.png"])

    assert [
             %{
               filename: "shot-new.png",
               target_device: "chalk",
               emulator_target: "chalk",
               captured_at: "2026-01-01 00:00:01",
               timestamp: "2026-01-01 00:00:01",
               mime_type: "image/png",
               url: "/screenshots/mock/chalk/shot-new.png",
               absolute_path: ^chalk_screenshot_path
             },
             %{
               filename: "shot-old.png",
               target_device: "basalt",
               emulator_target: "basalt",
               captured_at: "2026-01-01 00:00:00",
               timestamp: "2026-01-01 00:00:00",
               mime_type: "image/png",
               url: "/screenshots/mock/basalt/shot-old.png",
               absolute_path: ^basalt_screenshot_path
             }
           ] = screenshots.screenshots

    assert {:ok, screenshot_data} =
             Tools.call(
               "screenshots.read",
               %{
                 "slug" => "mcp-mutate",
                 "emulator_target" => "chalk",
                 "filename" => "shot-new.png"
               },
               [:read]
             )

    expected_png = <<137, 80, 78, 71, 13, 10, 26, 10, "new">>
    assert screenshot_data.slug == "mcp-mutate"
    assert screenshot_data.screenshot.filename == "shot-new.png"
    assert screenshot_data.screenshot.target_device == "chalk"
    assert screenshot_data.mime_type == "image/png"
    assert screenshot_data.encoding == "base64"
    assert screenshot_data.bytes == byte_size(expected_png)

    assert screenshot_data.sha256 ==
             Base.encode16(:crypto.hash(:sha256, expected_png), case: :lower)

    assert screenshot_data.content_base64 == Base.encode64(expected_png)

    assert {:error, read_denied} =
             Tools.call(
               "screenshots.read",
               %{
                 "slug" => "mcp-mutate",
                 "emulator_target" => "chalk",
                 "filename" => "shot-new.png"
               },
               [:publish]
             )

    assert String.contains?(read_denied, "not permitted")

    assert {:ok, screenshot} =
             Tools.call(
               "screenshots.capture",
               %{"slug" => "mcp-mutate", "emulator_target" => "chalk"},
               [:build]
             )

    assert screenshot.slug == "mcp-mutate"
    assert screenshot.screenshot.emulator_target == "chalk"
    assert screenshot.exit_code == 0

    assert {:error, delete_denied} =
             Tools.call("projects.delete", %{"slug" => "mcp-mutate"}, [:read])

    assert String.contains?(delete_denied, "not permitted")

    assert {:ok, %{slug: "mcp-mutate", deleted: true}} =
             Tools.call("projects.delete", %{"slug" => "mcp-mutate"}, [:edit])
  end

  test "publish MCP tools prepare validate and submit release" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    previous_manifest_env = Application.get_env(:ide, Ide.PublishManifest)

    output_root =
      Path.join(System.tmp_dir!(), "ide_mcp_publish_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Mcp.Tools,
      pebble_toolchain_module: MockPebbleToolchain,
      app_store_publisher_module: MockAppStorePublisher,
      screenshots_module: MockScreenshots
    )

    Application.put_env(:ide, Ide.PublishManifest, output_root: output_root)

    on_exit(fn ->
      File.rm_rf(output_root)

      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end

      if previous_manifest_env == nil do
        Application.delete_env(:ide, Ide.PublishManifest)
      else
        Application.put_env(:ide, Ide.PublishManifest, previous_manifest_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpPublish",
               "slug" => "mcp-publish",
               "target_type" => "app",
               "release_defaults" => %{"target_platforms" => ["basalt", "chalk"]}
             })

    assert {:error, denied} =
             Tools.call("publish.submit", %{"slug" => project.slug}, [:build])

    assert denied =~ "not permitted"

    assert {:ok, validated} =
             Tools.call("publish.validate", %{"slug" => project.slug}, [:build])

    assert validated.status == :ok
    assert Enum.all?(validated.readiness, &(&1.status == :ok))

    assert {:ok, prepared} =
             Tools.call("publish.prepare", %{"slug" => project.slug}, [:build])

    assert prepared.status == :ok
    assert File.exists?(prepared.manifest_path)
    assert File.exists?(prepared.release_notes_path)

    assert {:ok, submitted} =
             Tools.call("publish.submit", %{"slug" => project.slug}, [:publish])

    assert submitted.status == :ok
    assert submitted.command =~ "native appstore publish"
  end

  test "project settings tools expose only safe persisted settings" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpSettings",
               "slug" => "mcp-settings",
               "target_type" => "app"
             })

    assert {:error, denied} =
             Tools.call(
               "projects.update_settings",
               %{"slug" => project.slug, "name" => "Denied"},
               [:read]
             )

    assert String.contains?(denied, "not permitted")

    assert {:ok, settings} = Tools.call("projects.settings", %{"slug" => project.slug}, [:read])
    assert settings.name == "McpSettings"
    assert settings.debugger["simulator"]["latitude"] == 48.137154

    assert {:ok, updated} =
             Tools.call(
               "projects.update_settings",
               %{
                 "slug" => project.slug,
                 "name" => "Mcp Settings Updated",
                 "release_defaults" => %{
                   "version_label" => "1.2.3",
                   "target_platforms" => ["basalt", "chalk"]
                 },
                 "github" => %{"owner" => "ape", "repo" => "elm-pebble", "token" => "secret"},
                 "debugger" => %{
                   "emulator_target" => "chalk",
                   "emulator_mode" => "embedded",
                   "unsafe_key" => "ignored"
                 }
               },
               [:edit]
             )

    assert updated.name == "Mcp Settings Updated"
    assert updated.release_defaults["version_label"] == "1.2.3"
    assert updated.github == %{"owner" => "ape", "repo" => "elm-pebble"}
    assert updated.debugger["emulator_target"] == "chalk"
    refute Map.has_key?(updated.debugger, "unsafe_key")

    reloaded = Projects.get_project_by_slug(project.slug)
    assert reloaded.name == "Mcp Settings Updated"
    assert reloaded.github == %{"owner" => "ape", "repo" => "elm-pebble"}
    assert reloaded.debugger_settings["emulator_mode"] == "embedded"
  end

  test "debugger settings tools persist and apply simulator and subscription controls" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpDebuggerSettings",
               "slug" => "mcp-debugger-settings",
               "target_type" => "watchface"
             })

    assert {:error, denied} =
             Tools.call(
               "debugger.set_simulator_settings",
               %{"slug" => project.slug, "settings" => %{"battery_percent" => 25}},
               [:read]
             )

    assert String.contains?(denied, "not permitted")

    assert {:ok, %{settings: simulator}} =
             Tools.call(
               "debugger.set_simulator_settings",
               %{
                 "slug" => project.slug,
                 "settings" => %{
                   "battery_percent" => 12,
                   "charging" => true,
                   "connected" => false,
                   "clock_24h" => true,
                   "use_simulated_time" => true,
                   "simulated_time" => "07:08:09",
                   "simulated_date" => "2026-05-19",
                   "latitude" => "49.0",
                   "longitude" => 8,
                   "accuracy" => 40
                 }
               },
               [:edit]
             )

    assert simulator["battery_percent"] == 12
    assert simulator["charging"] == true
    assert simulator["use_simulated_time"] == true
    assert simulator["simulated_time"] == "07:08:09"
    assert simulator["simulated_date"] == "2026-05-19"
    assert simulator["longitude"] == 8.0

    assert {:ok, read_back} =
             Tools.call("debugger.simulator_settings", %{"slug" => project.slug}, [:read])

    assert read_back.settings["latitude"] == 49.0
    assert read_back.persisted_settings == simulator

    assert {:ok, %{values: values}} =
             Tools.call(
               "debugger.save_configuration",
               %{"slug" => project.slug, "values" => %{"mode" => "agent", "color" => ["red"]}},
               [:edit]
             )

    assert values == %{"mode" => "agent", "color" => "red"}

    assert {:ok, configuration} =
             Tools.call("debugger.configuration", %{"slug" => project.slug}, [:read])

    assert configuration.values == values

    assert {:ok, auto_fire} =
             Tools.call(
               "debugger.set_auto_fire",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "trigger" => "Time.every",
                 "enabled" => true
               },
               [:edit]
             )

    assert [%{"target" => "watch", "trigger" => "Time.every"}] =
             auto_fire.auto_fire_subscriptions

    assert {:ok, disabled} =
             Tools.call(
               "debugger.set_subscription_enabled",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "trigger" => "Time.every",
                 "enabled" => false
               },
               [:edit]
             )

    assert [%{"target" => "watch", "trigger" => "Time.every"}] =
             disabled.disabled_subscriptions

    reloaded = Projects.get_project_by_slug(project.slug)
    assert reloaded.debugger_settings["simulator"]["battery_percent"] == 12
    assert reloaded.debugger_settings["configuration_values"] == values

    assert reloaded.debugger_settings["auto_fire_subscriptions"] == [
             %{"target" => "watch", "trigger" => "Time.every"}
           ]

    assert reloaded.debugger_settings["disabled_subscriptions"] == [
             %{"target" => "watch", "trigger" => "Time.every"}
           ]
  end



  test "package tools browse and add dependencies via mcp" do
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

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpPackages",
               "slug" => "mcp-packages",
               "target_type" => "app"
             })

    assert {:ok, %{packages: [pkg]}} =
             Tools.call("packages.search", %{"query" => "elm/http"}, [:read])

    assert pkg.name == "elm/http"

    assert {:ok, %{packages: [published_name_pkg]}} =
             Tools.call("packages_search", %{"query" => "elm/http"}, [:read])

    assert published_name_pkg.name == "elm/http"

    assert {:ok, %{name: "elm/http", compatibility: compatibility}} =
             Tools.call("packages.details", %{"package" => "elm/http"}, [:read])

    assert compatibility.status == "blocked"
    assert compatibility.reason_code == "blocked_runtime_family"

    assert {:ok, %{versions: ["2.0.0"]}} =
             Tools.call("packages.versions", %{"package" => "elm/http"}, [:read])

    assert {:ok, %{readme: "# elm/http latest"}} =
             Tools.call("packages.readme", %{"package" => "elm/http"}, [:read])

    assert {:ok, %{markdown: markdown}} =
             Tools.call(
               "packages.module_docs",
               %{
                 "package" => "elm-pebble/companion-core",
                 "module" => "Pebble.Companion.Battery"
               },
               [:read]
             )

    assert String.contains?(markdown, "Phone battery helpers")
    assert String.contains?(markdown, "current phone battery status")

    assert {:error, reason} =
             Tools.call(
               "packages.add_to_elm_json",
               %{"slug" => project.slug, "package" => "elm/http"},
               [:read]
             )

    assert String.contains?(reason, "not permitted")

    assert {:ok, %{slug: "mcp-packages", package: "elm/http", selected_version: "2.0.0"}} =
             Tools.call(
               "packages.add_to_elm_json",
               %{"slug" => project.slug, "package" => "elm/http", "source_root" => "watch"},
               [:edit]
             )

    assert {:ok, %{content: content}} =
             Tools.call(
               "files.read",
               %{"slug" => project.slug, "source_root" => "watch", "rel_path" => "elm.json"},
               [:read]
             )

    assert String.contains?(content, "\"elm/http\": \"2.0.0\"")

    assert {:ok, %{slug: "mcp-packages", package: "elm/http"}} =
             Tools.call(
               "packages.remove_from_elm_json",
               %{"slug" => project.slug, "package" => "elm/http", "source_root" => "watch"},
               [:edit]
             )

    assert {:ok, %{content: content_after}} =
             Tools.call(
               "files.read",
               %{"slug" => project.slug, "source_root" => "watch", "rel_path" => "elm.json"},
               [:read]
             )

    refute String.contains?(content_after, "\"elm/http\"")
  end

  test "reads and writes files with capability checks" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTools",
               "slug" => "mcp-tools",
               "target_type" => "app"
             })

    assert {:ok, %{saved: true}} =
             Tools.call(
               "files.write",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm",
                 "content" => """
                 module Main exposing (main)

                 main =
                     "hello"
                 """
               },
               [:edit]
             )

    assert {:ok, %{content: content}} =
             Tools.call(
               "files.read",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm"
               },
               [:read]
             )

    assert String.contains?(content, "module Main")

    assert {:ok, stat} =
             Tools.call(
               "files.stat",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm"
               },
               [:read]
             )

    assert stat.bytes == byte_size(content)
    assert stat.sha256 == Base.encode16(:crypto.hash(:sha256, content), case: :lower)
    assert is_binary(stat.mtime)

    assert {:ok, range} =
             Tools.call(
               "files.read_range",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm",
                 "offset" => 3,
                 "limit" => 2
               },
               [:read]
             )

    assert range.total_lines >= 4
    assert [%{line: 3, text: "main ="}, %{line: 4, text: "    \"hello\""}] = range.lines

    assert {:ok, search} =
             Tools.call(
               "files.search",
               %{"slug" => project.slug, "source_root" => "watch", "query" => "hello"},
               [:read]
             )

    assert [%{source_root: "watch", rel_path: "src/Main.elm", line: 4}] = search.matches

    assert {:ok, patched} =
             Tools.call(
               "files.patch",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm",
                 "old_string" => "\"hello\"",
                 "new_string" => "\"patched\"",
                 "expected_sha256" => stat.sha256
               },
               [:edit]
             )

    assert patched.old_sha256 == stat.sha256
    assert patched.new_sha256 != stat.sha256

    assert {:ok, %{content: patched_content}} =
             Tools.call(
               "files.read",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm"
               },
               [:read]
             )

    assert String.contains?(patched_content, "\"patched\"")

    assert {:error, stale_reason} =
             Tools.call(
               "files.patch",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Main.elm",
                 "old_string" => "\"patched\"",
                 "new_string" => "\"stale\"",
                 "expected_sha256" => stat.sha256
               },
               [:edit]
             )

    assert String.contains?(stale_reason, "stale_file")

    assert {:ok, diff} = Tools.call("projects.diff", %{"slug" => project.slug}, [:read])
    assert diff.slug == project.slug
    assert is_binary(diff.diff)

    assert {:error, reason} =
             Tools.call(
               "files.write",
               %{
                 "slug" => project.slug,
                 "source_root" => "watch",
                 "rel_path" => "src/Denied.elm",
                 "content" => "module Denied exposing (..)"
               },
               [:read]
             )

    assert String.contains?(reason, "not permitted")
  end

  test "returns project graph and recent audit entries" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpGraph",
               "slug" => "mcp-graph",
               "target_type" => "app"
             })

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "src/Main.elm",
               "module Main exposing (main)"
             )

    assert {:ok, %{projects: projects}} = Tools.call("projects.graph", %{}, [:read])
    assert Enum.any?(projects, &(&1.slug == "mcp-graph" and &1.file_count >= 1))

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_test",
        action: "files.read",
        status: "ok"
      })

    assert {:ok, %{entries: entries}} = Tools.call("audit.recent", %{"limit" => 10}, [:read])
    assert Enum.any?(entries, &(&1["trace_id"] == "trace_test"))
  end

  test "compiler check is cached and exposed as context" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpCheck",
               "slug" => "mcp-check",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-check", error_count: error_count, warning_count: warning_count}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    assert is_integer(error_count)
    assert is_integer(warning_count)

    assert {:ok, %{slug: "mcp-check", source_root: "watch", error_count: root_error_count}} =
             Tools.call(
               "compiler.check_source_root",
               %{"slug" => project.slug, "source_root" => "watch"},
               [:build]
             )

    assert is_integer(root_error_count)

    assert {:ok, %{cached: true, slug: "mcp-check", result: result}} =
             Tools.call("compiler.check_cached", %{"slug" => project.slug}, [:read])

    assert result[:status] in [:ok, :error]

    assert {:ok, %{entries: entries}} =
             Tools.call("compiler.check_recent", %{"slug" => project.slug, "limit" => 5}, [:read])

    assert Enum.any?(entries, &(&1.slug == "mcp-check"))
  end

  test "compiler check exposes structured lowerer warning fields" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: StructuredWarningCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpStructuredWarning",
               "slug" => "mcp-structured-warning",
               "target_type" => "app"
             })

    assert {:ok,
            %{diagnostics: [diag | _], error_count: error_count, warning_count: warning_count}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    assert diag.warning_type == "lowerer-warning"
    assert diag.warning_code == "constructor_payload_arity"
    assert diag.warning_constructor == "Wrap"
    assert diag.warning_expected_kind == "single"
    assert diag.warning_has_arg_pattern == false
    assert error_count == 0
    assert warning_count == 1
  end

  test "audit arguments redact file content for files.write" do
    args = %{
      "slug" => "demo",
      "source_root" => "watch",
      "rel_path" => "src/Main.elm",
      "content" => "abc"
    }

    redacted = Tools.audit_arguments("files.write", args)

    refute Map.has_key?(redacted, "content")
    assert redacted["content_redacted"] == true
    assert redacted["content_bytes"] == 3
    assert redacted["slug"] == "demo"
  end

  test "audit arguments redact patch content for files.patch" do
    args = %{
      "slug" => "demo",
      "source_root" => "watch",
      "rel_path" => "src/Main.elm",
      "old_string" => "before",
      "new_string" => "after"
    }

    redacted = Tools.audit_arguments("files.patch", args)

    refute Map.has_key?(redacted, "old_string")
    refute Map.has_key?(redacted, "new_string")
    assert redacted["old_string_redacted"] == true
    assert redacted["old_string_bytes"] == 6
    assert redacted["new_string_redacted"] == true
    assert redacted["new_string_bytes"] == 5
    assert redacted["slug"] == "demo"
  end

  test "sessions recent activity aggregates checks and actions" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpSession",
               "slug" => "mcp-session",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-session"}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    assert {:ok, %{strict: true}} =
             Tools.call("compiler.manifest", %{"slug" => project.slug, "strict" => true}, [:build])

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_session",
        action: "files.read",
        status: "ok",
        arguments: %{
          "slug" => project.slug,
          "source_root" => "watch",
          "rel_path" => "src/Main.elm"
        }
      })

    assert {:ok, %{projects: [activity]}} =
             Tools.call("sessions.recent_activity", %{"slug" => project.slug, "limit" => 5}, [
               :read
             ])

    assert activity.slug == "mcp-session"
    assert is_integer(activity.screenshot_count)
    assert is_list(activity.recent_checks)
    assert is_map(activity.latest_check) or is_nil(activity.latest_check)
    assert activity.latest_manifest_strict == true
    assert Enum.any?(activity.recent_actions, &(&1["trace_id"] == "trace_session"))
  end

  test "recent context tools honor since filter" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpSince",
               "slug" => "mcp-since",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-since"}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    :ok =
      Audit.append(%{
        at: "2020-01-01T00:00:00Z",
        trace_id: "trace_old",
        action: "files.read",
        status: "ok",
        arguments: %{"slug" => project.slug}
      })

    future = "2999-01-01T00:00:00Z"

    assert {:ok, %{entries: []}} =
             Tools.call(
               "audit.recent",
               %{"slug" => project.slug, "limit" => 20, "since" => future},
               [:read]
             )

    assert {:ok, %{entries: []}} =
             Tools.call(
               "compiler.check_recent",
               %{"slug" => project.slug, "limit" => 20, "since" => future},
               [:read]
             )

    assert {:ok, %{projects: [activity]}} =
             Tools.call(
               "sessions.recent_activity",
               %{"slug" => project.slug, "limit" => 20, "since" => future},
               [:read]
             )

    assert activity.recent_checks == []
    assert activity.recent_actions == []
    assert is_nil(activity.latest_check)
  end

  test "sessions summary returns compact status view" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpSummary",
               "slug" => "mcp-summary",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-summary"}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_summary",
        action: "files.read",
        status: "ok",
        arguments: %{"slug" => project.slug}
      })

    assert {:ok, %{projects: [summary]}} =
             Tools.call("sessions.summary", %{"slug" => project.slug}, [:read])

    assert summary.slug == "mcp-summary"
    assert summary.latest_check_status in [:ok, :error, nil]

    assert {:ok, %{strict: true}} =
             Tools.call("compiler.manifest", %{"slug" => project.slug, "strict" => true}, [:build])

    assert {:ok, %{projects: [summary_with_manifest]}} =
             Tools.call("sessions.summary", %{"slug" => project.slug}, [:read])

    assert summary_with_manifest.latest_manifest_strict == true
    assert is_integer(summary.checks_count)
    assert is_integer(summary.actions_count)
    assert is_integer(summary.screenshots_count)
  end

  test "compiler compile tool executes through build capability" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpCompile",
               "slug" => "mcp-compile",
               "target_type" => "app"
             })

    assert {:ok,
            %{
              slug: "mcp-compile",
              status: status,
              output: output,
              error_count: error_count,
              warning_count: warning_count
            }} =
             Tools.call("compiler.compile", %{"slug" => project.slug}, [:build])

    assert status in [:ok, :error]
    assert is_binary(output)
    assert is_integer(error_count)
    assert is_integer(warning_count)

    assert {:ok, %{cached: true, slug: "mcp-compile", result: cached_result}} =
             Tools.call("compiler.compile_cached", %{"slug" => project.slug}, [:read])

    assert cached_result[:status] in [:ok, :error]

    assert {:ok, %{entries: compile_entries}} =
             Tools.call("compiler.compile_recent", %{"slug" => project.slug, "limit" => 5}, [
               :read
             ])

    assert Enum.any?(compile_entries, &(&1.slug == "mcp-compile"))
  end

  test "compiler manifest tool executes through build capability" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpManifest",
               "slug" => "mcp-manifest",
               "target_type" => "app"
             })

    assert {:ok,
            %{
              slug: "mcp-manifest",
              status: status,
              output: output,
              strict: false,
              error_count: error_count,
              warning_count: warning_count
            }} =
             Tools.call("compiler.manifest", %{"slug" => project.slug}, [:build])

    assert status in [:ok, :error]
    assert is_binary(output)
    assert is_integer(error_count)
    assert is_integer(warning_count)

    assert {:ok, %{cached: true, slug: "mcp-manifest", result: cached_result}} =
             Tools.call("compiler.manifest_cached", %{"slug" => project.slug}, [:read])

    assert cached_result[:status] in [:ok, :error]

    assert {:ok, %{entries: manifest_entries}} =
             Tools.call("compiler.manifest_recent", %{"slug" => project.slug, "limit" => 5}, [
               :read
             ])

    assert Enum.any?(manifest_entries, &(&1.slug == "mcp-manifest"))

    assert {:ok, %{slug: "mcp-manifest", strict: true, status: strict_status}} =
             Tools.call("compiler.manifest", %{"slug" => project.slug, "strict" => true}, [:build])

    assert strict_status in [:ok, :error]
  end

  test "traces bundle returns correlated audit and compiler context" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTrace",
               "slug" => "mcp-trace",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-trace"}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    assert {:ok, %{strict: true}} =
             Tools.call("compiler.manifest", %{"slug" => project.slug, "strict" => true}, [:build])

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_bundle",
        action: "files.read",
        status: "ok",
        arguments: %{
          "slug" => project.slug,
          "source_root" => "watch",
          "rel_path" => "src/Main.elm"
        }
      })

    assert {:ok, payload} =
             Tools.call(
               "traces.bundle",
               %{"trace_id" => "trace_bundle", "slug" => project.slug, "limit" => 10},
               [:read]
             )

    assert payload.trace_id == "trace_bundle"
    assert payload.slug == "mcp-trace"
    assert Enum.any?(payload.audit_entries, &(&1["trace_id"] == "trace_bundle"))
    assert payload.compiler_context.latest.check.slug == "mcp-trace"
    assert payload.compiler_context.latest.manifest.slug == "mcp-trace"
    assert payload.compiler_context.latest.manifest.result[:strict?] == true
  end

  test "traces summary returns compact counters and statuses" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTraceSummary",
               "slug" => "mcp-trace-summary",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-trace-summary"}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    assert {:ok, %{strict: true}} =
             Tools.call("compiler.manifest", %{"slug" => project.slug, "strict" => true}, [:build])

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_summary_bundle",
        action: "compiler.manifest",
        status: "ok",
        arguments: %{"slug" => project.slug, "strict" => true}
      })

    assert {:ok, payload} =
             Tools.call(
               "traces.summary",
               %{"trace_id" => "trace_summary_bundle", "slug" => project.slug, "limit" => 10},
               [:read]
             )

    assert payload.trace_id == "trace_summary_bundle"
    assert payload.slug == "mcp-trace-summary"
    assert payload.window.audit_entries >= 1
    assert payload.latest_status.check in [:ok, :error]
    assert payload.latest_status.manifest in [:ok, :error]
    assert payload.latest_status.manifest_strict == true
    assert Enum.any?(payload.actions, &(&1.action == "compiler.manifest"))
  end

  test "traces export returns deterministic json payload and checksum" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTraceExport",
               "slug" => "mcp-trace-export",
               "target_type" => "app"
             })

    assert {:ok, %{slug: "mcp-trace-export"}} =
             Tools.call("compiler.check", %{"slug" => project.slug}, [:build])

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_export",
        action: "compiler.check",
        status: "ok",
        arguments: %{"slug" => project.slug}
      })

    assert {:ok, first} =
             Tools.call(
               "traces.export",
               %{"trace_id" => "trace_export", "slug" => project.slug, "limit" => 10},
               [:read]
             )

    assert {:ok, second} =
             Tools.call(
               "traces.export",
               %{"trace_id" => "trace_export", "slug" => project.slug, "limit" => 10},
               [:read]
             )

    assert first.export_json == second.export_json
    assert first.export_sha256 == second.export_sha256
    assert is_binary(first.export_json)
    assert String.starts_with?(first.export_json, "{")
    assert byte_size(first.export_sha256) == 64
  end

  test "traces export_write persists deterministic export with edit capability" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTraceWrite",
               "slug" => "mcp-trace-write",
               "target_type" => "app"
             })

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_write",
        action: "compiler.check",
        status: "ok",
        arguments: %{"slug" => project.slug}
      })

    assert {:error, reason} =
             Tools.call(
               "traces.export_write",
               %{"trace_id" => "trace_write", "slug" => project.slug},
               [
                 :read
               ]
             )

    assert String.contains?(reason, "not permitted")

    assert {:ok, result} =
             Tools.call(
               "traces.export_write",
               %{"trace_id" => "trace_write", "slug" => project.slug},
               [
                 :edit
               ]
             )

    assert result.trace_id == "trace_write"
    assert result.slug == "mcp-trace-write"
    assert byte_size(result.export_sha256) == 64
    assert result.bytes > 0

    assert {:ok, file_body} = File.read(result.path)
    assert String.starts_with?(file_body, "{")
  end

  test "trace exports can be listed and pruned" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTraceGc",
               "slug" => "mcp-trace-gc",
               "target_type" => "app"
             })

    for trace_id <- ["trace_gc_1", "trace_gc_2", "trace_gc_3"] do
      :ok =
        Audit.append(%{
          at: "2026-01-01T00:00:00Z",
          trace_id: trace_id,
          action: "compiler.check",
          status: "ok",
          arguments: %{"slug" => project.slug}
        })

      assert {:ok, _result} =
               Tools.call(
                 "traces.export_write",
                 %{"trace_id" => trace_id, "slug" => project.slug},
                 [:edit]
               )
    end

    assert {:ok, %{entries: entries_before}} =
             Tools.call("traces.exports_list", %{"limit" => 200}, [:read])

    assert length(entries_before) >= 3

    assert {:ok, %{deleted_count: deleted_count, remaining_count: remaining_count}} =
             Tools.call("traces.exports_prune", %{"keep_latest" => 1}, [:edit])

    assert deleted_count >= 2
    assert remaining_count >= 1

    assert {:ok, %{entries: entries_after}} =
             Tools.call("traces.exports_list", %{"limit" => 200}, [:read])

    assert length(entries_after) >= 1
    assert length(entries_after) <= length(entries_before)
  end

  test "sessions.trace_health reports storage metrics and recommendations" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTraceHealth",
               "slug" => "mcp-trace-health",
               "target_type" => "app"
             })

    :ok =
      Audit.append(%{
        at: "2026-01-01T00:00:00Z",
        trace_id: "trace_health",
        action: "compiler.check",
        status: "ok",
        arguments: %{"slug" => project.slug}
      })

    assert {:ok, _write_result} =
             Tools.call(
               "traces.export_write",
               %{"trace_id" => "trace_health", "slug" => project.slug},
               [
                 :edit
               ]
             )

    assert {:ok, payload} =
             Tools.call("sessions.trace_health", %{"warn_count" => 1, "warn_bytes" => 1}, [:read])

    assert payload.status in ["ok", "warn"]
    assert is_integer(payload.trace_exports.total_count)
    assert is_integer(payload.trace_exports.total_bytes)
    assert payload.trace_exports.total_count >= 1
    assert payload.suggested_keep_latest >= 1
    assert is_binary(payload.recommendation)
    assert payload.policy_validation.status in ["ok", "warn", "error"]
    assert is_list(payload.policy_validation.findings)
  end

  test "trace policy defaults are used when args omitted" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)

    merged_env =
      (previous_tools_env || [])
      |> Keyword.put(:compiler_module, MockCompiler)
      |> Keyword.put(:trace_policy,
        warn_count: 1,
        warn_bytes: 1,
        keep_latest: 1,
        target_keep_latest: 1
      )

    Application.put_env(:ide, Ide.Mcp.Tools, merged_env)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTracePolicy",
               "slug" => "mcp-trace-policy",
               "target_type" => "app"
             })

    for trace_id <- ["trace_policy_1", "trace_policy_2"] do
      :ok =
        Audit.append(%{
          at: "2026-01-01T00:00:00Z",
          trace_id: trace_id,
          action: "compiler.check",
          status: "ok",
          arguments: %{"slug" => project.slug}
        })

      assert {:ok, _written} =
               Tools.call(
                 "traces.export_write",
                 %{"trace_id" => trace_id, "slug" => project.slug},
                 [:edit]
               )
    end

    assert {:ok, health} = Tools.call("sessions.trace_health", %{}, [:read])
    assert health.thresholds.warn_count == 1
    assert health.thresholds.warn_bytes == 1
    assert health.status == "warn"

    assert {:ok, maintenance} = Tools.call("traces.maintenance", %{"apply" => true}, [:edit])
    assert maintenance.target_keep_latest == 1
    assert maintenance.health_after.trace_exports.total_count <= 1
  end

  test "traces.policy exposes configured and effective defaults" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)

    Application.put_env(:ide, Ide.Mcp.Tools,
      trace_policy: [
        warn_count: 123,
        warn_bytes: 456,
        keep_latest: 7,
        target_keep_latest: 8
      ]
    )

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, policy} = Tools.call("traces.policy", %{}, [:read])
    assert policy.configured.warn_count == 123
    assert policy.configured.warn_bytes == 456
    assert policy.configured.keep_latest == 7
    assert policy.configured.target_keep_latest == 8
    assert policy.effective.warn_count == 123
    assert policy.effective.warn_bytes == 456
    assert policy.effective.keep_latest == 7
    assert policy.effective.target_keep_latest == 8

    assert {:error, reason} = Tools.call("traces.policy", %{}, [:edit])
    assert String.contains?(reason, "not permitted")
  end

  test "traces.policy_validate reports safety findings for risky defaults" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)

    Application.put_env(:ide, Ide.Mcp.Tools,
      trace_policy: [
        warn_count: 5,
        warn_bytes: 100,
        keep_latest: 10,
        target_keep_latest: 12
      ]
    )

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, payload} = Tools.call("traces.policy_validate", %{}, [:read])
    assert payload.status == "warn"
    assert Enum.any?(payload.findings, &(&1.code == "target_keep_exceeds_keep"))
    assert Enum.any?(payload.findings, &(&1.code == "keep_exceeds_warn_count"))
    assert Enum.any?(payload.findings, &(&1.code == "warn_bytes_low"))

    assert {:error, reason} = Tools.call("traces.policy_validate", %{}, [:edit])
    assert String.contains?(reason, "not permitted")
  end

  test "traces.maintenance supports dry run and apply modes" do
    previous_tools_env = Application.get_env(:ide, Ide.Mcp.Tools)
    Application.put_env(:ide, Ide.Mcp.Tools, compiler_module: MockCompiler)

    on_exit(fn ->
      if previous_tools_env == nil do
        Application.delete_env(:ide, Ide.Mcp.Tools)
      else
        Application.put_env(:ide, Ide.Mcp.Tools, previous_tools_env)
      end
    end)

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpTraceMaintenance",
               "slug" => "mcp-trace-maintenance",
               "target_type" => "app"
             })

    for trace_id <- ["trace_maint_1", "trace_maint_2", "trace_maint_3"] do
      :ok =
        Audit.append(%{
          at: "2026-01-01T00:00:00Z",
          trace_id: trace_id,
          action: "compiler.check",
          status: "ok",
          arguments: %{"slug" => project.slug}
        })

      assert {:ok, _written} =
               Tools.call(
                 "traces.export_write",
                 %{"trace_id" => trace_id, "slug" => project.slug},
                 [
                   :edit
                 ]
               )
    end

    assert {:error, reason} =
             Tools.call("traces.maintenance", %{"warn_count" => 1, "apply" => false}, [:read])

    assert String.contains?(reason, "not permitted")

    assert {:ok, dry_run} =
             Tools.call(
               "traces.maintenance",
               %{
                 "warn_count" => 1,
                 "warn_bytes" => 1,
                 "target_keep_latest" => 1,
                 "apply" => false
               },
               [:edit]
             )

    assert dry_run.mode == "dry_run"
    assert dry_run.status == "no_change"
    assert dry_run.prune.deleted_count == 0
    assert dry_run.health_before.trace_exports.total_count >= 1
    assert dry_run.policy_validation.status in ["ok", "warn", "error"]
    assert is_list(dry_run.policy_validation.findings)

    assert {:ok, apply_run} =
             Tools.call(
               "traces.maintenance",
               %{
                 "warn_count" => 1,
                 "warn_bytes" => 1,
                 "target_keep_latest" => 1,
                 "apply" => true
               },
               [:edit]
             )

    assert apply_run.mode == "apply"
    assert apply_run.status in ["pruned", "no_change"]
    assert apply_run.policy_validation.status in ["ok", "warn", "error"]
    assert is_list(apply_run.policy_validation.findings)

    assert apply_run.health_after.trace_exports.total_count <=
             apply_run.health_before.trace_exports.total_count
  end





  test "vector resource tools convert, import, list, preview, and delete" do
    slug = "mcp-vectors-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             Tools.call(
               "projects.create",
               %{
                 "name" => "Vectors",
                 "slug" => slug,
                 "target_type" => "watchface",
                 "template" => "starter"
               },
               [:edit]
             )

    svg =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect x="2" y="2" width="16" height="16" fill="black"/></svg>)

    assert {:ok, converted} =
             Tools.call(
               "resources.vectors.convert",
               %{"svg" => svg, "color_mode" => "truncate"},
               [:read]
             )

    assert converted["magic"] == "PDCI"
    assert is_binary(converted["bytes_base64"])
    assert converted["report"]["stats"]["commands"] == 1

    frame_a =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect x="1" y="1" width="4" height="4" fill="black"/></svg>)

    frame_b =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect x="5" y="5" width="4" height="4" fill="black"/></svg>)

    assert {:ok, sequence} =
             Tools.call(
               "resources.vectors.convert_sequence",
               %{"frames" => [frame_a, frame_b], "frame_duration_ms" => 80},
               [:read]
             )

    assert sequence["magic"] == "PDCS"
    assert sequence["frame_count"] == 2

    assert {:ok, imported} =
             Tools.call(
               "resources.vectors.import",
               %{"slug" => slug, "svg" => svg, "name" => "Square.svg"},
               [:edit]
             )

    assert imported["entry"]["ctor"] == "VectorStaticSquare"
    assert is_binary(imported["preview_svg"])

    assert {:ok, imported_sequence} =
             Tools.call(
               "resources.vectors.import_sequence",
               %{
                 "slug" => slug,
                 "frames" => [frame_a, frame_b],
                 "name" => "Anim.pdc",
                 "frame_duration_ms" => 80
               },
               [:edit]
             )

    assert imported_sequence["entry"]["kind"] == "sequence"
    assert imported_sequence["entry"]["frames"] == 2

    assert {:ok, listed} = Tools.call("resources.vectors.list", %{"slug" => slug}, [:read])
    ctors = Enum.map(listed["entries"], & &1["ctor"])
    assert "VectorStaticSquare" in ctors
    assert "VectorAnimatedAnim" in ctors

    assert {:ok, preview} =
             Tools.call("resources.vectors.preview", %{"slug" => slug, "ctor" => "VectorStaticSquare"}, [
               :read
             ])

    assert preview["kind"] == "image"
    assert String.contains?(preview["svg"], "<svg")

    assert {:ok, deleted} =
             Tools.call("resources.vectors.delete", %{"slug" => slug, "ctor" => "VectorStaticSquare"}, [:edit])

    assert deleted["deleted"] == "VectorStaticSquare"
    refute Enum.any?(deleted["entries"], &(&1["ctor"] == "VectorStaticSquare"))
  end
end
