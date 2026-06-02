defmodule Ide.Debugger.TraceExchange.FingerprintCompare do
  @moduledoc false

  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Debugger.TraceExchange.Events
  alias Ide.Debugger.Types
  alias Ide.Debugger.WireValues

  @type runtime_event :: Types.runtime_event()

  @spec build([runtime_event()], integer() | nil, integer() | nil) ::
          Types.fingerprint_compare_result()
  def build(events, compare_cursor_seq, baseline_cursor_seq) when is_list(events) do
    current_seq = resolve_export_compare_cursor(events, compare_cursor_seq)
    baseline_seq = resolve_export_baseline_cursor(events, baseline_cursor_seq, current_seq)
    current_event = Events.event_at_seq(events, current_seq)
    baseline_event = Events.event_at_seq(events, baseline_seq)

    current_fingerprints = event_runtime_fingerprints(current_event)
    baseline_fingerprints = event_runtime_fingerprints(baseline_event)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current = Map.get(current_fingerprints, surface)
        baseline = Map.get(baseline_fingerprints, surface)

        if is_map(current) or is_map(baseline) do
          current_model_sha = WireValues.map_value(current, "runtime_model_sha256")
          baseline_model_sha = WireValues.map_value(baseline, "runtime_model_sha256")
          current_view_sha = WireValues.map_value(current, "view_tree_sha256")
          baseline_view_sha = WireValues.map_value(baseline, "view_tree_sha256")
          current_protocol_inbound_count = WireValues.map_value(current, "protocol_inbound_count")

          baseline_protocol_inbound_count =
            WireValues.map_value(baseline, "protocol_inbound_count")

          current_protocol_message_count = WireValues.map_value(current, "protocol_message_count")

          baseline_protocol_message_count =
            WireValues.map_value(baseline, "protocol_message_count")

          current_protocol_last_inbound_message =
            WireValues.map_value(current, "protocol_last_inbound_message")

          baseline_protocol_last_inbound_message =
            WireValues.map_value(baseline, "protocol_last_inbound_message")

          current_execution_backend = WireValues.map_value(current, "execution_backend")
          baseline_execution_backend = WireValues.map_value(baseline, "execution_backend")

          current_external_fallback_reason =
            WireValues.map_value(current, "external_fallback_reason")

          baseline_external_fallback_reason =
            WireValues.map_value(baseline, "external_fallback_reason")

          current_target_numeric_key = WireValues.map_value(current, "target_numeric_key")
          baseline_target_numeric_key = WireValues.map_value(baseline, "target_numeric_key")

          current_target_numeric_key_source =
            WireValues.map_value(current, "target_numeric_key_source")

          baseline_target_numeric_key_source =
            WireValues.map_value(baseline, "target_numeric_key_source")

          current_target_boolean_key = WireValues.map_value(current, "target_boolean_key")
          baseline_target_boolean_key = WireValues.map_value(baseline, "target_boolean_key")

          current_target_boolean_key_source =
            WireValues.map_value(current, "target_boolean_key_source")

          baseline_target_boolean_key_source =
            WireValues.map_value(baseline, "target_boolean_key_source")

          current_active_target_key = WireValues.map_value(current, "active_target_key")
          baseline_active_target_key = WireValues.map_value(baseline, "active_target_key")

          current_active_target_key_source =
            WireValues.map_value(current, "active_target_key_source")

          baseline_active_target_key_source =
            WireValues.map_value(baseline, "active_target_key_source")

          backend_changed =
            current_execution_backend != baseline_execution_backend or
              current_external_fallback_reason != baseline_external_fallback_reason

          key_target_changed =
            current_target_numeric_key != baseline_target_numeric_key or
              current_target_numeric_key_source != baseline_target_numeric_key_source or
              current_target_boolean_key != baseline_target_boolean_key or
              current_target_boolean_key_source != baseline_target_boolean_key_source or
              current_active_target_key != baseline_active_target_key or
              current_active_target_key_source != baseline_active_target_key_source

          Map.put(acc, Atom.to_string(surface), %{
            "changed" =>
              current_model_sha != baseline_model_sha or
                current_view_sha != baseline_view_sha or
                current_protocol_inbound_count != baseline_protocol_inbound_count or
                current_protocol_message_count != baseline_protocol_message_count or
                current_protocol_last_inbound_message != baseline_protocol_last_inbound_message or
                backend_changed or
                key_target_changed,
            "backend_changed" => backend_changed,
            "key_target_changed" => key_target_changed,
            "current_model_sha" => current_model_sha,
            "baseline_model_sha" => baseline_model_sha,
            "current_view_sha" => current_view_sha,
            "baseline_view_sha" => baseline_view_sha,
            "current_protocol_inbound_count" => current_protocol_inbound_count,
            "baseline_protocol_inbound_count" => baseline_protocol_inbound_count,
            "current_protocol_message_count" => current_protocol_message_count,
            "baseline_protocol_message_count" => baseline_protocol_message_count,
            "current_protocol_last_inbound_message" => current_protocol_last_inbound_message,
            "baseline_protocol_last_inbound_message" => baseline_protocol_last_inbound_message,
            "current_execution_backend" => current_execution_backend,
            "baseline_execution_backend" => baseline_execution_backend,
            "current_external_fallback_reason" => current_external_fallback_reason,
            "baseline_external_fallback_reason" => baseline_external_fallback_reason,
            "current_target_numeric_key" => current_target_numeric_key,
            "baseline_target_numeric_key" => baseline_target_numeric_key,
            "current_target_numeric_key_source" => current_target_numeric_key_source,
            "baseline_target_numeric_key_source" => baseline_target_numeric_key_source,
            "current_target_boolean_key" => current_target_boolean_key,
            "baseline_target_boolean_key" => baseline_target_boolean_key,
            "current_target_boolean_key_source" => current_target_boolean_key_source,
            "baseline_target_boolean_key_source" => baseline_target_boolean_key_source,
            "current_active_target_key" => current_active_target_key,
            "baseline_active_target_key" => baseline_active_target_key,
            "current_active_target_key_source" => current_active_target_key_source,
            "baseline_active_target_key_source" => baseline_active_target_key_source
          })
        else
          acc
        end
      end)

    %{
      "current_cursor_seq" => current_seq,
      "baseline_cursor_seq" => baseline_seq,
      "changed_surface_count" =>
        Enum.count(Map.values(surfaces), &WireValues.map_value(&1, "changed")),
      "backend_changed_surface_count" =>
        Enum.count(Map.values(surfaces), &WireValues.map_value(&1, "backend_changed")),
      "key_target_changed_surface_count" =>
        Enum.count(Map.values(surfaces), &WireValues.map_value(&1, "key_target_changed")),
      "key_target_drift_detail" =>
        RuntimeFingerprintDrift.key_target_drift_detail(%{surfaces: surfaces},
          compare_key_keys: [:baseline_active_target_key],
          compare_source_keys: [:baseline_active_target_key_source]
        ),
      "drift_detail" =>
        RuntimeFingerprintDrift.merge_drift_detail(
          RuntimeFingerprintDrift.backend_drift_detail(%{surfaces: surfaces},
            compare_backend_keys: [:baseline_execution_backend],
            compare_reason_keys: [:baseline_external_fallback_reason]
          ),
          RuntimeFingerprintDrift.key_target_drift_detail(%{surfaces: surfaces},
            compare_key_keys: [:baseline_active_target_key],
            compare_source_keys: [:baseline_active_target_key_source]
          )
        ),
      "surfaces" => surfaces
    }
  end

  defp resolve_export_compare_cursor(events, cursor_seq) when is_list(events) do
    CursorSeq.resolve_at_or_before(events, cursor_seq)
  end

  defp resolve_export_baseline_cursor(events, baseline_cursor_seq, current_seq)
       when is_list(events) and is_integer(current_seq) do
    CursorSeq.resolve_before(events, current_seq, baseline_cursor_seq)
  end

  defp resolve_export_baseline_cursor(_events, _baseline_cursor_seq, _current_seq), do: nil

  defp event_runtime_fingerprints(nil), do: %{watch: nil, companion: nil, phone: nil}

  defp event_runtime_fingerprints(event) when is_map(event) do
    %{
      watch: runtime_fingerprint_from_surface(Map.get(event, :watch)),
      companion: runtime_fingerprint_from_surface(Map.get(event, :companion)),
      phone: runtime_fingerprint_from_surface(Map.get(event, :phone))
    }
  end

  defp runtime_fingerprint_from_surface(surface) when is_map(surface) do
    model = Map.get(surface, :model)
    model = if is_map(model), do: model, else: %{}
    runtime = Map.get(model, "runtime_execution")
    runtime = if is_map(runtime), do: runtime, else: %{}

    fingerprint = %{
      "runtime_model_sha256" =>
        WireValues.map_value(model, "runtime_model_sha256") ||
          WireValues.map_value(runtime, "runtime_model_sha256"),
      "view_tree_sha256" =>
        WireValues.map_value(model, "runtime_view_tree_sha256") ||
          WireValues.map_value(runtime, "view_tree_sha256"),
      "runtime_mode" => WireValues.map_value(model, "runtime_execution_mode"),
      "engine" => WireValues.map_value(runtime, "engine"),
      "execution_backend" => WireValues.map_value(runtime, "execution_backend"),
      "external_fallback_reason" => WireValues.map_value(runtime, "external_fallback_reason"),
      "target_numeric_key" => WireValues.map_value(runtime, "target_numeric_key"),
      "target_numeric_key_source" => WireValues.map_value(runtime, "target_numeric_key_source"),
      "target_boolean_key" => WireValues.map_value(runtime, "target_boolean_key"),
      "target_boolean_key_source" => WireValues.map_value(runtime, "target_boolean_key_source"),
      "active_target_key" => WireValues.map_value(runtime, "active_target_key"),
      "active_target_key_source" => WireValues.map_value(runtime, "active_target_key_source"),
      "protocol_inbound_count" =>
        WireValues.map_value(model, "protocol_inbound_count") ||
          WireValues.map_value(
            WireValues.map_value(model, "runtime_model"),
            "protocol_inbound_count"
          ),
      "protocol_message_count" =>
        case Map.get(surface, :protocol_messages) do
          xs when is_list(xs) and xs != [] -> length(xs)
          _ -> nil
        end,
      "protocol_last_inbound_message" =>
        WireValues.map_value(model, "protocol_last_inbound_message") ||
          WireValues.map_value(
            WireValues.map_value(model, "runtime_model"),
            "protocol_last_inbound_message"
          )
    }

    if Enum.any?(Map.values(fingerprint), &(!is_nil(&1))), do: fingerprint, else: nil
  end

  defp runtime_fingerprint_from_surface(_), do: nil
end
