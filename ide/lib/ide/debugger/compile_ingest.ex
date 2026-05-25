defmodule Ide.Debugger.CompileIngest do
  @moduledoc """
  Plans surface merges and timeline events for `ingest_elmc_check/2`, `ingest_elmc_compile/2`,
  and `ingest_elmc_manifest/2`.
  """

  alias Ide.Debugger.Types.{
    CompileIngestAttrs,
    ElmcEventPayload,
    ElmcSurfaceFields,
    RuntimeEventAppend
  }

  @type ingest_plan :: %{
          required(:fields) => map(),
          required(:event_type) => String.t(),
          required(:event_payload) => ElmcEventPayload.t(),
          optional(:artifact_fields) => map(),
          optional(:artifact_target) => :watch | :companion | :phone | nil
        }

  @spec check_plan(CompileIngestAttrs.t() | map()) :: ingest_plan()
  def check_plan(attrs) when is_map(attrs) do
    %{
      fields: ElmcSurfaceFields.ingest_check_fields(attrs),
      event_type: RuntimeEventAppend.wire_type(:elmc_check),
      event_payload: ElmcEventPayload.from_check(attrs)
    }
  end

  @spec compile_plan(CompileIngestAttrs.t() | map()) :: ingest_plan()
  def compile_plan(attrs) when is_map(attrs) do
    %{
      fields: ElmcSurfaceFields.ingest_compile_fields(attrs),
      event_type: RuntimeEventAppend.wire_type(:elmc_compile),
      event_payload: ElmcEventPayload.from_compile(attrs),
      artifact_fields: ElmcSurfaceFields.optional_runtime_artifacts(attrs),
      artifact_target: ElmcSurfaceFields.compile_artifact_target(attrs)
    }
  end

  @spec manifest_plan(CompileIngestAttrs.t() | map()) :: ingest_plan()
  def manifest_plan(attrs) when is_map(attrs) do
    %{
      fields: ElmcSurfaceFields.ingest_manifest_fields(attrs),
      event_type: RuntimeEventAppend.wire_type(:elmc_manifest),
      event_payload: ElmcEventPayload.from_manifest(attrs)
    }
  end

  @spec merge_fields_into_all_targets(map(), map()) :: map()
  def merge_fields_into_all_targets(state, fields) when is_map(state) and is_map(fields) do
    state
    |> merge_target(:watch, fields)
    |> merge_target(:companion, fields)
    |> merge_target(:phone, fields)
  end

  @spec merge_target(map(), :watch | :companion | :phone, map()) :: map()
  defp merge_target(state, target, fields)
       when target in [:watch, :companion, :phone] and is_map(state) and is_map(fields) do
    Ide.Debugger.RuntimeSurfaceMerge.merge_into_state(state, target, fields)
  end
end
