defmodule Ide.Debugger.TraceExchange do
  @moduledoc """
  Trace export/import serialization for debugger sessions.

  Implementation is split into:

  * `Ide.Debugger.TraceExchange.Export` — export body construction
  * `Ide.Debugger.TraceExchange.Import` — decode, validate, and parse import bodies
  * `Ide.Debugger.TraceExchange.Wire` — canonical JSON wire normalization
  * `Ide.Debugger.TraceExchange.FingerprintCompare` — runtime fingerprint drift payloads
  * `Ide.Debugger.TraceExchange.Events` — event lookup helpers for snapshot continue
  """

  alias Ide.Debugger.TraceExchange.{Events, Export, FingerprintCompare, Import, Wire}
  alias Ide.Debugger.Types

  @type runtime_event :: Types.runtime_event()
  @type debugger_event :: Types.debugger_event()
  @type runtime_state :: Types.RuntimeState.t() | map()

  @spec export_payload(String.t(), runtime_state(), keyword()) :: Types.import_trace_body()
  def export_payload(project_slug, state, opts) when is_binary(project_slug) and is_map(state) do
    Export.payload(project_slug, state,
      disabled_subscriptions: Keyword.fetch!(opts, :disabled_subscriptions),
      compare_cursor_seq: Keyword.get(opts, :compare_cursor_seq),
      baseline_cursor_seq: Keyword.get(opts, :baseline_cursor_seq)
    )
  end

  @spec build_runtime_fingerprint_compare_payload(
          [runtime_event()],
          integer() | nil,
          integer() | nil
        ) :: map()
  defdelegate build_runtime_fingerprint_compare_payload(events, compare_cursor_seq, baseline_cursor_seq),
    to: FingerprintCompare,
    as: :build

  @spec event_at_seq([runtime_event()], integer() | nil) :: runtime_event() | nil
  defdelegate event_at_seq(events, seq), to: Events

  @spec snapshot_surface(map(), map()) :: map()
  defdelegate snapshot_surface(surface, fallback), to: Events

  @spec normalize_events_with_snapshot_refs([runtime_event()]) :: [map()]
  defdelegate normalize_events_with_snapshot_refs(events), to: Wire

  @spec normalize_term(Types.wire_input() | atom()) :: Types.normalized_export_term()
  defdelegate normalize_term(term), to: Wire

  @spec decode_import_body(String.t() | map()) :: {:ok, map()} | {:error, Types.protocol_error()}
  defdelegate decode_import_body(input), to: Import, as: :decode_body

  @spec validate_import_body(Types.import_trace_body()) :: :ok | {:error, Types.protocol_error()}
  defdelegate validate_import_body(body), to: Import, as: :validate_body

  @spec maybe_match_import_slug(Types.import_trace_body(), String.t(), keyword()) ::
          :ok | {:error, Types.protocol_error()}
  defdelegate maybe_match_import_slug(body, project_slug, opts), to: Import, as: :maybe_match_slug

  @spec parse_import_state(Types.import_trace_body(), keyword()) :: map()
  defdelegate parse_import_state(body, opts \\ []), to: Import, as: :parse_state
end
