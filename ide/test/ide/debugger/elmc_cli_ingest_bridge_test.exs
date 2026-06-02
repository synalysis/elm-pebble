defmodule Ide.Debugger.ElmcCliIngestBridgeTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  alias Ide.Debugger.Types.{
    CompileIngestBridge,
    ElmcCliIngestBridge,
    ElmcEventPayload,
    ElmcSurfaceFields
  }

  test "to_check_result maps CLI warnings into compiler check_result" do
    result =
      ElmcCliIngestBridge.to_check_result(
        %{
          status: :error,
          output: "check: failed",
          warnings: [%{"severity" => "error", "message" => "bad", "source" => "elmc"}]
        },
        checked_path: "/tmp/proj"
      )

    assert result.status == :error
    assert result.checked_path == "/tmp/proj"
    assert result.error_count == 1
    assert hd(result.diagnostics).severity == "error"
  end

  test "from_check_run maps CLI warnings into ingest attrs" do
    attrs =
      ElmcCliIngestBridge.from_check_run(
        %{
          status: :error,
          output: "check: failed",
          warnings: [%{"severity" => "error", "message" => "bad", "source" => "elmc"}]
        },
        checked_path: "/tmp/proj"
      )

    assert attrs.status == :error
    assert attrs.checked_path == "/tmp/proj"
    assert attrs.error_count == 1
    assert hd(attrs.diagnostics).severity == "error"

    fields = ElmcSurfaceFields.ingest_check_fields(attrs)
    event = ElmcEventPayload.from_check(attrs)

    assert fields["elmc_check_status"] == "error"
    assert event.error_count == 1
  end

  test "from_compile_run maps compile metadata" do
    attrs =
      ElmcCliIngestBridge.from_compile_run(
        %{status: :ok, output: "compile: ok", warnings: []},
        compiled_path: "watch/.elmc-build",
        revision: "rev-1",
        source_root: "watch"
      )

    assert attrs.compiled_path == "watch/.elmc-build"
    assert ElmcSurfaceFields.optional_runtime_artifacts(attrs) == %{}
  end

  test "from_manifest_run reads schema_version from manifest map" do
    attrs =
      ElmcCliIngestBridge.from_manifest_run(
        %{
          status: :ok,
          output: "{}",
          warnings: [],
          manifest: %{"schema_version" => 2, "packages" => %{}}
        },
        manifest_path: "/tmp",
        revision: "r1"
      )

    assert attrs.schema_version == 2
    assert ElmcSurfaceFields.ingest_manifest_fields(attrs)["elmc_manifest_schema_version"] == "2"
  end

  test "debugger ingest accepts CLI-shaped attrs via bridge" do
    slug = "elmc_cli_ingest_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)
    assert {:ok, _} = Debugger.start_session(slug)

    attrs =
      ElmcCliIngestBridge.from_check_run(
        %{status: :ok, output: "check: ok", warnings: []},
        checked_path: "/tmp"
      )

    assert CompileIngestBridge.from_check_result(attrs) == attrs
    assert {:ok, state} = Debugger.ingest_elmc_check(slug, attrs)
    assert get_in(state, [:watch, :model, "elmc_check_status"]) == "ok"
  end
end
