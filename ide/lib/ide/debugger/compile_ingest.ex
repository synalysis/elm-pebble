defmodule Ide.Debugger.CompileIngest do
  @moduledoc """
  Plans surface merges and timeline events for `ingest_elmc_check/2`, `ingest_elmc_compile/2`,
  and `ingest_elmc_manifest/2`.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{
    CompileIngestAttrs,
    ElmcEventPayload,
    ElmcSurfaceFields,
    RuntimeEventAppend
  }

  @type ingest_fields ::
          ElmcSurfaceFields.check_fields()
          | ElmcSurfaceFields.compile_fields()
          | ElmcSurfaceFields.manifest_fields()

  @type ingest_plan :: %{
          required(:fields) => ingest_fields(),
          required(:event_type) => String.t(),
          required(:event_payload) => ElmcEventPayload.t(),
          optional(:artifact_fields) => ElmcSurfaceFields.artifact_fields(),
          optional(:artifact_target) => ElmcSurfaceFields.surface_target() | nil
        }

  @spec check_plan(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: ingest_plan()
  def check_plan(attrs) when is_map(attrs) do
    %{
      fields: ElmcSurfaceFields.ingest_check_fields(attrs),
      event_type: RuntimeEventAppend.wire_type(:elmc_check),
      event_payload: ElmcEventPayload.from_check(attrs)
    }
  end

  @spec compile_plan(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: ingest_plan()
  def compile_plan(attrs) when is_map(attrs) do
    %{
      fields: ElmcSurfaceFields.ingest_compile_fields(attrs),
      event_type: RuntimeEventAppend.wire_type(:elmc_compile),
      event_payload: ElmcEventPayload.from_compile(attrs),
      artifact_fields: ElmcSurfaceFields.optional_runtime_artifacts(attrs),
      artifact_target: ElmcSurfaceFields.compile_artifact_target(attrs)
    }
  end

  @spec manifest_plan(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: ingest_plan()
  def manifest_plan(attrs) when is_map(attrs) do
    %{
      fields: ElmcSurfaceFields.ingest_manifest_fields(attrs),
      event_type: RuntimeEventAppend.wire_type(:elmc_manifest),
      event_payload: ElmcEventPayload.from_manifest(attrs)
    }
  end

  @spec merge_fields_into_all_targets(Types.runtime_state(), ingest_fields()) :: Types.runtime_state()
  def merge_fields_into_all_targets(state, fields) when is_map(state) and is_map(fields) do
    state
    |> merge_target(:watch, fields)
    |> merge_target(:companion, fields)
    |> merge_target(:phone, fields)
  end

  @spec merge_target(Types.runtime_state(), ElmcSurfaceFields.surface_target(), ingest_fields()) ::
          Types.runtime_state()
  defp merge_target(state, target, fields)
       when target in [:watch, :companion, :phone] and is_map(state) and is_map(fields) do
    Ide.Debugger.RuntimeSurfaceMerge.merge_into_state(state, target, fields)
  end
end
