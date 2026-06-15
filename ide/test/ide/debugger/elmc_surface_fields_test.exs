defmodule Ide.Debugger.ElmcSurfaceFieldsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.Types.ElmcSurfaceFields

  test "check_fields and ingest_check_fields include status and optional diagnostics" do
    fields =
      ElmcSurfaceFields.ingest_check_fields(%{
        status: :ok,
        checked_path: "/tmp/ws",
        error_count: 1,
        warning_count: 2,
        diagnostics: [%{severity: :warning, message: "unused import"}]
      })

    assert fields["elmc_check_status"] == "ok"
    assert fields["elmc_checked_path"] == "/tmp/ws"
    assert length(fields["elmc_diagnostic_preview"]) == 1
  end

  test "compile_fields keeps elmx artifacts out of compile status fields" do
    manifest = %{"contract" => "elmx.runtime_executor.v1"}

    fields =
      ElmcSurfaceFields.ingest_compile_fields(%{
        status: :ok,
        compiled_path: "watch/src/Main.elm",
        revision: "rev1",
        elmx_manifest: manifest,
        elmx_revision: "rev1"
      })

    assert fields["elmc_compile_status"] == "ok"
    refute Map.has_key?(fields, "elmx_manifest")
    refute Map.has_key?(fields, "elmx_revision")

    artifacts =
      ElmcSurfaceFields.optional_runtime_artifacts(%{
        elmx_manifest: manifest,
        elmx_revision: "rev1"
      })

    assert artifacts["elmx_manifest"] == manifest
    assert artifacts["elmx_revision"] == "rev1"
  end

  test "optional_runtime_artifacts and compile_artifact_target route by source_root" do
    artifacts =
      ElmcSurfaceFields.optional_runtime_artifacts(%{
        elmx_manifest: %{"contract" => "elmx.runtime_executor.v1"},
        elmx_revision: "rev1"
      })

    assert artifacts["elmx_manifest"]["contract"] == "elmx.runtime_executor.v1"
    assert artifacts["elmx_revision"] == "rev1"

    contract = %{"msg_constructors" => ["A"]}

    assert ElmcSurfaceFields.optional_runtime_artifacts(%{
             debugger_contract: contract,
             debugger_contract_b64: "abc",
             debugger_contract_version: "debugger_contract.v1"
           }) == %{
             "debugger_contract" => contract,
             "debugger_contract_b64" => "abc",
             "debugger_contract_version" => "debugger_contract.v1"
           }

    assert ElmcSurfaceFields.compile_artifact_target(%{source_root: "watch"}) == :watch
    assert ElmcSurfaceFields.compile_artifact_target(%{source_root: "protocol"}) == nil
    assert ElmcSurfaceFields.compile_artifact_target(%{source_root: "phone"}) == :companion
  end

  test "ingest paths merge ElmcSurfaceFields into runtime model" do
    slug = "elmc_surface_fields_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.ingest_elmc_manifest(slug, %{
               status: :error,
               manifest_path: "/tmp/manifest.json",
               schema_version: 2,
               strict: true
             })

    assert get_in(state, [:watch, :model, "elmc_manifest_status"]) == "error"
    assert get_in(state, [:watch, :model, "elmc_manifest_schema_version"]) == "2"
    assert get_in(state, [:watch, :model, "elmc_manifest_strict"]) == "true"
  end
end
