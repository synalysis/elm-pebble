defmodule Ide.Debugger.CompileIngestBridgeTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.Types.{CompileIngestBridge, ElmcEventPayload, ElmcSurfaceFields}

  test "from_check_result maps compiler check into ingest attrs" do
    attrs =
      CompileIngestBridge.from_check_result(%{
        status: :ok,
        checked_path: "/tmp/proj",
        error_count: 0,
        warning_count: 2,
        diagnostics: [%{severity: "warning", message: "hint"}]
      })

    fields = ElmcSurfaceFields.ingest_check_fields(attrs)
    event = ElmcEventPayload.from_check(attrs)

    assert fields["elmc_check_status"] == "ok"
    assert event.status == "ok"
    assert event.warning_count == 2
    assert length(fields["elmc_diagnostic_preview"]) == 1
  end

  test "from_compile_result preserves elmx artifacts for surface merge" do
    attrs =
      CompileIngestBridge.from_compile_result(%{
        status: :ok,
        compiled_path: "watch/src/Main.elm",
        revision: "rev",
        cached?: true,
        source_root: "watch",
        elmx_manifest: %{"contract" => "elmx.runtime_executor.v1"},
        elmx_revision: "rev"
      })

    artifacts = ElmcSurfaceFields.optional_runtime_artifacts(attrs)
    fields = ElmcSurfaceFields.ingest_compile_fields(attrs)

    assert artifacts["elmx_manifest"]["contract"] == "elmx.runtime_executor.v1"
    assert artifacts["elmx_revision"] == "rev"
    assert fields["elmx_manifest"]["contract"] == "elmx.runtime_executor.v1"
  end

  test "from_manifest_result maps strict? and schema_version" do
    attrs =
      CompileIngestBridge.from_manifest_result(%{
        status: :ok,
        manifest_path: "/tmp/manifest.json",
        revision: "r1",
        strict?: true,
        cached?: false,
        schema_version: 2,
        error_count: 0,
        warning_count: 0
      })

    fields = ElmcSurfaceFields.ingest_manifest_fields(attrs)

    assert attrs.strict == true
    assert attrs.schema_version == 2
    assert fields["elmc_manifest_strict"] == "true"
  end

  test "debugger ingest via bridge-shaped attrs" do
    slug = "compile_ingest_bridge_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    attrs =
      CompileIngestBridge.from_check_result(%{
        status: :error,
        checked_path: "/tmp",
        error_count: 1,
        warning_count: 0
      })

    assert {:ok, state} = Debugger.ingest_elmc_check(slug, attrs)
    assert get_in(state, [:watch, :model, "elmc_check_status"]) == "error"
  end
end
