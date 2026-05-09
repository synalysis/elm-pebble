defmodule Ide.Mcp.ToolsTest do
  use Ide.DataCase, async: false

  defmodule MockCompiler do
    alias Ide.Compiler.ManifestCache

    def check(_slug, _opts),
      do: {:ok, %{status: :ok, checked_path: ".", diagnostics: [], output: "ok"}}

    def compile(_slug, _opts),
      do:
        {:ok,
         %{
           status: :ok,
           compiled_path: ".",
           revision: "mock-rev",
           cached?: false,
           diagnostics: [],
           output: "ok"
         }}

    def manifest(slug, opts) do
      strict? = Keyword.get(opts, :strict, false)
      revision = "mock-rev:strict=#{strict?}"

      result = %{
        status: :ok,
        diagnostics: [],
        output: "ok",
        manifest_path: ".",
        revision: revision,
        cached?: false,
        strict?: strict?,
        manifest: %{
          schema_version: 1,
          supported_packages: ["elm/core"],
          excluded_packages: [],
          modules_detected: ["Main"]
        }
      }

      :ok = ManifestCache.put(slug, revision, result)
      {:ok, result}
    end
  end

  defmodule StructuredWarningCompiler do
    def check(_slug, _opts) do
      {:ok,
       %{
         status: :ok,
         checked_path: ".",
         diagnostics: [
           %{
             severity: "warning",
             source: "elmc/lowerer/pattern",
             message: "Constructor Wrap expects payload pattern",
             file: nil,
             line: 12,
             column: nil,
             warning_type: "lowerer-warning",
             warning_code: "constructor_payload_arity",
             warning_constructor: "Wrap",
             warning_expected_kind: "single",
             warning_has_arg_pattern: false
           }
         ],
         output: "ok"
       }}
    end

    def compile(_slug, _opts), do: MockCompiler.compile(nil, [])
    def manifest(slug, opts), do: MockCompiler.manifest(slug, opts)
  end

  defmodule MockPackageProvider do
    @behaviour Ide.Packages.Provider

    @impl true
    def search(_query, _opts) do
      {:ok, [%{name: "elm/http", summary: "HTTP", license: "BSD-3-Clause", version: "2.0.0"}]}
    end

    @impl true
    def package_details(package, _opts) do
      {:ok,
       %{
         name: package,
         summary: "HTTP",
         license: "BSD-3-Clause",
         latest_version: "2.0.0",
         versions: ["1.0.0", "2.0.0"],
         exposed_modules: ["Http"],
         elm_json: %{}
       }}
    end

    @impl true
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

    def package_release("elm/core", "1.0.5", _opts), do: {:ok, %{"dependencies" => %{}}}

    def package_release("elm/json", "1.1.3", _opts),
      do: {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

    def package_release(_package, _version, _opts), do: {:ok, %{"dependencies" => %{}}}

    @impl true
    def readme(package, version, _opts), do: {:ok, "# #{package} #{version}"}
  end

  defmodule MockPebbleToolchain do
    def package(_slug, _opts) do
      {:ok,
       %{
         status: :ok,
         artifact_path: "/tmp/mock-app.pbw",
         app_root: "/tmp/mock-app",
         build_result: %{status: :ok, output: "packaged"}
       }}
    end

    def run_emulator(_slug, opts) do
      {:ok,
       %{
         status: :ok,
         command: "pebble install --emulator",
         output: "installed",
         exit_code: 0,
         cwd: Path.dirname(opts[:package_path] || "/tmp/mock-app.pbw")
       }}
    end
  end

  defmodule MockScreenshots do
    def capture(_slug, opts) do
      target = opts[:emulator_target] || "basalt"

      {:ok,
       %{
         screenshot: %{
           filename: "shot-mock.png",
           emulator_target: target,
           url: "/screenshots/mock/#{target}/shot-mock.png",
           absolute_path: "/tmp/mock/#{target}/shot-mock.png",
           captured_at: "2026-01-01 00:00:00"
         },
         output: "captured",
         exit_code: 0,
         command: "pebble screenshot",
         cwd: "/tmp/mock"
       }}
    end
  end

  alias Ide.Mcp.Audit
  alias Ide.Mcp.Tools
  alias Ide.Projects
  alias Ide.Debugger

  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_mcp_tools_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "lists tools for provided capability scope" do
    tool_defs = Tools.tool_definitions([:read, :build])
    tool_names = Enum.map(tool_defs, & &1.name)

    assert "projects.list" in tool_names
    assert "files.read" in tool_names
    assert "packages.search" in tool_names
    assert "packages.details" in tool_names
    assert "packages.versions" in tool_names
    assert "packages.readme" in tool_names
    assert "projects.graph" in tool_names
    assert "audit.recent" in tool_names
    assert "compiler.check_cached" in tool_names
    assert "compiler.check_recent" in tool_names
    assert "compiler.compile_cached" in tool_names
    assert "compiler.compile_recent" in tool_names
    assert "compiler.manifest_cached" in tool_names
    assert "compiler.manifest_recent" in tool_names
    assert "sessions.recent_activity" in tool_names
    assert "sessions.summary" in tool_names
    assert "sessions.trace_health" in tool_names
    assert "traces.bundle" in tool_names
    assert "traces.summary" in tool_names
    assert "traces.export" in tool_names
    assert "traces.exports_list" in tool_names
    assert "traces.policy" in tool_names
    assert "traces.policy_validate" in tool_names
    assert "debugger.state" in tool_names
    assert "debugger.cursor_inspect" in tool_names
    assert "debugger.export_trace" in tool_names
    assert "pebble.package" in tool_names
    assert "pebble.install" in tool_names
    assert "screenshots.capture" in tool_names
    refute "traces.export_write" in tool_names
    refute "traces.exports_prune" in tool_names
    refute "traces.maintenance" in tool_names
    refute "projects.create" in tool_names
    refute "projects.delete" in tool_names
    refute "debugger.start" in tool_names
    refute "debugger.reset" in tool_names
    refute "debugger.import_trace" in tool_names
    refute "debugger.reload" in tool_names
    refute "debugger.step" in tool_names
    refute "debugger.tick" in tool_names
    refute "debugger.auto_tick_start" in tool_names
    refute "debugger.auto_tick_stop" in tool_names
    refute "debugger.replay_recent" in tool_names
    refute "debugger.continue_from_snapshot" in tool_names
    assert "compiler.check" in tool_names
    assert "compiler.compile" in tool_names
    assert "compiler.manifest" in tool_names
    refute "files.write" in tool_names
    refute "packages.add_to_elm_json" in tool_names
    refute "packages.remove_from_elm_json" in tool_names
    assert Enum.all?(tool_defs, &(is_binary(&1.version) and &1.version != ""))
    assert is_binary(Tools.catalog_version())
  end

  test "publish capability is default deny until publish tools are defined" do
    tool_defs = Tools.tool_definitions([:publish])
    assert tool_defs == []

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
    assert packaged.artifact_path == "/tmp/mock-app.pbw"
    assert packaged.status == :ok

    assert {:ok, installed} =
             Tools.call(
               "pebble.install",
               %{"slug" => "mcp-mutate", "emulator_target" => "chalk"},
               [:build]
             )

    assert installed.slug == "mcp-mutate"
    assert installed.artifact_path == "/tmp/mock-app.pbw"
    assert installed.install_result.status == :ok
    assert installed.install_result.exit_code == 0

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

    assert {:ok, %{name: "elm/http", compatibility: compatibility}} =
             Tools.call("packages.details", %{"package" => "elm/http"}, [:read])

    assert compatibility.status == "blocked"
    assert compatibility.reason_code == "blocked_runtime_family"

    assert {:ok, %{versions: ["2.0.0"]}} =
             Tools.call("packages.versions", %{"package" => "elm/http"}, [:read])

    assert {:ok, %{readme: "# elm/http latest"}} =
             Tools.call("packages.readme", %{"package" => "elm/http"}, [:read])

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
                 "content" => "module Main exposing (main)"
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

  test "debugger MCP tools expose state and controls by capability" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpDebugger",
               "slug" => "mcp-debugger",
               "target_type" => "app"
             })

    assert {:error, reason} = Tools.call("debugger.start", %{"slug" => project.slug}, [:read])
    assert String.contains?(reason, "not permitted")

    assert {:ok, %{slug: "mcp-debugger", state: started}} =
             Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])

    assert started.running == true
    assert started.seq >= 1

    assert {:error, reason} =
             Tools.call(
               "debugger.reload",
               %{"slug" => project.slug, "rel_path" => "watch/Main.elm"},
               [:read]
             )

    assert String.contains?(reason, "not permitted")

    assert {:ok, %{slug: "mcp-debugger", state: after_reload}} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/Main.elm",
                 "source" => "module Main exposing (main)",
                 "reason" => "mcp_test"
               },
               [:edit]
             )

    assert after_reload.seq > started.seq
    assert Enum.any?(after_reload.events, &(&1.type == "debugger.reload"))

    assert {:ok, %{state: phone_reload}} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "phone/Main.elm",
                 "source_root" => "phone"
               },
               [:edit]
             )

    assert phone_reload.seq > after_reload.seq

    assert {:ok, %{state: stepped}} =
             Tools.call(
               "debugger.step",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "message" => "Inc",
                 "count" => 2
               },
               [:edit]
             )

    assert stepped.seq > phone_reload.seq
    assert get_in(stepped, [:watch, :model, "runtime_message_source"]) == "provided"
    assert Enum.any?(stepped.events, &(&1.type == "debugger.update_in"))
    assert Enum.any?(stepped.events, &(&1.type == "debugger.view_render"))

    assert {:ok, %{state: companion_stepped}} =
             Tools.call(
               "debugger.step",
               %{
                 "slug" => project.slug,
                 "target" => "companion",
                 "message" => "Sync",
                 "count" => 1
               },
               [:edit]
             )

    assert get_in(companion_stepped, [:companion, :model, "runtime_message_source"]) == "provided"

    assert {:ok, %{state: ticked}} =
             Tools.call(
               "debugger.tick",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1
               },
               [:edit]
             )

    assert ticked.seq > stepped.seq
    assert get_in(ticked, [:watch, :model, "runtime_message_source"]) == "subscription_tick"
    assert Enum.any?(ticked.events, &(&1.type == "debugger.tick"))

    assert {:ok, %{state: auto_tick_started}} =
             Tools.call(
               "debugger.auto_tick_start",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "interval_ms" => 120
               },
               [:edit]
             )

    assert get_in(auto_tick_started, [:auto_tick, :enabled]) == true
    Process.sleep(280)

    assert {:ok, %{state: auto_tick_stopped}} =
             Tools.call(
               "debugger.auto_tick_stop",
               %{"slug" => project.slug},
               [:edit]
             )

    assert get_in(auto_tick_stopped, [:auto_tick, :enabled]) == false
    assert Enum.any?(auto_tick_stopped.events, &(&1.type == "debugger.tick_auto"))
    assert Enum.any?(auto_tick_stopped.events, &(&1.type == "debugger.tick"))

    assert {:ok, %{state: replayed_recent}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_mode" => "live",
                 "replay_drift_seq" => 4,
                 "cursor_seq" => stepped.seq
               },
               [:edit]
             )

    assert replayed_recent.seq > stepped.seq
    assert replay_event = Enum.find(replayed_recent.events, &(&1.type == "debugger.replay"))
    assert Map.get(replay_event.payload, :replay_source) == "recent_query"
    telemetry = Map.get(replay_event.payload, :replay_telemetry)
    assert is_map(telemetry)
    assert telemetry.mode == "live"
    assert telemetry.source == "recent_query"
    assert telemetry.drift_seq == 4
    assert telemetry.drift_band == "medium"
    assert telemetry.used_live_query == true
    assert telemetry.used_frozen_preview == false
    assert Map.get(replay_event.payload, :replay_target_counts) == %{"watch" => 1}
    assert is_map(Map.get(replay_event.payload, :replay_message_counts))
    assert is_list(Map.get(replay_event.payload, :replay_preview))

    assert {:ok, %{state: replayed_mode_source_split}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_mode" => "frozen"
               },
               [:edit]
             )

    assert replay_mode_source_event =
             Enum.find(replayed_mode_source_split.events, &(&1.type == "debugger.replay"))

    mode_source_telemetry = Map.get(replay_mode_source_event.payload, :replay_telemetry)
    assert mode_source_telemetry.mode == "frozen"
    assert mode_source_telemetry.source == "recent_query"
    assert mode_source_telemetry.used_live_query == true
    assert mode_source_telemetry.used_frozen_preview == false

    assert {:ok,
            %{
              state: replay_state,
              replay_metadata: replay_state_md,
              runtime_fingerprints: replay_fps,
              runtime_fingerprint_digest: replay_fp_digest,
              snapshot_refs: replay_snapshot_refs
            }} =
             Tools.call("debugger.state", %{"slug" => project.slug, "event_limit" => 50}, [:read])

    assert replay_state.seq >= replayed_recent.seq
    assert is_map(replay_fps)
    assert is_map(replay_fps.watch)
    assert replay_fps.watch.runtime_mode == "runtime_executed"
    assert replay_fps.watch.engine == "elm_executor_runtime_v1"
    assert is_map(replay_fp_digest)
    assert is_map(replay_fp_digest.watch)
    assert replay_fp_digest.watch.runtime_mode == "runtime_executed"
    assert replay_fp_digest.watch.engine == "elm_executor_runtime_v1"
    assert replay_fp_digest.watch.execution_backend == "external"
    assert Map.has_key?(replay_fp_digest.watch, :target_numeric_key_source)
    assert Map.has_key?(replay_fp_digest.watch, :target_boolean_key_source)
    assert Map.has_key?(replay_fp_digest.watch, :active_target_key_source)
    assert is_binary(replay_fp_digest.watch.runtime_model_sha256)
    assert is_binary(replay_fp_digest.watch.view_tree_sha256)
    assert is_map(replay_fp_digest.companion)
    assert is_list(replay_snapshot_refs)
    assert replay_snapshot_refs != []

    assert Enum.all?(
             replay_snapshot_refs,
             &(is_integer(Map.get(&1, "seq")) and is_map(Map.get(&1, "snapshot_refs")))
           )

    assert {:ok, state_compare_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "compare_cursor_seq" => stepped.seq
               },
               [:read]
             )

    state_event_seqs = Enum.map(state_compare_payload.state.events, & &1.seq)

    expected_compare_seq =
      if stepped.seq in state_event_seqs, do: stepped.seq, else: state_compare_payload.state.seq

    assert is_map(state_compare_payload.runtime_fingerprint_compare)

    assert state_compare_payload.runtime_fingerprint_compare.compare_cursor_seq ==
             expected_compare_seq

    assert is_integer(
             state_compare_payload.runtime_fingerprint_compare.backend_changed_surface_count
           )

    assert is_integer(
             state_compare_payload.runtime_fingerprint_compare.key_target_changed_surface_count
           )

    assert Map.has_key?(state_compare_payload.runtime_fingerprint_compare, :backend_drift_detail)

    assert Map.has_key?(
             state_compare_payload.runtime_fingerprint_compare,
             :key_target_drift_detail
           )

    assert Map.has_key?(state_compare_payload.runtime_fingerprint_compare, :drift_detail)
    assert is_map(state_compare_payload.runtime_fingerprint_compare.surfaces)
    assert is_boolean(state_compare_payload.runtime_fingerprint_compare.surfaces.watch.changed)

    assert is_boolean(
             state_compare_payload.runtime_fingerprint_compare.surfaces.watch.backend_changed
           )

    assert {:ok, far_compare_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "compare_cursor_seq" => stepped.seq + 100_000
               },
               [:read]
             )

    assert far_compare_payload.runtime_fingerprint_compare.compare_cursor_seq ==
             far_compare_payload.state.seq

    assert replay_state_md.replay_source == "recent_query"
    assert replay_state_md.replay_telemetry.mode == "frozen"
    assert replay_state_md.replay_telemetry.source == "recent_query"
    assert replay_state_md.replay_telemetry.drift_seq == 0
    assert replay_state_md.replay_telemetry.drift_band == "none"
    assert replay_state_md.replay_telemetry.used_live_query == true
    assert replay_state_md.replay_telemetry.used_frozen_preview == false

    assert {:ok,
            %{
              slug: "mcp-debugger",
              replay_metadata: md_only,
              event_window: win,
              runtime_fingerprint_digest: md_only_fp_digest,
              snapshot_refs: md_only_snapshot_refs
            }} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "replay_metadata_only" => true
               },
               [:read]
             )

    assert is_integer(win) and win > 0
    assert md_only.replay_source == "recent_query"
    assert md_only.replay_telemetry.mode == "frozen"
    assert md_only.replay_telemetry.source == "recent_query"
    assert md_only.replay_telemetry.drift_seq == 0
    assert md_only.replay_telemetry.drift_band == "none"
    assert md_only.replay_telemetry.used_live_query == true
    assert md_only.replay_telemetry.used_frozen_preview == false
    assert is_map(md_only_fp_digest)
    assert is_map(md_only_fp_digest.watch)
    assert md_only_fp_digest.watch.runtime_mode == "runtime_executed"
    assert is_binary(md_only_fp_digest.watch.runtime_model_sha256)
    assert is_binary(md_only_fp_digest.watch.view_tree_sha256)
    assert is_map(md_only_fp_digest.companion)
    assert is_list(md_only_snapshot_refs)

    assert {:ok, no_md_full} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(no_md_full, :replay_metadata)
    assert is_map(no_md_full.runtime_fingerprints)
    assert is_map(no_md_full.runtime_fingerprint_digest)
    assert is_map(no_md_full.state)

    assert {:ok, inspect_replay} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug},
               [:read]
             )

    assert inspect_replay.replay_metadata.replay_source == "recent_query"
    assert inspect_replay.replay_metadata.replay_telemetry.mode == "frozen"
    assert inspect_replay.replay_metadata.replay_telemetry.source == "recent_query"
    assert inspect_replay.replay_metadata.replay_telemetry.drift_seq == 0
    assert inspect_replay.replay_metadata.replay_telemetry.drift_band == "none"
    assert inspect_replay.replay_metadata.replay_telemetry.used_live_query == true
    assert inspect_replay.replay_metadata.replay_telemetry.used_frozen_preview == false
    assert is_map(inspect_replay.runtime_fingerprints)
    assert is_map(inspect_replay.runtime_fingerprint_digest)
    assert is_map(inspect_replay.runtime_fingerprints.watch)
    assert inspect_replay.runtime_fingerprints.watch.runtime_mode == "runtime_executed"
    assert inspect_replay.runtime_fingerprints.watch.engine == "elm_executor_runtime_v1"
    assert inspect_replay.runtime_fingerprints.watch.execution_backend == "external"
    assert is_binary(inspect_replay.runtime_fingerprints.watch.runtime_model_sha256)
    assert is_binary(inspect_replay.runtime_fingerprints.watch.view_tree_sha256)
    assert is_map(inspect_replay.runtime_fingerprints.companion)
    assert is_list(inspect_replay.snapshot_refs)

    assert {:ok, inspect_compare_payload} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "compare_cursor_seq" => stepped.seq},
               [:read]
             )

    assert is_map(inspect_compare_payload.runtime_fingerprint_compare)
    assert inspect_compare_payload.runtime_fingerprint_compare.compare_cursor_seq == stepped.seq

    assert is_integer(
             inspect_compare_payload.runtime_fingerprint_compare.backend_changed_surface_count
           )

    assert is_integer(
             inspect_compare_payload.runtime_fingerprint_compare.key_target_changed_surface_count
           )

    assert Map.has_key?(
             inspect_compare_payload.runtime_fingerprint_compare,
             :backend_drift_detail
           )

    assert Map.has_key?(
             inspect_compare_payload.runtime_fingerprint_compare,
             :key_target_drift_detail
           )

    assert Map.has_key?(inspect_compare_payload.runtime_fingerprint_compare, :drift_detail)
    assert is_boolean(inspect_compare_payload.runtime_fingerprint_compare.surfaces.watch.changed)

    assert is_boolean(
             inspect_compare_payload.runtime_fingerprint_compare.surfaces.watch.backend_changed
           )

    assert {:ok, inspect_replay_no_md} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(inspect_replay_no_md, :replay_metadata)
    assert is_map(inspect_replay_no_md.runtime_fingerprints)
    assert is_map(inspect_replay_no_md.runtime_fingerprint_digest)

    assert {:error, bad_cursor_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "cursor_seq" => -1
               },
               [:edit]
             )

    assert bad_cursor_msg == "invalid cursor_seq (expected non-negative integer)"

    assert {:error, bad_compare_cursor_msg} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "compare_cursor_seq" => "nope"
               },
               [:read]
             )

    assert bad_compare_cursor_msg == "invalid compare_cursor_seq (expected non-negative integer)"

    assert {:error, bad_mode_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "replay_mode" => "bogus"
               },
               [:edit]
             )

    assert bad_mode_msg == "invalid replay_mode (expected frozen|live)"

    assert {:error, bad_drift_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "replay_drift_seq" => -1
               },
               [:edit]
             )

    assert bad_drift_msg == "invalid replay_drift_seq (expected non-negative integer)"

    assert {:error, bad_drift_string_msg} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "replay_drift_seq" => "abc"
               },
               [:edit]
             )

    assert bad_drift_string_msg == "invalid replay_drift_seq (expected non-negative integer)"

    assert {:ok, %{state: replayed_unknown_mode}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => project.slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_drift_seq" => "4"
               },
               [:edit]
             )

    assert replay_unknown_event =
             Enum.find(replayed_unknown_mode.events, &(&1.type == "debugger.replay"))

    assert Map.get(replay_unknown_event.payload, :replay_telemetry).mode == "unknown"
    assert Map.get(replay_unknown_event.payload, :replay_telemetry).drift_seq == 4
    assert Map.get(replay_unknown_event.payload, :replay_telemetry).drift_band == "medium"

    assert_replay_drift_band(project.slug, "0", 0, "none")
    assert_replay_drift_band(project.slug, "3", 3, "mild")
    assert_replay_drift_band(project.slug, "10", 10, "medium")
    assert_replay_drift_band(project.slug, "11", 11, "high")

    snap_src = """
    module McpSnap exposing (..)

    type Msg
        = A

    init _ =
        ( { n = 1 }, Cmd.none )

    view m =
        Ui.root []
    """

    assert {:ok, %{state: intro_reload}} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/McpSnap.elm",
                 "source" => snap_src,
                 "source_root" => "watch",
                 "reason" => "mcp_introspect"
               },
               [:edit]
             )

    assert intro_reload.seq > phone_reload.seq

    assert {:ok, snapshot_payload} =
             Tools.call("debugger.state", %{"slug" => project.slug, "event_limit" => 5}, [:read])

    assert snapshot_payload.slug == "mcp-debugger"
    snapshot = snapshot_payload.state
    replay_md = Map.get(snapshot_payload, :replay_metadata)
    assert replay_md == nil or is_map(replay_md)

    assert {:ok, inspect0} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "cursor_seq" => 1},
               [
                 :read
               ]
             )

    assert inspect0.cursor_seq == 1
    assert inspect0.event_window > 0
    assert Enum.any?(inspect0.lifecycle, &(&1.type == "debugger.start"))
    assert inspect0.view_renders == []

    assert {:ok, inspect_latest} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert inspect_latest.cursor_seq == inspect0.event_window
    assert Enum.any?(inspect_latest.view_renders, &(&1.target == "watch"))
    assert inspect_latest.elm_introspect.watch["module"] == "McpSnap"
    assert inspect_latest.elm_introspect.watch["init_model"]["n"] == 1

    assert {:ok, _} =
             Debugger.ingest_elmc_check(project.slug, %{
               status: :ok,
               checked_path: ".",
               error_count: 0,
               warning_count: 0,
               diagnostics: [
                 %{
                   severity: "error",
                   message: "mcp row",
                   source: "elmc",
                   file: "A.elm",
                   line: 2,
                   warning_type: "lowerer-warning",
                   warning_code: "constructor_payload_arity",
                   warning_constructor: "Ok",
                   warning_expected_kind: "single",
                   warning_has_arg_pattern: false
                 }
               ]
             })

    assert {:ok, inspect_diag} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert inspect_diag.elmc_diagnostics_source == "event_payload"

    assert [
             %{
               "message" => "mcp row",
               "warning_type" => "lowerer-warning",
               "warning_code" => "constructor_payload_arity",
               "warning_constructor" => "Ok",
               "warning_expected_kind" => "single",
               "warning_has_arg_pattern" => false
             }
             | _
           ] = inspect_diag.elmc_diagnostics

    assert inspect_diag.elm_introspect.watch["module"] == "McpSnap"

    assert {:error, msg} =
             Tools.call(
               "debugger.cursor_inspect",
               %{"slug" => project.slug, "cursor_seq" => -1},
               [
                 :read
               ]
             )

    assert msg == "invalid cursor_seq (expected non-negative integer)"

    assert snapshot.running == true
    assert is_list(snapshot.events)
    assert length(snapshot.events) <= 5

    assert {:ok, export} =
             Tools.call(
               "debugger.export_trace",
               %{"slug" => project.slug, "event_limit" => 50},
               [
                 :read
               ]
             )

    assert export.slug == "mcp-debugger"
    assert is_binary(export.export_json)
    assert byte_size(export.export_json) == export.byte_size
    assert is_binary(export.sha256)

    assert {:ok, export_body} = Jason.decode(export.export_json)
    assert is_map(export_body["runtime_fingerprint_compare"])
    assert is_integer(export_body["runtime_fingerprint_compare"]["current_cursor_seq"])
    assert Map.has_key?(export_body["runtime_fingerprint_compare"], "baseline_cursor_seq")
    assert is_map(export_body["runtime_fingerprint_compare"]["surfaces"])

    export_diag =
      export_body
      |> Map.get("events", [])
      |> Enum.find_value(fn event ->
        payload = Map.get(event, "payload", %{})
        preview = Map.get(payload, "diagnostic_preview", [])

        if is_list(preview) and preview != [], do: List.first(preview), else: nil
      end)

    assert is_map(export_diag)
    assert export_diag["message"] == "mcp row"
    assert export_diag["warning_type"] == "lowerer-warning"
    assert export_diag["warning_code"] == "constructor_payload_arity"
    assert export_diag["warning_constructor"] == "Ok"
    assert export_diag["warning_expected_kind"] == "single"
    assert export_diag["warning_has_arg_pattern"] == false

    assert {:ok, export_with_compare} =
             Tools.call(
               "debugger.export_trace",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "compare_cursor_seq" => stepped.seq,
                 "baseline_cursor_seq" => 1
               },
               [:read]
             )

    assert {:ok, export_compare_body} = Jason.decode(export_with_compare.export_json)
    assert is_integer(export_compare_body["runtime_fingerprint_compare"]["baseline_cursor_seq"])

    assert export_compare_body["runtime_fingerprint_compare"]["baseline_cursor_seq"] <=
             export_compare_body["runtime_fingerprint_compare"]["current_cursor_seq"]

    assert export_compare_body["runtime_fingerprint_compare"]["current_cursor_seq"] <=
             export_compare_body["seq"]

    assert is_integer(
             export_compare_body["runtime_fingerprint_compare"]["backend_changed_surface_count"]
           )

    assert is_integer(
             export_compare_body["runtime_fingerprint_compare"][
               "key_target_changed_surface_count"
             ]
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"],
             "key_target_drift_detail"
           )

    assert Map.has_key?(export_compare_body["runtime_fingerprint_compare"], "drift_detail")
    assert is_map(export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"])

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"],
             "current_protocol_inbound_count"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"],
             "current_protocol_message_count"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["companion"],
             "current_protocol_last_inbound_message"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "current_execution_backend"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "baseline_execution_backend"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "current_external_fallback_reason"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "baseline_external_fallback_reason"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "current_active_target_key_source"
           )

    assert Map.has_key?(
             export_compare_body["runtime_fingerprint_compare"]["surfaces"]["watch"],
             "baseline_active_target_key_source"
           )

    assert {:error, bad_export_compare_msg} =
             Tools.call(
               "debugger.export_trace",
               %{"slug" => project.slug, "compare_cursor_seq" => "nope"},
               [:read]
             )

    assert bad_export_compare_msg == "invalid compare_cursor_seq (expected non-negative integer)"

    assert {:error, bad_export_baseline_msg} =
             Tools.call(
               "debugger.export_trace",
               %{"slug" => project.slug, "baseline_cursor_seq" => "nope"},
               [:read]
             )

    assert bad_export_baseline_msg ==
             "invalid baseline_cursor_seq (expected non-negative integer)"

    assert {:ok, tx_only_payload} =
             Tools.call(
               "debugger.state",
               %{"slug" => project.slug, "types" => ["debugger.start"]},
               [:read]
             )

    tx_only = tx_only_payload.state
    refute Map.has_key?(tx_only_payload, :replay_metadata)
    assert Enum.all?(tx_only.events, &(&1.type == "debugger.start"))

    assert {:ok, md_only_none} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "types" => ["debugger.start"],
                 "replay_metadata_only" => true
               },
               [:read]
             )

    refute Map.has_key?(md_only_none, :replay_metadata)

    assert {:ok, no_md_only} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "types" => ["debugger.start"],
                 "replay_metadata_only" => true,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(no_md_only, :replay_metadata)
    assert is_integer(no_md_only.event_window)

    assert {:ok, %{state: since_seq}} =
             Tools.call(
               "debugger.state",
               %{"slug" => project.slug, "since_seq" => 0},
               [:read]
             )

    assert Enum.all?(since_seq.events, &(&1.seq > 0))

    assert {:ok, %{slug: "mcp-debugger", state: continued_state}} =
             Tools.call(
               "debugger.continue_from_snapshot",
               %{"slug" => project.slug, "cursor_seq" => stepped.seq},
               [:edit]
             )

    assert hd(continued_state.events).type == "debugger.snapshot_continue"
    assert continued_state.seq > stepped.seq

    assert {:ok, %{slug: "mcp-debugger", state: reset_state}} =
             Tools.call("debugger.reset", %{"slug" => project.slug}, [:edit])

    assert reset_state.revision == nil

    assert {:ok, %{slug: "mcp-debugger", state: replayed}} =
             Tools.call(
               "debugger.import_trace",
               %{
                 "slug" => project.slug,
                 "export_json" => export.export_json
               },
               [:edit]
             )

    assert replayed.seq == export_body["seq"]

    assert {:error, mismatch_reason} =
             Tools.call(
               "debugger.import_trace",
               %{
                 "slug" => project.slug,
                 "export_json" => export.export_json,
                 "expected_sha256" => "deadbeef"
               },
               [:edit]
             )

    assert mismatch_reason =~ "sha256_mismatch"

    assert {:ok, %{slug: "mcp-debugger"}} =
             Tools.call(
               "debugger.import_trace",
               %{
                 "slug" => project.slug,
                 "export_json" => export.export_json,
                 "expected_sha256" => export.sha256
               },
               [:edit]
             )

    assert {:ok, replay_inspect} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert replay_inspect.elmc_diagnostics_source == "event_payload"

    assert [
             %{
               "message" => "mcp row",
               "warning_type" => "lowerer-warning",
               "warning_code" => "constructor_payload_arity",
               "warning_constructor" => "Ok",
               "warning_expected_kind" => "single",
               "warning_has_arg_pattern" => false
             }
             | _
           ] = replay_inspect.elmc_diagnostics
  end

  test "debugger.state polling modes expose expected payload keys" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpStateModes",
               "slug" => "mcp-state-modes",
               "target_type" => "app"
             })

    assert {:ok, _} = Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])

    assert {:ok, _} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/Main.elm",
                 "source" => "module Main exposing (main)"
               },
               [:edit]
             )

    assert {:ok, _} =
             Tools.call(
               "debugger.replay_recent",
               %{"slug" => project.slug, "target" => "watch", "count" => 1},
               [:edit]
             )

    assert {:ok, default_payload} =
             Tools.call("debugger.state", %{"slug" => project.slug, "event_limit" => 50}, [:read])

    assert Map.has_key?(default_payload, :state)
    assert Map.has_key?(default_payload, :runtime_fingerprints)
    assert Map.has_key?(default_payload, :runtime_fingerprint_digest)
    assert Map.has_key?(default_payload, :replay_metadata)
    refute Map.has_key?(default_payload, :event_window)

    assert {:ok, no_md_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    assert Map.has_key?(no_md_payload, :state)
    assert Map.has_key?(no_md_payload, :runtime_fingerprints)
    assert Map.has_key?(no_md_payload, :runtime_fingerprint_digest)
    refute Map.has_key?(no_md_payload, :replay_metadata)
    refute Map.has_key?(no_md_payload, :event_window)

    assert {:ok, md_only_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "replay_metadata_only" => true
               },
               [:read]
             )

    assert Map.has_key?(md_only_payload, :event_window)
    assert Map.has_key?(md_only_payload, :runtime_fingerprint_digest)
    assert Map.has_key?(md_only_payload, :replay_metadata)
    refute Map.has_key?(md_only_payload, :runtime_fingerprints)
    refute Map.has_key?(md_only_payload, :state)

    assert {:ok, md_only_no_md_payload} =
             Tools.call(
               "debugger.state",
               %{
                 "slug" => project.slug,
                 "event_limit" => 50,
                 "replay_metadata_only" => true,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    assert Map.has_key?(md_only_no_md_payload, :event_window)
    assert Map.has_key?(md_only_no_md_payload, :runtime_fingerprint_digest)
    refute Map.has_key?(md_only_no_md_payload, :replay_metadata)
    refute Map.has_key?(md_only_no_md_payload, :runtime_fingerprints)
    refute Map.has_key?(md_only_no_md_payload, :state)
  end

  test "debugger.cursor_inspect include_replay_metadata controls payload key" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "McpCursorInspectModes",
               "slug" => "mcp-cursor-inspect-modes",
               "target_type" => "app"
             })

    assert {:ok, _} = Tools.call("debugger.start", %{"slug" => project.slug}, [:edit])

    assert {:ok, _} =
             Tools.call(
               "debugger.reload",
               %{
                 "slug" => project.slug,
                 "rel_path" => "watch/Main.elm",
                 "source" => "module Main exposing (main)"
               },
               [:edit]
             )

    assert {:ok, _} =
             Tools.call(
               "debugger.replay_recent",
               %{"slug" => project.slug, "target" => "watch", "count" => 1},
               [:edit]
             )

    assert {:ok, inspect_default} =
             Tools.call("debugger.cursor_inspect", %{"slug" => project.slug}, [:read])

    assert Map.has_key?(inspect_default, :replay_metadata)
    assert inspect_default.replay_metadata.replay_source in ["recent_query", "frozen_preview"]
    assert Map.has_key?(inspect_default, :runtime_fingerprints)
    assert Map.has_key?(inspect_default, :runtime_fingerprint_digest)

    assert {:ok, inspect_no_md} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(inspect_no_md, :replay_metadata)
    assert Map.has_key?(inspect_no_md, :runtime_fingerprints)
    assert Map.has_key?(inspect_no_md, :runtime_fingerprint_digest)
    assert Map.has_key?(inspect_no_md, :update_messages)
    assert Map.has_key?(inspect_no_md, :protocol_exchange)
    assert Map.has_key?(inspect_no_md, :view_renders)
    assert Map.has_key?(inspect_no_md, :lifecycle)

    assert {:ok, inspect_md_only} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "replay_metadata_only" => true
               },
               [:read]
             )

    assert Map.has_key?(inspect_md_only, :replay_metadata)
    assert Map.has_key?(inspect_md_only, :cursor_seq)
    assert Map.has_key?(inspect_md_only, :event_window)
    refute Map.has_key?(inspect_md_only, :runtime_fingerprints)
    refute Map.has_key?(inspect_md_only, :runtime_fingerprint_digest)
    refute Map.has_key?(inspect_md_only, :update_messages)
    refute Map.has_key?(inspect_md_only, :protocol_exchange)
    refute Map.has_key?(inspect_md_only, :view_renders)
    refute Map.has_key?(inspect_md_only, :lifecycle)
    refute Map.has_key?(inspect_md_only, :elmc_diagnostics)
    refute Map.has_key?(inspect_md_only, :elm_introspect)

    assert {:ok, inspect_md_only_no_md} =
             Tools.call(
               "debugger.cursor_inspect",
               %{
                 "slug" => project.slug,
                 "replay_metadata_only" => true,
                 "include_replay_metadata" => false
               },
               [:read]
             )

    refute Map.has_key?(inspect_md_only_no_md, :replay_metadata)
    assert Map.has_key?(inspect_md_only_no_md, :cursor_seq)
    assert Map.has_key?(inspect_md_only_no_md, :event_window)
    refute Map.has_key?(inspect_md_only_no_md, :runtime_fingerprints)
    refute Map.has_key?(inspect_md_only_no_md, :runtime_fingerprint_digest)
    refute Map.has_key?(inspect_md_only_no_md, :update_messages)
  end

  defp assert_replay_drift_band(slug, replay_drift_seq, expected_seq, expected_band) do
    assert {:ok, %{state: replayed}} =
             Tools.call(
               "debugger.replay_recent",
               %{
                 "slug" => slug,
                 "target" => "watch",
                 "count" => 1,
                 "replay_drift_seq" => replay_drift_seq
               },
               [:edit]
             )

    assert replay_event = Enum.find(replayed.events, &(&1.type == "debugger.replay"))
    telemetry = Map.get(replay_event.payload, :replay_telemetry)
    assert telemetry.drift_seq == expected_seq
    assert telemetry.drift_band == expected_band
  end
end
