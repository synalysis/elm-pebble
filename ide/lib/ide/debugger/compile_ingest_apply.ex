defmodule Ide.Debugger.CompileIngestApply do
  @moduledoc false

  alias Ide.Debugger.CompileIngest
  alias Ide.Debugger.Types

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type merge_artifacts_fn ::
          (Types.runtime_state(), Types.surface_target() | nil, map() -> Types.runtime_state())

  @type host :: %{
          required(:append_event) => append_event_fn(),
          optional(:merge_runtime_artifacts) => merge_artifacts_fn(),
          optional(:refresh_from_artifacts) => (Types.runtime_state() -> Types.runtime_state())
        }

  @spec check(Types.runtime_state(), Types.compile_ingest_attrs(), host()) :: Types.runtime_state()
  def check(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      %{fields: fields, event_type: type, event_payload: payload} = CompileIngest.check_plan(attrs)

      state
      |> CompileIngest.merge_fields_into_all_targets(fields)
      |> host.append_event.(type, payload)
    else
      state
    end
  end

  @spec compile(Types.runtime_state(), Types.compile_ingest_attrs(), host()) :: Types.runtime_state()
  def compile(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      %{
        fields: fields,
        event_type: type,
        event_payload: payload,
        artifact_fields: artifact_fields,
        artifact_target: artifact_target
      } = CompileIngest.compile_plan(attrs)

      state
      |> CompileIngest.merge_fields_into_all_targets(fields)
      |> maybe_merge_artifacts(host, artifact_target, artifact_fields)
      |> maybe_refresh_artifacts(host)
      |> host.append_event.(type, payload)
    else
      state
    end
  end

  @spec manifest(Types.runtime_state(), Types.compile_ingest_attrs(), host()) :: Types.runtime_state()
  def manifest(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      %{fields: fields, event_type: type, event_payload: payload} = CompileIngest.manifest_plan(attrs)

      state
      |> CompileIngest.merge_fields_into_all_targets(fields)
      |> host.append_event.(type, payload)
    else
      state
    end
  end

  defp maybe_merge_artifacts(state, host, target, fields) do
    case Map.get(host, :merge_runtime_artifacts) do
      fun when is_function(fun, 3) -> fun.(state, target, fields)
      _ -> state
    end
  end

  defp maybe_refresh_artifacts(state, host) do
    case Map.get(host, :refresh_from_artifacts) do
      fun when is_function(fun, 1) -> fun.(state)
      _ -> state
    end
  end
end
