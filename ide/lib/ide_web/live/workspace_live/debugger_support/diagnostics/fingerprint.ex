defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.Fingerprint do
  @moduledoc false

  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.Cursor
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util.WireMap

  @type events :: Types.events()
  @type execution_model :: Types.execution_model()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type runtime_fingerprint :: DebuggerTypes.runtime_fingerprint()
  @type fingerprint_compare_result :: DebuggerTypes.fingerprint_compare_result()

  @spec runtime_fingerprint_compare_at_cursor(
          events(),
          maybe_non_neg_integer(),
          maybe_non_neg_integer()
        ) :: fingerprint_compare_result() | nil
  def runtime_fingerprint_compare_at_cursor(_events, _cursor_seq, nil), do: nil

  def runtime_fingerprint_compare_at_cursor(events, cursor_seq, compare_cursor_seq)
      when is_list(events) do
    current_cursor = Timeline.normalize_cursor_seq(events, cursor_seq)
    compare_cursor = Timeline.normalize_cursor_seq(events, compare_cursor_seq)

    current = Cursor.fingerprints_at_cursor(events, current_cursor)
    compare = Cursor.fingerprints_at_cursor(events, compare_cursor)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current_fp = Map.get(current, surface)
        compare_fp = Map.get(compare, surface)
        current_model_sha = WireMap.map_string(current_fp || %{}, :runtime_model_sha256)
        compare_model_sha = WireMap.map_string(compare_fp || %{}, :runtime_model_sha256)
        current_view_sha = WireMap.map_string(current_fp || %{}, :view_tree_sha256)
        compare_view_sha = WireMap.map_string(compare_fp || %{}, :view_tree_sha256)
        current_execution_backend = WireMap.map_scalar_string(current_fp || %{}, :execution_backend)
        compare_execution_backend = WireMap.map_scalar_string(compare_fp || %{}, :execution_backend)

        current_external_fallback_reason =
          WireMap.map_scalar_string(current_fp || %{}, :external_fallback_reason)

        compare_external_fallback_reason =
          WireMap.map_scalar_string(compare_fp || %{}, :external_fallback_reason)

        current_target_numeric_key =
          WireMap.map_scalar_string(current_fp || %{}, :target_numeric_key)

        compare_target_numeric_key =
          WireMap.map_scalar_string(compare_fp || %{}, :target_numeric_key)

        current_target_numeric_key_source =
          WireMap.map_scalar_string(current_fp || %{}, :target_numeric_key_source)

        compare_target_numeric_key_source =
          WireMap.map_scalar_string(compare_fp || %{}, :target_numeric_key_source)

        current_target_boolean_key =
          WireMap.map_scalar_string(current_fp || %{}, :target_boolean_key)

        compare_target_boolean_key =
          WireMap.map_scalar_string(compare_fp || %{}, :target_boolean_key)

        current_target_boolean_key_source =
          WireMap.map_scalar_string(current_fp || %{}, :target_boolean_key_source)

        compare_target_boolean_key_source =
          WireMap.map_scalar_string(compare_fp || %{}, :target_boolean_key_source)

        current_active_target_key = WireMap.map_scalar_string(current_fp || %{}, :active_target_key)
        compare_active_target_key = WireMap.map_scalar_string(compare_fp || %{}, :active_target_key)

        current_active_target_key_source =
          WireMap.map_scalar_string(current_fp || %{}, :active_target_key_source)

        compare_active_target_key_source =
          WireMap.map_scalar_string(compare_fp || %{}, :active_target_key_source)

        backend_changed =
          current_execution_backend != compare_execution_backend or
            current_external_fallback_reason != compare_external_fallback_reason

        key_target_changed =
          current_target_numeric_key != compare_target_numeric_key or
            current_target_numeric_key_source != compare_target_numeric_key_source or
            current_target_boolean_key != compare_target_boolean_key or
            current_target_boolean_key_source != compare_target_boolean_key_source or
            current_active_target_key != compare_active_target_key or
            current_active_target_key_source != compare_active_target_key_source

        if is_map(current_fp) or is_map(compare_fp) do
          Map.put(acc, surface, %{
            changed:
              current_model_sha != compare_model_sha or
                current_view_sha != compare_view_sha or
                backend_changed or
                key_target_changed,
            backend_changed: backend_changed,
            key_target_changed: key_target_changed,
            current_model_sha: current_model_sha,
            compare_model_sha: compare_model_sha,
            current_view_sha: current_view_sha,
            compare_view_sha: compare_view_sha,
            current_execution_backend: current_execution_backend,
            compare_execution_backend: compare_execution_backend,
            current_external_fallback_reason: current_external_fallback_reason,
            compare_external_fallback_reason: compare_external_fallback_reason,
            current_target_numeric_key: current_target_numeric_key,
            compare_target_numeric_key: compare_target_numeric_key,
            current_target_numeric_key_source: current_target_numeric_key_source,
            compare_target_numeric_key_source: compare_target_numeric_key_source,
            current_target_boolean_key: current_target_boolean_key,
            compare_target_boolean_key: compare_target_boolean_key,
            current_target_boolean_key_source: current_target_boolean_key_source,
            compare_target_boolean_key_source: compare_target_boolean_key_source,
            current_active_target_key: current_active_target_key,
            compare_active_target_key: compare_active_target_key,
            current_active_target_key_source: current_active_target_key_source,
            compare_active_target_key_source: compare_active_target_key_source
          })
        else
          acc
        end
      end)

    %{
      cursor_seq: current_cursor,
      compare_cursor_seq: compare_cursor,
      changed_surface_count: surfaces |> Map.values() |> Enum.count(fn row -> row[:changed] end),
      backend_changed_surface_count:
        surfaces |> Map.values() |> Enum.count(fn row -> row[:backend_changed] end),
      key_target_changed_surface_count:
        surfaces |> Map.values() |> Enum.count(fn row -> row[:key_target_changed] end),
      drift_detail:
        RuntimeFingerprintDrift.merge_drift_detail(
          backend_drift_detail(%{surfaces: surfaces}),
          key_target_drift_detail(%{surfaces: surfaces})
        ),
      key_target_drift_detail: key_target_drift_detail(%{surfaces: surfaces}),
      surfaces: surfaces
    }
  end

  @spec backend_drift_detail(fingerprint_compare_result() | nil, pos_integer()) ::
          String.t() | nil
  def backend_drift_detail(compare, max_reason_len \\ 72)

  def backend_drift_detail(compare, max_reason_len)
      when is_map(compare) and is_integer(max_reason_len) and max_reason_len > 3 do
    RuntimeFingerprintDrift.backend_drift_detail(compare, max_reason_len: max_reason_len)
  end

  def backend_drift_detail(_compare, _max_reason_len), do: nil

  @spec key_target_drift_detail(fingerprint_compare_result() | nil, pos_integer()) ::
          String.t() | nil
  def key_target_drift_detail(compare, max_len \\ 72)

  def key_target_drift_detail(compare, max_len)
      when is_map(compare) and is_integer(max_len) and max_len > 3 do
    RuntimeFingerprintDrift.key_target_drift_detail(compare, max_len: max_len)
  end

  def key_target_drift_detail(_compare, _max_len), do: nil

  @spec merge_drift_detail(String.t() | nil, String.t() | nil) :: String.t() | nil
  def merge_drift_detail(backend_detail, key_target_detail),
    do: RuntimeFingerprintDrift.merge_drift_detail(backend_detail, key_target_detail)

  @spec from_runtime(execution_model()) :: runtime_fingerprint() | nil
  def from_runtime(nil), do: nil

  def from_runtime(%{} = rt) do
    model = Map.get(rt, :model) || %{}
    runtime = Map.get(model, "runtime_execution") || Map.get(model, :runtime_execution) || %{}
    protocol_messages = Map.get(rt, :protocol_messages)
    protocol_messages = if is_list(protocol_messages), do: protocol_messages, else: []

    fingerprint = %{
      runtime_mode: WireMap.map_string(model, :runtime_execution_mode),
      engine: WireMap.map_string(runtime, :engine),
      execution_backend: WireMap.map_scalar_string(runtime, :execution_backend),
      external_fallback_reason: WireMap.map_scalar_string(runtime, :external_fallback_reason),
      runtime_model_source:
        WireMap.map_string(model, :runtime_model_source) ||
          WireMap.map_string(runtime, :runtime_model_source),
      view_tree_source: WireMap.map_string(runtime, :view_tree_source),
      runtime_model_entry_count: WireMap.map_integer(runtime, :runtime_model_entry_count),
      view_tree_node_count: WireMap.map_integer(runtime, :view_tree_node_count),
      target_numeric_key: WireMap.map_scalar_string(runtime, :target_numeric_key),
      target_numeric_key_source: WireMap.map_scalar_string(runtime, :target_numeric_key_source),
      target_boolean_key: WireMap.map_scalar_string(runtime, :target_boolean_key),
      target_boolean_key_source: WireMap.map_scalar_string(runtime, :target_boolean_key_source),
      active_target_key: WireMap.map_scalar_string(runtime, :active_target_key),
      active_target_key_source: WireMap.map_scalar_string(runtime, :active_target_key_source),
      protocol_inbound_count:
        WireMap.map_integer(model, :protocol_inbound_count) ||
          WireMap.map_integer(Map.get(model, "runtime_model") || %{}, :protocol_inbound_count),
      protocol_message_count:
        if(protocol_messages == [], do: nil, else: length(protocol_messages)),
      protocol_last_inbound_message:
        WireMap.map_string(model, :protocol_last_inbound_message) ||
          WireMap.map_string(Map.get(model, "runtime_model") || %{}, :protocol_last_inbound_message),
      runtime_model_sha256:
        WireMap.map_string(model, :runtime_model_sha256) ||
          WireMap.map_string(runtime, :runtime_model_sha256),
      view_tree_sha256:
        WireMap.map_string(model, :runtime_view_tree_sha256) ||
          WireMap.map_string(runtime, :view_tree_sha256)
    }

    if Enum.any?(Map.values(fingerprint), &(!is_nil(&1))), do: fingerprint, else: nil
  end

  def from_runtime(_), do: nil
end
