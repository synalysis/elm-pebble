defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Ide.Debugger.RuntimeArtifacts
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util
  def view_tree_outline(nil), do: "(no snapshot)"

  def view_tree_outline(runtime) when is_map(runtime) do
    tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    case tree do
      nil -> "(no view tree in snapshot)"
      node -> format_view_tree_node(node, 0) |> String.trim_trailing()
    end
  end

  def view_tree_outline(_), do: "(no snapshot)"
  @spec model_diagnostic_preview(map() | nil) :: [map()]
  def model_diagnostic_preview(nil), do: []

  def model_diagnostic_preview(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}

    list =
      Map.get(model, "elmc_diagnostic_preview") ||
        Map.get(model, :elmc_diagnostic_preview) ||
        []

    if is_list(list), do: list, else: []
  end

  def model_diagnostic_preview(_), do: []

  @spec event_diagnostic_preview(map() | nil) :: [map()]
  def event_diagnostic_preview(nil), do: []

  def event_diagnostic_preview(%{} = event) do
    payload = Map.get(event, :payload) || %{}

    list =
      Map.get(payload, :diagnostic_preview) ||
        Map.get(payload, "diagnostic_preview") ||
        []

    if is_list(list), do: list, else: []
  end

  def event_diagnostic_preview(_), do: []

  @doc """
  Resolves the capped Elmc diagnostic rows for a timeline cursor: prefers `payload.diagnostic_preview`
  on the selected event, otherwise `elmc_diagnostic_preview` on the first non-empty embedded runtime
  (watch, then companion, then phone).
  Returns `%{source: \"event_payload\" | \"cursor_model\" | \"cursor_model_companion\" | \"cursor_model_phone\" | \"none\", rows: [map()]}`.
  """
  @spec diagnostics_preview_at_cursor([map()], Types.maybe_non_neg_integer()) :: %{
          source: String.t(),
          rows: [map()]
        }
  def diagnostics_preview_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = Timeline.normalize_cursor_seq(events, cursor_seq)

    selected =
      if is_integer(normalized) do
        Enum.find(events, &(&1.seq == normalized))
      else
        nil
      end

    case event_diagnostic_preview(selected) do
      [] ->
        watch = if selected, do: Map.get(selected, :watch), else: nil
        companion = if selected, do: Map.get(selected, :companion), else: nil
        phone = if selected, do: Map.get(selected, :phone), else: nil

        watch_rows = model_diagnostic_preview(watch)
        companion_rows = model_diagnostic_preview(companion)
        phone_rows = model_diagnostic_preview(phone)

        cond do
          watch_rows != [] ->
            %{source: "cursor_model", rows: watch_rows}

          companion_rows != [] ->
            %{source: "cursor_model_companion", rows: companion_rows}

          phone_rows != [] ->
            %{source: "cursor_model_phone", rows: phone_rows}

          true ->
            %{source: "none", rows: []}
        end

      rows ->
        %{source: "event_payload", rows: rows}
    end
  end

  @spec diagnostics_preview_source_label(String.t()) :: String.t()
  def diagnostics_preview_source_label("event_payload"), do: "selected event payload"
  def diagnostics_preview_source_label("cursor_model"), do: "cursor model (watch)"
  def diagnostics_preview_source_label("cursor_model_companion"), do: "cursor model (companion)"
  def diagnostics_preview_source_label("cursor_model_phone"), do: "cursor model (phone)"
  def diagnostics_preview_source_label("none"), do: "none"
  def diagnostics_preview_source_label(other), do: other

  @doc """
  Returns debugger contract maps for each surface at the timeline cursor
  (from the selected event's `watch` / `companion` / `phone` snapshots). Values are `nil` when absent.
  """
  @spec debugger_contract_at_cursor([map()], Types.maybe_non_neg_integer()) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  def debugger_contract_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = Timeline.normalize_cursor_seq(events, cursor_seq)

    selected =
      if is_integer(normalized) do
        Enum.find(events, &(&1.seq == normalized))
      else
        nil
      end

    if selected do
      %{
        watch: runtime_debugger_contract(Map.get(selected, :watch)),
        companion: runtime_debugger_contract(Map.get(selected, :companion)),
        phone: runtime_debugger_contract(Map.get(selected, :phone))
      }
    else
      %{watch: nil, companion: nil, phone: nil}
    end
  end

  def elm_introspect_at_cursor(events, cursor_seq),
    do: debugger_contract_at_cursor(events, cursor_seq)

  @doc """
  Returns runtime fingerprint summaries for watch/companion/phone at the timeline cursor.
  """
  @spec runtime_fingerprints_at_cursor([map()], Types.maybe_non_neg_integer()) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  def runtime_fingerprints_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = Timeline.normalize_cursor_seq(events, cursor_seq)

    selected =
      if is_integer(normalized) do
        Enum.find(events, &(&1.seq == normalized))
      else
        nil
      end

    if selected do
      %{
        watch: runtime_fingerprint(Map.get(selected, :watch)),
        companion: runtime_fingerprint(Map.get(selected, :companion)),
        phone: runtime_fingerprint(Map.get(selected, :phone))
      }
    else
      %{watch: nil, companion: nil, phone: nil}
    end
  end

  @doc """
  Compares runtime fingerprint hashes at `cursor_seq` vs `compare_cursor_seq`.
  """
  @spec runtime_fingerprint_compare_at_cursor(
          [map()],
          Types.maybe_non_neg_integer(),
          Types.maybe_non_neg_integer()
        ) :: map() | nil
  def runtime_fingerprint_compare_at_cursor(_events, _cursor_seq, nil), do: nil

  def runtime_fingerprint_compare_at_cursor(events, cursor_seq, compare_cursor_seq)
      when is_list(events) do
    current_cursor = Timeline.normalize_cursor_seq(events, cursor_seq)
    compare_cursor = Timeline.normalize_cursor_seq(events, compare_cursor_seq)

    current = runtime_fingerprints_at_cursor(events, current_cursor)
    compare = runtime_fingerprints_at_cursor(events, compare_cursor)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current_fp = Map.get(current, surface)
        compare_fp = Map.get(compare, surface)
        current_model_sha = Util.map_string(current_fp || %{}, :runtime_model_sha256)
        compare_model_sha = Util.map_string(compare_fp || %{}, :runtime_model_sha256)
        current_view_sha = Util.map_string(current_fp || %{}, :view_tree_sha256)
        compare_view_sha = Util.map_string(compare_fp || %{}, :view_tree_sha256)
        current_execution_backend = Util.map_scalar_string(current_fp || %{}, :execution_backend)
        compare_execution_backend = Util.map_scalar_string(compare_fp || %{}, :execution_backend)

        current_external_fallback_reason =
          Util.map_scalar_string(current_fp || %{}, :external_fallback_reason)

        compare_external_fallback_reason =
          Util.map_scalar_string(compare_fp || %{}, :external_fallback_reason)

        current_target_numeric_key =
          Util.map_scalar_string(current_fp || %{}, :target_numeric_key)

        compare_target_numeric_key =
          Util.map_scalar_string(compare_fp || %{}, :target_numeric_key)

        current_target_numeric_key_source =
          Util.map_scalar_string(current_fp || %{}, :target_numeric_key_source)

        compare_target_numeric_key_source =
          Util.map_scalar_string(compare_fp || %{}, :target_numeric_key_source)

        current_target_boolean_key =
          Util.map_scalar_string(current_fp || %{}, :target_boolean_key)

        compare_target_boolean_key =
          Util.map_scalar_string(compare_fp || %{}, :target_boolean_key)

        current_target_boolean_key_source =
          Util.map_scalar_string(current_fp || %{}, :target_boolean_key_source)

        compare_target_boolean_key_source =
          Util.map_scalar_string(compare_fp || %{}, :target_boolean_key_source)

        current_active_target_key = Util.map_scalar_string(current_fp || %{}, :active_target_key)
        compare_active_target_key = Util.map_scalar_string(compare_fp || %{}, :active_target_key)

        current_active_target_key_source =
          Util.map_scalar_string(current_fp || %{}, :active_target_key_source)

        compare_active_target_key_source =
          Util.map_scalar_string(compare_fp || %{}, :active_target_key_source)

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

  @spec backend_drift_detail(map() | nil, pos_integer()) :: String.t() | nil
  def backend_drift_detail(compare, max_reason_len \\ 72)

  def backend_drift_detail(compare, max_reason_len)
      when is_map(compare) and is_integer(max_reason_len) and max_reason_len > 3 do
    RuntimeFingerprintDrift.backend_drift_detail(compare, max_reason_len: max_reason_len)
  end

  def backend_drift_detail(_compare, _max_reason_len), do: nil

  @spec key_target_drift_detail(map() | nil, pos_integer()) :: String.t() | nil
  def key_target_drift_detail(compare, max_len \\ 72)

  def key_target_drift_detail(compare, max_len)
      when is_map(compare) and is_integer(max_len) and max_len > 3 do
    RuntimeFingerprintDrift.key_target_drift_detail(compare, max_len: max_len)
  end

  def key_target_drift_detail(_compare, _max_len), do: nil

  @spec merge_drift_detail(String.t() | nil, String.t() | nil) :: String.t() | nil
  def merge_drift_detail(backend_detail, key_target_detail),
    do: RuntimeFingerprintDrift.merge_drift_detail(backend_detail, key_target_detail)

  @spec runtime_debugger_contract(map()) :: map()
  defp runtime_debugger_contract(nil), do: nil

  defp runtime_debugger_contract(%{} = rt), do: RuntimeArtifacts.introspect(rt)

  defp runtime_debugger_contract(_), do: nil

  @spec runtime_fingerprint(map()) :: map()
  defp runtime_fingerprint(nil), do: nil

  defp runtime_fingerprint(%{} = rt) do
    model = Map.get(rt, :model) || %{}
    runtime = Map.get(model, "runtime_execution") || Map.get(model, :runtime_execution) || %{}
    protocol_messages = Map.get(rt, :protocol_messages)
    protocol_messages = if is_list(protocol_messages), do: protocol_messages, else: []

    fingerprint = %{
      runtime_mode: Util.map_string(model, :runtime_execution_mode),
      engine: Util.map_string(runtime, :engine),
      execution_backend: Util.map_scalar_string(runtime, :execution_backend),
      external_fallback_reason: Util.map_scalar_string(runtime, :external_fallback_reason),
      runtime_model_source:
        Util.map_string(model, :runtime_model_source) ||
          Util.map_string(runtime, :runtime_model_source),
      view_tree_source: Util.map_string(runtime, :view_tree_source),
      runtime_model_entry_count: Util.map_integer(runtime, :runtime_model_entry_count),
      view_tree_node_count: Util.map_integer(runtime, :view_tree_node_count),
      target_numeric_key: Util.map_scalar_string(runtime, :target_numeric_key),
      target_numeric_key_source: Util.map_scalar_string(runtime, :target_numeric_key_source),
      target_boolean_key: Util.map_scalar_string(runtime, :target_boolean_key),
      target_boolean_key_source: Util.map_scalar_string(runtime, :target_boolean_key_source),
      active_target_key: Util.map_scalar_string(runtime, :active_target_key),
      active_target_key_source: Util.map_scalar_string(runtime, :active_target_key_source),
      protocol_inbound_count:
        Util.map_integer(model, :protocol_inbound_count) ||
          Util.map_integer(Map.get(model, "runtime_model") || %{}, :protocol_inbound_count),
      protocol_message_count:
        if(protocol_messages == [], do: nil, else: length(protocol_messages)),
      protocol_last_inbound_message:
        Util.map_string(model, :protocol_last_inbound_message) ||
          Util.map_string(Map.get(model, "runtime_model") || %{}, :protocol_last_inbound_message),
      runtime_model_sha256:
        Util.map_string(model, :runtime_model_sha256) ||
          Util.map_string(runtime, :runtime_model_sha256),
      view_tree_sha256:
        Util.map_string(model, :runtime_view_tree_sha256) ||
          Util.map_string(runtime, :view_tree_sha256)
    }

    if Enum.any?(Map.values(fingerprint), &(!is_nil(&1))), do: fingerprint, else: nil
  end

  defp runtime_fingerprint(_), do: nil

  @spec format_view_tree_node(Types.view_tree(), non_neg_integer()) :: String.t()
  defp format_view_tree_node(node, depth) when is_map(node) do
    indent = String.duplicate("  ", depth)
    type = Map.get(node, :type) || Map.get(node, "type") || "node"
    line = "#{indent}- #{type}\n"
    children = Map.get(node, :children) || Map.get(node, "children") || []

    child_lines =
      if is_list(children) do
        children
        |> Enum.map(fn
          child when is_map(child) -> format_view_tree_node(child, depth + 1)
          other -> "#{indent}  - #{inspect(other)}\n"
        end)
        |> Enum.join("")
      else
        ""
      end

    line <> child_lines
  end

  defp format_view_tree_node(other, depth) do
    indent = String.duplicate("  ", depth)
    "#{indent}- #{inspect(other)}\n"
  end
end
