defmodule IdeWeb.WorkspaceLive.DebuggerSupport do
  @moduledoc false

  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.RuntimeFingerprintDrift
  alias Phoenix.Component

  @default_event_limit 500
  @type socket :: Phoenix.LiveView.Socket.t()
  @type maybe_non_neg_integer :: non_neg_integer() | nil
  @type timeline_kind :: :all | :protocol | :update | :render | :lifecycle | :other
  @type event_type_counts :: [{String.t(), non_neg_integer()}]
  @type event_summary :: %{
          seq: non_neg_integer(),
          type: String.t(),
          target: String.t() | nil,
          message: String.t() | nil
        }
  @type highlight_fragment :: %{text: String.t(), match?: boolean()}
  @type protocol_row :: %{
          seq: non_neg_integer(),
          kind: String.t(),
          from: String.t() | nil,
          to: String.t() | nil,
          message: String.t() | nil
        }
  @type update_message_row :: %{
          seq: non_neg_integer(),
          target: String.t() | nil,
          message: String.t() | nil
        }
  @type debugger_row :: %{
          seq: non_neg_integer(),
          debugger_seq: non_neg_integer(),
          raw_seq: non_neg_integer(),
          type: String.t(),
          target: String.t(),
          message: String.t(),
          message_source: String.t() | nil,
          selected_runtime: map() | nil,
          other_runtime: map() | nil,
          watch_runtime: map() | nil,
          companion_runtime: map() | nil,
          phone_runtime: map() | nil
        }
  @type render_event_row :: %{
          seq: non_neg_integer(),
          target: String.t() | nil,
          root: String.t() | nil
        }
  @type lifecycle_row :: %{
          seq: non_neg_integer(),
          type: String.t(),
          summary: String.t()
        }
  @type replay_preview_row :: %{
          seq: non_neg_integer(),
          target: String.t(),
          message: String.t()
        }
  @type replay_compare :: %{
          status: :none | :match | :mismatch,
          reason: String.t() | nil,
          preview_count: non_neg_integer(),
          applied_count: non_neg_integer(),
          mismatch_preview: replay_preview_row() | nil,
          mismatch_applied: replay_preview_row() | nil
        }

  @spec assign_defaults(socket()) :: socket()
  def assign_defaults(socket) do
    socket
    |> Component.assign(:debugger_state, nil)
    |> Component.assign(:debugger_event_limit, @default_event_limit)
    |> Component.assign(:debugger_since_seq, nil)
    |> Component.assign(:debugger_types, [])
    |> Component.assign(:debugger_filter_form, filter_form([], nil))
    |> Component.assign(:debugger_cursor_seq, nil)
    |> Component.assign(:debugger_selected_event, nil)
    |> Component.assign(:debugger_newer_event, nil)
    |> Component.assign(:debugger_older_event, nil)
    |> Component.assign(:debugger_cursor_watch_runtime, nil)
    |> Component.assign(:debugger_cursor_companion_runtime, nil)
    |> Component.assign(:debugger_cursor_phone_runtime, nil)
    |> Component.assign(:debugger_timeline_form, timeline_form(nil))
    |> Component.assign(:debugger_timeline_kind, :all)
    |> Component.assign(:debugger_timeline_limit, 30)
    |> Component.assign(:debugger_timeline_query, "")
    |> Component.assign(:debugger_advanced_debug_tools, false)
    |> Component.assign(:debugger_trigger_buttons, [])
    |> Component.assign(:debugger_watch_trigger_buttons, [])
    |> Component.assign(:debugger_companion_trigger_buttons, [])
    |> Component.assign(:debugger_watch_auto_fire, false)
    |> Component.assign(:debugger_companion_auto_fire, false)
    |> Component.assign(:debugger_auto_fire_subscriptions, [])
    |> Component.assign(:debugger_disabled_subscriptions, [])
    |> Component.assign(:debugger_trigger_modal_open, false)
    |> Component.assign(:debugger_trigger_form, Component.to_form(%{}, as: :debugger_trigger))
    |> Component.assign(:debugger_replay_form, replay_form("1", "all", true, "frozen"))
    |> Component.assign(:debugger_replay_preview, [])
    |> Component.assign(:debugger_replay_preview_seq, nil)
    |> Component.assign(:debugger_replay_live_warning, false)
    |> Component.assign(:debugger_replay_live_drift, nil)
    |> Component.assign(:debugger_last_replay, nil)
    |> Component.assign(:debugger_replay_compare, nil)
    |> Component.assign(:debugger_compare_baseline_seq, nil)
    |> Component.assign(:debugger_compare_form, compare_form(nil))
    |> Component.assign(:debugger_runtime_fingerprint_compare, nil)
    |> Component.assign(:debugger_trace_export, nil)
    |> Component.assign(:debugger_trace_export_context, nil)
    |> Component.assign(:debugger_export_form, export_trace_form())
    |> Component.assign(:debugger_import_form, import_trace_form())
    |> Component.assign(:debugger_cursor_seq, nil)
    |> Component.assign(:debugger_rows, [])
    |> Component.assign(:debugger_timeline_mode, "mixed")
    |> Component.assign(:debugger_selected_row, nil)
    |> Component.assign(:debugger_watch_runtime, nil)
    |> Component.assign(:debugger_companion_runtime, nil)
    |> Component.assign(:debugger_watch_view_runtime, nil)
  end

  @spec import_trace_form() :: Phoenix.HTML.Form.t()
  def import_trace_form do
    Component.to_form(%{"json" => ""}, as: :debugger_import)
  end

  @spec export_trace_form(maybe_non_neg_integer(), maybe_non_neg_integer()) ::
          Phoenix.HTML.Form.t()
  def export_trace_form(compare_cursor_seq \\ nil, baseline_cursor_seq \\ nil) do
    compare_text =
      if is_integer(compare_cursor_seq), do: Integer.to_string(compare_cursor_seq), else: ""

    baseline_text =
      if is_integer(baseline_cursor_seq), do: Integer.to_string(baseline_cursor_seq), else: ""

    Component.to_form(
      %{"compare_cursor_seq" => compare_text, "baseline_cursor_seq" => baseline_text},
      as: :debugger_export
    )
  end

  @spec set_export_form(socket(), map()) :: socket()
  def set_export_form(socket, params) when is_map(params) do
    compare_text = to_string(Map.get(params, "compare_cursor_seq", ""))
    baseline_text = to_string(Map.get(params, "baseline_cursor_seq", ""))

    Component.assign(
      socket,
      :debugger_export_form,
      Component.to_form(
        %{"compare_cursor_seq" => compare_text, "baseline_cursor_seq" => baseline_text},
        as: :debugger_export
      )
    )
  end

  @spec export_trace_opts(socket(), map()) :: keyword()
  def export_trace_opts(socket, params \\ %{}) when is_map(params) do
    requested_compare_cursor = parse_optional_non_neg_int(Map.get(params, "compare_cursor_seq"))
    requested_baseline_cursor = parse_optional_non_neg_int(Map.get(params, "baseline_cursor_seq"))
    compare_cursor_seq = requested_compare_cursor || socket.assigns[:debugger_cursor_seq]

    baseline_cursor_seq =
      requested_baseline_cursor || socket.assigns[:debugger_compare_baseline_seq]

    [event_limit: 500]
    |> maybe_put_export_cursor_opt(:compare_cursor_seq, compare_cursor_seq)
    |> maybe_put_export_cursor_opt(:baseline_cursor_seq, baseline_cursor_seq)
  end

  @spec refresh(socket()) :: socket()
  def refresh(socket) do
    case socket.assigns[:project] do
      nil ->
        socket
        |> Component.assign(:debugger_state, nil)
        |> Component.assign(:debugger_cursor_seq, nil)
        |> Component.assign(:debugger_selected_event, nil)
        |> Component.assign(:debugger_newer_event, nil)
        |> Component.assign(:debugger_older_event, nil)
        |> Component.assign(:debugger_cursor_watch_runtime, nil)
        |> Component.assign(:debugger_cursor_companion_runtime, nil)
        |> Component.assign(:debugger_cursor_phone_runtime, nil)
        |> Component.assign(:debugger_timeline_form, timeline_form(nil))
        |> Component.assign(:debugger_timeline_kind, :all)
        |> Component.assign(:debugger_timeline_limit, 30)
        |> Component.assign(:debugger_timeline_query, "")
        |> Component.assign(:debugger_advanced_debug_tools, false)
        |> Component.assign(:debugger_trigger_buttons, [])
        |> Component.assign(:debugger_watch_trigger_buttons, [])
        |> Component.assign(:debugger_companion_trigger_buttons, [])
        |> Component.assign(:debugger_watch_auto_fire, false)
        |> Component.assign(:debugger_companion_auto_fire, false)
        |> Component.assign(:debugger_auto_fire_subscriptions, [])
        |> Component.assign(:debugger_disabled_subscriptions, [])
        |> Component.assign(:debugger_trigger_modal_open, false)
        |> Component.assign(:debugger_trigger_form, Component.to_form(%{}, as: :debugger_trigger))
        |> Component.assign(:debugger_replay_form, replay_form("1", "all", true, "frozen"))
        |> Component.assign(:debugger_replay_preview, [])
        |> Component.assign(:debugger_replay_preview_seq, nil)
        |> Component.assign(:debugger_replay_live_warning, false)
        |> Component.assign(:debugger_replay_live_drift, nil)
        |> Component.assign(:debugger_last_replay, nil)
        |> Component.assign(:debugger_replay_compare, nil)
        |> Component.assign(:debugger_compare_baseline_seq, nil)
        |> Component.assign(:debugger_compare_form, compare_form(nil))
        |> Component.assign(:debugger_runtime_fingerprint_compare, nil)
        |> Component.assign(:debugger_trace_export, nil)
        |> Component.assign(:debugger_trace_export_context, nil)
        |> Component.assign(:debugger_export_form, export_trace_form())
        |> Component.assign(:debugger_import_form, import_trace_form())
        |> Component.assign(:debugger_cursor_seq, nil)
        |> Component.assign(:debugger_rows, [])
        |> Component.assign(:debugger_timeline_mode, "mixed")
        |> Component.assign(:debugger_selected_row, nil)
        |> Component.assign(:debugger_watch_runtime, nil)
        |> Component.assign(:debugger_companion_runtime, nil)
        |> Component.assign(:debugger_watch_view_runtime, nil)

      project ->
        {:ok, debugger_state} =
          Debugger.snapshot(project.slug,
            event_limit: socket.assigns[:debugger_event_limit] || @default_event_limit,
            since_seq: socket.assigns[:debugger_since_seq],
            types: socket.assigns[:debugger_types]
          )

        assign_timeline(socket, debugger_state)
    end
  end

  @spec refresh_following_debugger_latest(socket()) :: socket()
  def refresh_following_debugger_latest(socket) do
    follow_latest? = debugger_cursor_at_latest?(socket)
    socket = refresh(socket)

    if follow_latest? do
      jump_latest_debugger(socket)
    else
      socket
    end
  end

  @spec set_cursor_seq(socket(), term()) :: socket()
  def set_cursor_seq(socket, value) do
    case parse_since_seq(value) do
      nil -> socket
      seq -> assign_cursor(socket, seq)
    end
  end

  @spec set_debugger_cursor_seq(socket(), term()) :: socket()
  def set_debugger_cursor_seq(socket, value) do
    case parse_since_seq(value) do
      nil -> socket
      seq -> assign_debugger_cursor(socket, seq)
    end
  end

  @spec set_timeline_kind(socket(), term()) :: socket()
  def set_timeline_kind(socket, value) do
    kind =
      case value do
        "protocol" -> :protocol
        "update" -> :update
        "render" -> :render
        "lifecycle" -> :lifecycle
        "other" -> :other
        _ -> :all
      end

    Component.assign(socket, :debugger_timeline_kind, kind)
  end

  @spec set_timeline_limit(socket(), term()) :: socket()
  def set_timeline_limit(socket, value) do
    limit =
      case Integer.parse(to_string(value || "")) do
        {parsed, ""} when parsed in [10, 30, 100, 200] -> parsed
        _ -> 30
      end

    Component.assign(socket, :debugger_timeline_limit, limit)
  end

  @spec set_timeline_query(socket(), term()) :: socket()
  def set_timeline_query(socket, value) do
    query =
      value
      |> to_string()
      |> String.trim()

    Component.assign(socket, :debugger_timeline_query, query)
  end

  @spec set_debugger_timeline_mode(socket(), term()) :: socket()
  def set_debugger_timeline_mode(socket, value) do
    Component.assign(socket, :debugger_timeline_mode, normalize_debugger_timeline_mode(value))
  end

  @spec jump_latest(socket()) :: socket()
  def jump_latest(socket) do
    socket =
      case socket.assigns[:debugger_state] do
        %{events: events} when is_list(events) and events != [] ->
          [latest | _rest] = events
          assign_cursor(socket, latest.seq)

        _ ->
          socket
      end

    jump_latest_debugger(socket)
  end

  @spec step_back(socket()) :: socket()
  def step_back(socket) do
    move_cursor(socket, :back)
  end

  @spec step_forward(socket()) :: socket()
  def step_forward(socket) do
    move_cursor(socket, :forward)
  end

  @spec maybe_reload(socket(), String.t() | nil, String.t(), String.t(), String.t() | nil) ::
          socket()
  def maybe_reload(socket, rel_path, content, reason, source_root \\ nil) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        {:ok, _state} =
          Debugger.reload(project.slug, %{
            rel_path: rel_path,
            source: content,
            reason: reason,
            source_root: source_root || "watch"
          })

        refresh(socket)
    end
  end

  @spec apply_filter_inputs(socket(), String.t(), String.t()) :: socket()
  def apply_filter_inputs(socket, types_text, since_seq_text) do
    debugger_types = parse_types(types_text)
    debugger_since_seq = parse_since_seq(since_seq_text)

    socket
    |> Component.assign(:debugger_types, debugger_types)
    |> Component.assign(:debugger_since_seq, debugger_since_seq)
    |> Component.assign(:debugger_filter_form, filter_form(types_text, since_seq_text))
    |> refresh()
  end

  @spec apply_type_filter(socket(), String.t()) :: socket()
  def apply_type_filter(socket, type) do
    types =
      case type do
        "" -> []
        "*" -> []
        value -> [value]
      end

    since_seq = socket.assigns[:debugger_since_seq]
    since_seq_text = if is_integer(since_seq), do: Integer.to_string(since_seq), else: ""

    socket
    |> Component.assign(:debugger_types, types)
    |> Component.assign(
      :debugger_filter_form,
      filter_form(Enum.join(types, ","), since_seq_text)
    )
    |> refresh()
  end

  @spec replay_recent(socket(), map()) :: socket()
  def replay_recent(socket, params) when is_map(params) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        count = parse_replay_count(Map.get(params, "count") || Map.get(params, :count))
        target = parse_replay_target(Map.get(params, "target") || Map.get(params, :target))

        cursor_bound? =
          parse_replay_cursor_bound(
            Map.get(params, "cursor_bound") || Map.get(params, :cursor_bound)
          )

        replay_mode = parse_replay_mode(Map.get(params, "mode") || Map.get(params, :mode))

        cursor_seq =
          if cursor_bound? do
            socket.assigns[:debugger_cursor_seq]
          else
            nil
          end

        attrs_base = %{
          count: count,
          target: target,
          cursor_seq: cursor_seq,
          replay_mode: replay_mode,
          replay_drift_seq: socket.assigns[:debugger_replay_live_drift]
        }

        attrs =
          if replay_mode == "frozen" do
            Map.put(attrs_base, :replay_rows, socket.assigns[:debugger_replay_preview] || [])
          else
            attrs_base
          end

        {:ok, _state} = Debugger.replay_recent(project.slug, attrs)

        target_value = if is_binary(target), do: target, else: "all"

        socket
        |> Component.assign(
          :debugger_replay_form,
          replay_form(Integer.to_string(count), target_value, cursor_bound?, replay_mode)
        )
        |> refresh()
    end
  end

  @spec set_replay_form(socket(), map()) :: socket()
  def set_replay_form(socket, params) when is_map(params) do
    count = parse_replay_count(Map.get(params, "count") || Map.get(params, :count))
    target = parse_replay_target(Map.get(params, "target") || Map.get(params, :target))

    cursor_bound? =
      parse_replay_cursor_bound(Map.get(params, "cursor_bound") || Map.get(params, :cursor_bound))

    replay_mode = parse_replay_mode(Map.get(params, "mode") || Map.get(params, :mode))
    target_value = if is_binary(target), do: target, else: "all"

    socket
    |> Component.assign(
      :debugger_replay_form,
      replay_form(Integer.to_string(count), target_value, cursor_bound?, replay_mode)
    )
    |> assign_replay_preview(track_seq: true)
  end

  @spec set_compare_form(socket(), map()) :: socket()
  def set_compare_form(socket, params) when is_map(params) do
    baseline_seq = parse_optional_non_neg_int(Map.get(params, "baseline_seq"))

    socket
    |> Component.assign(:debugger_compare_baseline_seq, baseline_seq)
    |> Component.assign(:debugger_compare_form, compare_form(baseline_seq))
    |> assign_replay_preview()
  end

  @spec use_preview_as_compare_baseline(socket()) :: socket()
  def use_preview_as_compare_baseline(socket) do
    baseline_seq = socket.assigns[:debugger_replay_preview_seq]

    socket
    |> Component.assign(:debugger_compare_baseline_seq, baseline_seq)
    |> Component.assign(:debugger_compare_form, compare_form(baseline_seq))
    |> assign_replay_preview()
  end

  @spec replay_form_params(socket()) :: map()
  def replay_form_params(socket) do
    form = socket.assigns[:debugger_replay_form]

    %{
      "count" => form_value(form, :count) || "1",
      "target" => form_value(form, :target) || "all",
      "cursor_bound" => form_value(form, :cursor_bound) || "false",
      "mode" => form_value(form, :mode) || "frozen"
    }
  end

  @spec replay_preview_rows([map()], map()) :: [replay_preview_row()]
  def replay_preview_rows(events, opts) when is_list(events) and is_map(opts) do
    count = parse_replay_count(Map.get(opts, :count) || Map.get(opts, "count"))
    target = parse_replay_target(Map.get(opts, :target) || Map.get(opts, "target"))
    cursor_seq = Map.get(opts, :cursor_seq) || Map.get(opts, "cursor_seq")

    events
    |> maybe_filter_preview_events_at_or_before_seq(cursor_seq)
    |> Enum.filter(fn event ->
      event.type == "debugger.update_in" and is_map(event.payload)
    end)
    |> Enum.map(fn event ->
      payload = event.payload
      payload_target = Map.get(payload, :target) || Map.get(payload, "target")
      payload_message = Map.get(payload, :message) || Map.get(payload, "message")
      normalized_target = normalize_preview_target(payload_target)

      %{
        seq: event.seq,
        target: preview_target_label(normalized_target),
        message:
          if(is_binary(payload_message) and payload_message != "",
            do: payload_message,
            else: "Tick"
          ),
        normalized_target: normalized_target
      }
    end)
    |> Enum.filter(fn row ->
      is_nil(target) or row.normalized_target == target
    end)
    |> Enum.take(count)
    |> Enum.reverse()
    |> Enum.map(fn row ->
      %{seq: row.seq, target: row.target, message: row.message}
    end)
  end

  @spec replay_metadata_at_cursor([map()], maybe_non_neg_integer()) :: map() | nil
  def replay_metadata_at_cursor(events, cursor_seq) when is_list(events) do
    upper = timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.find(fn event ->
      event.type == "debugger.replay" and is_map(event.payload) and event.seq <= upper
    end)
    |> case do
      nil ->
        nil

      event ->
        payload = event.payload

        %{
          seq: event.seq,
          target: map_string(payload, :target),
          replay_source: map_string(payload, :replay_source),
          requested_count: map_integer(payload, :requested_count),
          replayed_count: map_integer(payload, :replayed_count),
          cursor_seq: map_integer(payload, :cursor_seq),
          replay_telemetry: map_map(payload, :replay_telemetry),
          replay_target_counts: map_map(payload, :replay_target_counts),
          replay_message_counts: map_map(payload, :replay_message_counts),
          replay_preview: map_list(payload, :replay_preview)
        }
    end
  end

  @spec replay_compare([replay_preview_row()], map() | nil) :: replay_compare()
  def replay_compare(preview_rows, nil) when is_list(preview_rows) do
    %{
      status: :none,
      reason: nil,
      preview_count: length(preview_rows),
      applied_count: 0,
      mismatch_preview: nil,
      mismatch_applied: nil
    }
  end

  def replay_compare(preview_rows, last_replay)
      when is_list(preview_rows) and is_map(last_replay) do
    applied_rows = normalize_replay_rows(Map.get(last_replay, :replay_preview) || [])
    preview_rows = Enum.map(preview_rows, &normalize_replay_row/1)
    applied_count = Map.get(last_replay, :replayed_count) || length(applied_rows)

    cond do
      length(preview_rows) != applied_count ->
        %{
          status: :mismatch,
          reason: "count",
          preview_count: length(preview_rows),
          applied_count: applied_count,
          mismatch_preview: List.first(preview_rows),
          mismatch_applied: List.first(applied_rows)
        }

      preview_rows != applied_rows ->
        {mismatch_preview, mismatch_applied} = first_row_mismatch(preview_rows, applied_rows)

        %{
          status: :mismatch,
          reason: "rows",
          preview_count: length(preview_rows),
          applied_count: applied_count,
          mismatch_preview: mismatch_preview,
          mismatch_applied: mismatch_applied
        }

      true ->
        %{
          status: :match,
          reason: nil,
          preview_count: length(preview_rows),
          applied_count: applied_count,
          mismatch_preview: nil,
          mismatch_applied: nil
        }
    end
  end

  @spec replay_live_warning?(String.t(), maybe_non_neg_integer(), [map()]) :: boolean()
  def replay_live_warning?(mode, preview_seq, events) when is_binary(mode) and is_list(events) do
    latest_seq =
      case events do
        [] ->
          nil

        list ->
          list
          |> Enum.map(& &1.seq)
          |> Enum.max()
      end

    mode == "live" and is_integer(preview_seq) and is_integer(latest_seq) and
      latest_seq > preview_seq
  end

  @spec replay_live_drift(String.t(), maybe_non_neg_integer(), [map()]) :: non_neg_integer() | nil
  def replay_live_drift(mode, preview_seq, events) when is_binary(mode) and is_list(events) do
    latest_seq =
      case events do
        [] -> nil
        list -> list |> Enum.map(& &1.seq) |> Enum.max()
      end

    if mode == "live" and is_integer(preview_seq) and is_integer(latest_seq) and
         latest_seq > preview_seq do
      latest_seq - preview_seq
    end
  end

  @spec replay_live_drift_severity(non_neg_integer() | nil) :: :none | :mild | :medium | :high
  def replay_live_drift_severity(nil), do: :none
  def replay_live_drift_severity(drift) when is_integer(drift) and drift <= 3, do: :mild
  def replay_live_drift_severity(drift) when is_integer(drift) and drift <= 10, do: :medium
  def replay_live_drift_severity(drift) when is_integer(drift), do: :high

  @spec runtime_json(map() | term()) :: String.t()
  def runtime_json(runtime) when is_map(runtime), do: Jason.encode!(runtime, pretty: true)
  def runtime_json(_runtime), do: "{}"

  @doc """
  Human-readable summary of `model.elm_introspect` for a frozen runtime snapshot (e.g. at timeline cursor).
  """
  @spec format_elm_introspect_brief(map() | nil) :: String.t()
  def format_elm_introspect_brief(nil), do: "(no snapshot)"

  def format_elm_introspect_brief(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    ei = Map.get(model, "elm_introspect") || Map.get(model, :elm_introspect)
    mode = Map.get(model, "elm_executor_mode") || Map.get(model, :elm_executor_mode)

    case ei do
      %{} = m ->
        prefix =
          if is_binary(mode) and mode != "",
            do: "elm_executor_mode: #{mode}\n",
            else: ""

        prefix <> format_elm_introspect_inner(m)

      _ ->
        format_elm_introspect_inner(nil)
    end
  end

  def format_elm_introspect_brief(_), do: "(no snapshot)"

  @spec format_elm_introspect_inner(term()) :: term()
  defp format_elm_introspect_inner(nil),
    do: "No parser snapshot merged for this surface at this seq."

  defp format_elm_introspect_inner(ei) when is_map(ei) do
    mod = Map.get(ei, "module") || Map.get(ei, :module) || "—"

    source_stats_line = format_source_stats_line(ei)

    exposing_line =
      format_module_exposing_line(Map.get(ei, "module_exposing") || Map.get(ei, :module_exposing))

    imps = Map.get(ei, "imported_modules") || Map.get(ei, :imported_modules) || []
    imps = if is_list(imps), do: imps, else: []

    import_line =
      case imps do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(14)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 14, do: s <> " …", else: s end)
      end

    ient = Map.get(ei, "import_entries") || Map.get(ei, :import_entries) || []
    ient = if is_list(ient), do: ient, else: []

    import_entries_line =
      case ient do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(6)
          |> Enum.map(&ElmIntrospect.import_entry_summary/1)
          |> Enum.join("; ")
          |> then(fn s -> if length(list) > 6, do: s <> " …", else: s end)
      end

    ta = Map.get(ei, "type_aliases") || Map.get(ei, :type_aliases) || []
    ta = if is_list(ta), do: ta, else: []
    uni = Map.get(ei, "unions") || Map.get(ei, :unions) || []
    uni = if is_list(uni), do: uni, else: []
    fns = Map.get(ei, "functions") || Map.get(ei, :functions) || []
    fns = if is_list(fns), do: fns, else: []

    alias_line =
      case ta do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    unions_line =
      case uni do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    functions_line =
      case fns do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(16)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 16, do: s <> " …", else: s end)
      end

    msgs = Map.get(ei, "msg_constructors") || Map.get(ei, :msg_constructors) || []
    msgs = if is_list(msgs), do: msgs, else: []

    msg_line =
      case msgs do
        [] ->
          "—"

        list ->
          shown = Enum.take(list, 10)

          Enum.join(shown, ", ") <>
            if(length(list) > length(shown), do: " …", else: "")
      end

    init = Map.get(ei, "init_model") || Map.get(ei, :init_model)
    init_line = brief_term_line(init, 220)

    ibs = Map.get(ei, "init_case_branches") || Map.get(ei, :init_case_branches) || []
    ibs = if is_list(ibs), do: ibs, else: []

    ics = Map.get(ei, "init_case_subject") || Map.get(ei, :init_case_subject)

    init_case_line =
      case ibs do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    init_case_header =
      cond do
        ibs != [] and is_binary(ics) and ics != "" ->
          "init (case #{ics}):"

        true ->
          "init (case …):"
      end

    icmd = Map.get(ei, "init_cmd_ops") || Map.get(ei, :init_cmd_ops) || []
    icmd = if is_list(icmd), do: icmd, else: []

    init_cmd_line =
      case icmd do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(10)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 10, do: s <> " …", else: s end)
      end

    vt = Map.get(ei, "view_tree") || Map.get(ei, :view_tree) || %{}
    root = Map.get(vt, "type") || Map.get(vt, :type) || "—"

    branches = Map.get(ei, "update_case_branches") || Map.get(ei, :update_case_branches) || []
    branches = if is_list(branches), do: branches, else: []

    upd_line =
      case branches do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    ucs = Map.get(ei, "update_case_subject") || Map.get(ei, :update_case_subject)

    upd_header =
      cond do
        branches != [] and is_binary(ucs) and ucs != "" ->
          "update (case #{ucs}):"

        true ->
          "update (case …):"
      end

    ucmd = Map.get(ei, "update_cmd_ops") || Map.get(ei, :update_cmd_ops) || []
    ucmd = if is_list(ucmd), do: ucmd, else: []

    update_cmd_line =
      case ucmd do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(10)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 10, do: s <> " …", else: s end)
      end

    vbr = Map.get(ei, "view_case_branches") || Map.get(ei, :view_case_branches) || []
    vbr = if is_list(vbr), do: vbr, else: []

    vcs = Map.get(ei, "view_case_subject") || Map.get(ei, :view_case_subject)

    view_case_line =
      case vbr do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    view_case_header =
      cond do
        vbr != [] and is_binary(vcs) and vcs != "" ->
          "view (case #{vcs}):"

        true ->
          "view (case …):"
      end

    scbs =
      Map.get(ei, "subscriptions_case_branches") || Map.get(ei, :subscriptions_case_branches) ||
        []

    scbs = if is_list(scbs), do: scbs, else: []

    scs = Map.get(ei, "subscriptions_case_subject") || Map.get(ei, :subscriptions_case_subject)

    subs_case_line =
      case scbs do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    subs_case_header =
      cond do
        scbs != [] and is_binary(scs) and scs != "" ->
          "subscriptions (case #{scs}):"

        true ->
          "subscriptions (case …):"
      end

    subs = Map.get(ei, "subscription_ops") || Map.get(ei, :subscription_ops) || []
    subs = if is_list(subs), do: subs, else: []

    sub_line =
      case subs do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(10)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 10, do: s <> " …", else: s end)
      end

    prts = Map.get(ei, "ports") || Map.get(ei, :ports) || []
    prts = if is_list(prts), do: prts, else: []

    ports_line =
      case prts do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    port_module =
      case Map.get(ei, "port_module") || Map.get(ei, :port_module) do
        true -> "yes"
        _ -> "no"
      end

    mp = Map.get(ei, "main_program") || Map.get(ei, :main_program)

    main_line =
      case mp do
        %{"target" => t, "kind" => k, "fields" => fs} when is_binary(t) ->
          fs = if is_list(fs), do: fs, else: []
          fld = fs |> Enum.take(8) |> Enum.join(", ")
          suffix = if length(fs) > 8, do: fld <> " …", else: fld
          suffix = if suffix != "", do: " {" <> suffix <> "}", else: ""
          "#{t} · #{k}#{suffix}"

        %{} = m ->
          t = Map.get(m, "target") || Map.get(m, :target)
          k = Map.get(m, "kind") || Map.get(m, :kind)

          if is_binary(t) and is_binary(k) do
            "#{t} · #{k}"
          else
            "—"
          end

        _ ->
          "—"
      end

    param_suffix =
      [
        {"init", Map.get(ei, "init_params") || Map.get(ei, :init_params)},
        {"update", Map.get(ei, "update_params") || Map.get(ei, :update_params)},
        {"view", Map.get(ei, "view_params") || Map.get(ei, :view_params)},
        {"subscriptions",
         Map.get(ei, "subscriptions_params") || Map.get(ei, :subscriptions_params)}
      ]
      |> Enum.flat_map(fn {label, xs} ->
        xs = if is_list(xs), do: xs, else: []
        if xs != [], do: ["#{label} λ: " <> Enum.join(xs, ", ")], else: []
      end)
      |> then(fn lines ->
        if lines == [], do: "", else: "\n" <> Enum.join(lines, "\n")
      end)

    """
    module: #{mod}
    source: #{source_stats_line}
    exposing: #{exposing_line}
    imports: #{import_line}
    import entries: #{import_entries_line}
    type aliases: #{alias_line}
    unions: #{unions_line}
    functions: #{functions_line}
    Msg: #{msg_line}
    main: #{main_line}
    #{upd_header} #{upd_line}
    update Cmd: #{update_cmd_line}
    #{subs_case_header} #{subs_case_line}
    subscriptions: #{sub_line}
    ports: #{ports_line}
    port module: #{port_module}
    init: #{init_line}
    #{init_case_header} #{init_case_line}
    init Cmd: #{init_cmd_line}
    #{view_case_header} #{view_case_line}
    view root: #{root}#{param_suffix}
    """
    |> String.trim()
  end

  @spec format_module_exposing_line(term()) :: term()
  defp format_module_exposing_line(".."), do: "(..)"

  defp format_module_exposing_line(names) when is_list(names) and names != [] do
    names
    |> Enum.take(16)
    |> Enum.join(", ")
    |> then(fn s -> if length(names) > 16, do: s <> " …", else: s end)
  end

  defp format_module_exposing_line(_), do: "—"

  @spec format_source_stats_line(term()) :: term()
  defp format_source_stats_line(ei) when is_map(ei) do
    bs = Map.get(ei, "source_byte_size") || Map.get(ei, :source_byte_size)
    ls = Map.get(ei, "source_line_count") || Map.get(ei, :source_line_count)

    cond do
      is_integer(bs) and bs >= 0 and is_integer(ls) and ls >= 0 ->
        "#{bs} bytes, #{ls} lines"

      is_integer(bs) and bs >= 0 ->
        "#{bs} bytes"

      is_integer(ls) and ls >= 0 ->
        "#{ls} lines"

      true ->
        "—"
    end
  end

  @spec brief_term_line(term(), term()) :: term()
  defp brief_term_line(nil, _), do: "—"

  defp brief_term_line(term, max_chars) when is_integer(max_chars) and max_chars > 0 do
    case Jason.encode(term) do
      {:ok, s} ->
        if String.length(s) <= max_chars do
          s
        else
          String.slice(s, 0, max_chars) <> "…"
        end

      {:error, _} ->
        "…"
    end
  end

  @spec view_tree_outline(map() | nil) :: String.t()
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
  @spec diagnostics_preview_at_cursor([map()], maybe_non_neg_integer()) :: %{
          source: String.t(),
          rows: [map()]
        }
  def diagnostics_preview_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = normalize_cursor_seq(events, cursor_seq)

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
  Returns `elm_introspect` maps embedded in each surface's model at the timeline cursor
  (from the selected event's `watch` / `companion` / `phone` snapshots). Values are `nil` when absent.
  """
  @spec elm_introspect_at_cursor([map()], maybe_non_neg_integer()) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  def elm_introspect_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = normalize_cursor_seq(events, cursor_seq)

    selected =
      if is_integer(normalized) do
        Enum.find(events, &(&1.seq == normalized))
      else
        nil
      end

    if selected do
      %{
        watch: runtime_elm_introspect(Map.get(selected, :watch)),
        companion: runtime_elm_introspect(Map.get(selected, :companion)),
        phone: runtime_elm_introspect(Map.get(selected, :phone))
      }
    else
      %{watch: nil, companion: nil, phone: nil}
    end
  end

  @doc """
  Returns runtime fingerprint summaries for watch/companion/phone at the timeline cursor.
  """
  @spec runtime_fingerprints_at_cursor([map()], maybe_non_neg_integer()) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  def runtime_fingerprints_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = normalize_cursor_seq(events, cursor_seq)

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
          maybe_non_neg_integer(),
          maybe_non_neg_integer()
        ) :: map() | nil
  def runtime_fingerprint_compare_at_cursor(_events, _cursor_seq, nil), do: nil

  def runtime_fingerprint_compare_at_cursor(events, cursor_seq, compare_cursor_seq)
      when is_list(events) do
    current_cursor = normalize_cursor_seq(events, cursor_seq)
    compare_cursor = normalize_cursor_seq(events, compare_cursor_seq)

    current = runtime_fingerprints_at_cursor(events, current_cursor)
    compare = runtime_fingerprints_at_cursor(events, compare_cursor)

    surfaces =
      [:watch, :companion, :phone]
      |> Enum.reduce(%{}, fn surface, acc ->
        current_fp = Map.get(current, surface)
        compare_fp = Map.get(compare, surface)
        current_model_sha = map_string(current_fp || %{}, :runtime_model_sha256)
        compare_model_sha = map_string(compare_fp || %{}, :runtime_model_sha256)
        current_view_sha = map_string(current_fp || %{}, :view_tree_sha256)
        compare_view_sha = map_string(compare_fp || %{}, :view_tree_sha256)
        current_execution_backend = map_scalar_string(current_fp || %{}, :execution_backend)
        compare_execution_backend = map_scalar_string(compare_fp || %{}, :execution_backend)

        current_external_fallback_reason =
          map_scalar_string(current_fp || %{}, :external_fallback_reason)

        compare_external_fallback_reason =
          map_scalar_string(compare_fp || %{}, :external_fallback_reason)

        current_target_numeric_key = map_scalar_string(current_fp || %{}, :target_numeric_key)
        compare_target_numeric_key = map_scalar_string(compare_fp || %{}, :target_numeric_key)

        current_target_numeric_key_source =
          map_scalar_string(current_fp || %{}, :target_numeric_key_source)

        compare_target_numeric_key_source =
          map_scalar_string(compare_fp || %{}, :target_numeric_key_source)

        current_target_boolean_key = map_scalar_string(current_fp || %{}, :target_boolean_key)
        compare_target_boolean_key = map_scalar_string(compare_fp || %{}, :target_boolean_key)

        current_target_boolean_key_source =
          map_scalar_string(current_fp || %{}, :target_boolean_key_source)

        compare_target_boolean_key_source =
          map_scalar_string(compare_fp || %{}, :target_boolean_key_source)

        current_active_target_key = map_scalar_string(current_fp || %{}, :active_target_key)
        compare_active_target_key = map_scalar_string(compare_fp || %{}, :active_target_key)

        current_active_target_key_source =
          map_scalar_string(current_fp || %{}, :active_target_key_source)

        compare_active_target_key_source =
          map_scalar_string(compare_fp || %{}, :active_target_key_source)

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

  @spec runtime_elm_introspect(term()) :: term()
  defp runtime_elm_introspect(nil), do: nil

  defp runtime_elm_introspect(%{} = rt) do
    model = Map.get(rt, :model) || %{}
    Map.get(model, "elm_introspect") || Map.get(model, :elm_introspect)
  end

  defp runtime_elm_introspect(_), do: nil

  @spec runtime_fingerprint(term()) :: term()
  defp runtime_fingerprint(nil), do: nil

  defp runtime_fingerprint(%{} = rt) do
    model = Map.get(rt, :model) || %{}
    runtime = Map.get(model, "elm_executor") || Map.get(model, :elm_executor) || %{}
    protocol_messages = Map.get(rt, :protocol_messages)
    protocol_messages = if is_list(protocol_messages), do: protocol_messages, else: []

    fingerprint = %{
      runtime_mode: map_string(model, :elm_executor_mode),
      engine: map_string(runtime, :engine),
      execution_backend: map_scalar_string(runtime, :execution_backend),
      external_fallback_reason: map_scalar_string(runtime, :external_fallback_reason),
      runtime_model_source:
        map_string(model, :runtime_model_source) || map_string(runtime, :runtime_model_source),
      view_tree_source: map_string(runtime, :view_tree_source),
      runtime_model_entry_count: map_integer(runtime, :runtime_model_entry_count),
      view_tree_node_count: map_integer(runtime, :view_tree_node_count),
      target_numeric_key: map_scalar_string(runtime, :target_numeric_key),
      target_numeric_key_source: map_scalar_string(runtime, :target_numeric_key_source),
      target_boolean_key: map_scalar_string(runtime, :target_boolean_key),
      target_boolean_key_source: map_scalar_string(runtime, :target_boolean_key_source),
      active_target_key: map_scalar_string(runtime, :active_target_key),
      active_target_key_source: map_scalar_string(runtime, :active_target_key_source),
      protocol_inbound_count:
        map_integer(model, :protocol_inbound_count) ||
          map_integer(Map.get(model, "runtime_model") || %{}, :protocol_inbound_count),
      protocol_message_count:
        if(protocol_messages == [], do: nil, else: length(protocol_messages)),
      protocol_last_inbound_message:
        map_string(model, :protocol_last_inbound_message) ||
          map_string(Map.get(model, "runtime_model") || %{}, :protocol_last_inbound_message),
      runtime_model_sha256:
        map_string(model, :runtime_model_sha256) || map_string(runtime, :runtime_model_sha256),
      view_tree_sha256:
        map_string(model, :runtime_view_tree_sha256) || map_string(runtime, :view_tree_sha256)
    }

    if Enum.any?(Map.values(fingerprint), &(!is_nil(&1))), do: fingerprint, else: nil
  end

  defp runtime_fingerprint(_), do: nil

  @spec format_view_tree_node(term(), term()) :: term()
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

  @spec event_json([map()] | term()) :: String.t()
  def event_json(events) when is_list(events) do
    events
    |> Enum.reverse()
    |> Jason.encode!(pretty: true)
  end

  def event_json(event) when is_map(event), do: Jason.encode!(event, pretty: true)
  def event_json(_events), do: "[]"

  @spec payload_diff_json(map() | nil, map() | nil) :: String.t()
  def payload_diff_json(base_event, compare_event)
      when is_map(base_event) and is_map(compare_event) do
    base_payload = Map.get(base_event, :payload, %{})
    compare_payload = Map.get(compare_event, :payload, %{})

    if is_map(base_payload) and is_map(compare_payload) do
      base_keys = Map.keys(base_payload) |> MapSet.new()
      compare_keys = Map.keys(compare_payload) |> MapSet.new()

      added_keys = MapSet.difference(compare_keys, base_keys) |> MapSet.to_list() |> Enum.sort()
      removed_keys = MapSet.difference(base_keys, compare_keys) |> MapSet.to_list() |> Enum.sort()

      changed_keys =
        MapSet.intersection(base_keys, compare_keys)
        |> MapSet.to_list()
        |> Enum.filter(fn key -> Map.get(base_payload, key) != Map.get(compare_payload, key) end)
        |> Enum.sort()

      diff = %{
        from_seq: Map.get(base_event, :seq),
        to_seq: Map.get(compare_event, :seq),
        from_type: Map.get(base_event, :type),
        to_type: Map.get(compare_event, :type),
        added: Map.take(compare_payload, added_keys),
        removed: Map.take(base_payload, removed_keys),
        changed:
          Map.new(changed_keys, fn key ->
            {key, %{from: Map.get(base_payload, key), to: Map.get(compare_payload, key)}}
          end)
      }

      Jason.encode!(diff, pretty: true)
    else
      "{}"
    end
  end

  def payload_diff_json(_base_event, _compare_event), do: "{}"

  @spec event_type_counts([map()] | term()) :: event_type_counts()
  def event_type_counts(events) when is_list(events) do
    events
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, grouped} -> {type, length(grouped)} end)
    |> Enum.sort_by(fn {type, _} -> type end)
  end

  def event_type_counts(_events), do: []

  @spec event_summaries([map()] | term()) :: [event_summary()]
  def event_summaries(events) when is_list(events) do
    Enum.map(events, fn event ->
      payload = Map.get(event, :payload, %{})

      %{
        seq: Map.get(event, :seq, 0),
        type: Map.get(event, :type, "unknown"),
        target: payload_target(payload),
        message: payload_message(payload)
      }
    end)
  end

  def event_summaries(_events), do: []

  @spec protocol_exchange_at_cursor([map()] | term(), maybe_non_neg_integer(), pos_integer()) :: [
          protocol_row()
        ]
  def protocol_exchange_at_cursor(events, cursor_seq, limit \\ 40)

  def protocol_exchange_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e ->
      e.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and e.seq <= upper
    end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}
      kind = if e.type == "debugger.protocol_tx", do: "tx", else: "rx"

      %{
        seq: e.seq,
        kind: kind,
        from: protocol_payload_field(payload, :from),
        to: protocol_payload_field(payload, :to),
        message: protocol_payload_field(payload, :message)
      }
    end)
  end

  def protocol_exchange_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec update_messages_at_cursor([map()] | term(), maybe_non_neg_integer(), pos_integer()) :: [
          update_message_row()
        ]
  def update_messages_at_cursor(events, cursor_seq, limit \\ 40)

  def update_messages_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e -> e.type == "debugger.update_in" and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}

      %{
        seq: e.seq,
        target: protocol_payload_field(payload, :target),
        message: protocol_payload_field(payload, :message)
      }
    end)
  end

  def update_messages_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec debugger_rows(map() | [map()] | term(), pos_integer()) :: [debugger_row()]
  def debugger_rows(source, limit \\ 80)

  def debugger_rows(%{} = debugger_state, limit) when is_integer(limit) and limit > 0 do
    case Map.get(debugger_state, :debugger_timeline) ||
           Map.get(debugger_state, "debugger_timeline") do
      rows when is_list(rows) and rows != [] ->
        rows
        |> Enum.sort_by(&debugger_row_seq/1, :desc)
        |> Enum.take(limit)
        |> Enum.map(&normalize_debugger_row/1)

      _ ->
        debugger_state
        |> Map.get(:events, Map.get(debugger_state, "events", []))
        |> debugger_rows(limit)
    end
  end

  def debugger_rows(events, limit) when is_list(events) and is_integer(limit) and limit > 0 do
    events
    |> Enum.filter(fn event ->
      Map.get(event, :type) in ["debugger.init_in", "debugger.update_in"]
    end)
    |> Enum.sort_by(&Map.get(&1, :seq, 0), :asc)
    |> Enum.take(-limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {event, debugger_seq} ->
      payload = Map.get(event, :payload) || %{}
      raw_seq = Map.get(event, :seq, 0)
      target = debugger_target(protocol_payload_field(payload, :target))

      watch_runtime = nearest_surface_runtime_at_or_before(events, raw_seq, :watch)
      companion_runtime = nearest_surface_runtime_at_or_before(events, raw_seq, :companion)
      phone_runtime = nearest_surface_runtime_at_or_before(events, raw_seq, :phone)

      %{
        seq: debugger_seq,
        debugger_seq: debugger_seq,
        raw_seq: raw_seq,
        type: debugger_type_from_event(event),
        target: target,
        message: protocol_payload_field(payload, :message) || "",
        message_source: protocol_payload_field(payload, :message_source),
        selected_runtime: debugger_target_runtime(target, watch_runtime, companion_runtime),
        other_runtime: debugger_other_runtime(target, watch_runtime, companion_runtime),
        watch_runtime: watch_runtime,
        companion_runtime: companion_runtime,
        phone_runtime: phone_runtime
      }
    end)
  end

  def debugger_rows(_source, _limit), do: []

  @spec debugger_rows_for_target([debugger_row()] | term(), String.t()) :: [debugger_row()]
  def debugger_rows_for_target(rows, target)
      when is_list(rows) and target in ["watch", "companion"] do
    rows
    |> Enum.filter(fn row -> Map.get(row, :target) == target end)
    |> newest_first()
  end

  def debugger_rows_for_target(_rows, _target), do: []

  @spec debugger_rows_for_mode([debugger_row()] | term(), String.t()) :: [debugger_row()]
  def debugger_rows_for_mode(rows, "watch"), do: debugger_rows_for_target(rows, "watch")
  def debugger_rows_for_mode(rows, "companion"), do: debugger_rows_for_target(rows, "companion")

  def debugger_rows_for_mode(rows, "mixed") when is_list(rows),
    do: newest_first(rows)

  def debugger_rows_for_mode(rows, "separate") when is_list(rows),
    do: newest_first(rows)

  def debugger_rows_for_mode(_rows, _mode), do: []

  @spec newest_first([map()]) :: [map()]
  defp newest_first(rows) when is_list(rows),
    do: Enum.sort_by(rows, &Map.get(&1, :seq, 0), :desc)

  @spec normalize_debugger_row(map()) :: debugger_row()
  defp normalize_debugger_row(row) when is_map(row) do
    seq = debugger_row_seq(row)
    raw_seq = Map.get(row, :raw_seq) || Map.get(row, "raw_seq") || seq
    target = debugger_target(Map.get(row, :target) || Map.get(row, "target"))
    watch_runtime = Map.get(row, :watch) || Map.get(row, "watch")
    companion_runtime = Map.get(row, :companion) || Map.get(row, "companion")
    phone_runtime = Map.get(row, :phone) || Map.get(row, "phone")

    %{
      seq: seq,
      debugger_seq: seq,
      raw_seq: raw_seq,
      type: Map.get(row, :type) || Map.get(row, "type") || "update",
      target: target,
      message: Map.get(row, :message) || Map.get(row, "message") || "",
      message_source: Map.get(row, :message_source) || Map.get(row, "message_source"),
      selected_runtime: debugger_target_runtime(target, watch_runtime, companion_runtime),
      other_runtime: debugger_other_runtime(target, watch_runtime, companion_runtime),
      watch_runtime: watch_runtime,
      companion_runtime: companion_runtime,
      phone_runtime: phone_runtime
    }
  end

  @spec debugger_row_seq(term()) :: non_neg_integer()
  defp debugger_row_seq(row) when is_map(row) do
    case Map.get(row, :seq) || Map.get(row, "seq") || Map.get(row, :debugger_seq) ||
           Map.get(row, "debugger_seq") do
      seq when is_integer(seq) and seq >= 0 -> seq
      _ -> 0
    end
  end

  defp debugger_row_seq(_row), do: 0

  @spec debugger_type_from_event(map()) :: String.t()
  defp debugger_type_from_event(%{type: "debugger.init_in"}), do: "init"
  defp debugger_type_from_event(%{type: "debugger.update_in"}), do: "update"
  defp debugger_type_from_event(_event), do: "update"

  @spec debugger_message_label(term()) :: String.t()
  def debugger_message_label(message) when is_binary(message) do
    case Regex.run(~r/^([A-Z][A-Za-z0-9_]*)(?:\s+)([\{\[].*)$/, String.trim(message)) do
      [_, constructor, json] ->
        case Jason.decode(json) do
          {:ok, value} -> "#{constructor} #{elm_value(value)}"
          {:error, _reason} -> message
        end

      _ ->
        message
    end
  end

  def debugger_message_label(nil), do: ""
  def debugger_message_label(message), do: to_string(message)

  @spec selected_debugger_row(map() | [map()] | term(), maybe_non_neg_integer()) ::
          debugger_row() | nil
  def selected_debugger_row(source, cursor_seq) do
    rows = debugger_rows(source, 500)
    newest_rows = Enum.sort_by(rows, &Map.get(&1, :seq, 0), :desc)
    oldest_rows = Enum.reverse(newest_rows)

    cond do
      rows == [] ->
        nil

      is_integer(cursor_seq) ->
        oldest_rows
        |> Enum.find(fn row -> row.seq >= cursor_seq end) || List.first(newest_rows)

      true ->
        List.first(newest_rows)
    end
  end

  @spec render_events_at_cursor([map()] | term(), maybe_non_neg_integer(), pos_integer()) :: [
          render_event_row()
        ]
  def render_events_at_cursor(events, cursor_seq, limit \\ 24)

  def render_events_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e -> e.type == "debugger.view_render" and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}

      %{
        seq: e.seq,
        target: protocol_payload_field(payload, :target),
        root: protocol_payload_field(payload, :root)
      }
    end)
  end

  def render_events_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec lifecycle_events_at_cursor([map()] | term(), maybe_non_neg_integer(), pos_integer()) :: [
          lifecycle_row()
        ]
  def lifecycle_events_at_cursor(events, cursor_seq, limit \\ 12)

  def lifecycle_events_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = timeline_upper_seq(events, cursor_seq)

    types = [
      "debugger.start",
      "debugger.reset",
      "debugger.reload",
      "debugger.elm_introspect",
      "debugger.elmc_check",
      "debugger.elmc_compile",
      "debugger.elmc_manifest"
    ]

    events
    |> Enum.filter(fn e -> e.type in types and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      %{
        seq: e.seq,
        type: e.type,
        summary: lifecycle_summary(e)
      }
    end)
  end

  def lifecycle_events_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec lifecycle_summary(map()) :: String.t()
  defp lifecycle_summary(%{type: "debugger.reload", payload: payload}) when is_map(payload) do
    root = protocol_payload_field(payload, :source_root) || "watch"
    path = protocol_payload_field(payload, :rel_path) || "—"
    rev = protocol_payload_field(payload, :revision) || "—"
    "#{root} · #{path} · #{rev}"
  end

  defp lifecycle_summary(%{type: "debugger.elm_introspect", payload: payload})
       when is_map(payload) do
    mod = Map.get(payload, :module) || Map.get(payload, "module") || "—"
    tgt = Map.get(payload, :target) || Map.get(payload, "target") || "—"
    mc = Map.get(payload, :msg_count) || Map.get(payload, "msg_count") || 0
    vr = Map.get(payload, :view_root) || Map.get(payload, "view_root") || "—"
    ub = Map.get(payload, :update_branch_count) || Map.get(payload, "update_branch_count") || 0
    sc = Map.get(payload, :subscription_count) || Map.get(payload, "subscription_count") || 0
    ic = Map.get(payload, :init_cmd_count) || Map.get(payload, "init_cmd_count") || 0
    uc = Map.get(payload, :update_cmd_count) || Map.get(payload, "update_cmd_count") || 0
    vb = Map.get(payload, :view_branch_count) || Map.get(payload, "view_branch_count") || 0

    ibc =
      Map.get(payload, :init_case_branch_count) || Map.get(payload, "init_case_branch_count") || 0

    sbc =
      Map.get(payload, :subscriptions_case_branch_count) ||
        Map.get(payload, "subscriptions_case_branch_count") || 0

    pc = Map.get(payload, :port_count) || Map.get(payload, "port_count") || 0
    icx = Map.get(payload, :import_count) || Map.get(payload, "import_count") || 0

    iec =
      Map.get(payload, :import_entry_count) || Map.get(payload, "import_entry_count") || 0

    mk = Map.get(payload, :main_kind) || Map.get(payload, "main_kind")

    base = "#{mod} · #{tgt} · #{mc} msgs · view #{vr}"

    base = if is_integer(ub) and ub > 0, do: base <> " · #{ub} update branches", else: base
    base = if is_integer(vb) and vb > 0, do: base <> " · #{vb} view case branches", else: base
    base = if is_integer(ibc) and ibc > 0, do: base <> " · #{ibc} init case branches", else: base

    base =
      if is_integer(sbc) and sbc > 0,
        do: base <> " · #{sbc} subscriptions case branches",
        else: base

    base = if is_integer(sc) and sc > 0, do: base <> " · #{sc} subs", else: base
    base = if is_integer(ic) and ic > 0, do: base <> " · #{ic} init cmds", else: base
    base = if is_integer(uc) and uc > 0, do: base <> " · #{uc} update cmds", else: base
    base = if is_integer(pc) and pc > 0, do: base <> " · #{pc} ports", else: base
    base = if is_integer(icx) and icx > 0, do: base <> " · #{icx} imports", else: base
    base = if is_integer(iec) and iec > 0, do: base <> " · #{iec} import lines", else: base

    tac = Map.get(payload, :type_alias_count) || Map.get(payload, "type_alias_count") || 0
    unc = Map.get(payload, :union_type_count) || Map.get(payload, "union_type_count") || 0

    fnc =
      Map.get(payload, :top_level_function_count) || Map.get(payload, "top_level_function_count") ||
        0

    base = if is_integer(tac) and tac > 0, do: base <> " · #{tac} type aliases", else: base
    base = if is_integer(unc) and unc > 0, do: base <> " · #{unc} unions", else: base
    base = if is_integer(fnc) and fnc > 0, do: base <> " · #{fnc} functions", else: base

    ucs = Map.get(payload, :update_case_subject) || Map.get(payload, "update_case_subject")
    vcs = Map.get(payload, :view_case_subject) || Map.get(payload, "view_case_subject")
    ics = Map.get(payload, :init_case_subject) || Map.get(payload, "init_case_subject")

    scs =
      Map.get(payload, :subscriptions_case_subject) ||
        Map.get(payload, "subscriptions_case_subject")

    base =
      if is_integer(ub) and ub > 0 and is_binary(ucs) and ucs != "" do
        base <> " · case #{ucs}"
      else
        base
      end

    base =
      if is_integer(vb) and vb > 0 and is_binary(vcs) and vcs != "" do
        base <> " · view case #{vcs}"
      else
        base
      end

    base =
      if is_integer(ibc) and ibc > 0 and is_binary(ics) and ics != "" do
        base <> " · init case #{ics}"
      else
        base
      end

    base =
      if is_integer(sbc) and sbc > 0 and is_binary(scs) and scs != "" do
        base <> " · subs case #{scs}"
      else
        base
      end

    me = Map.get(payload, :module_exposing) || Map.get(payload, "module_exposing")

    base =
      case me do
        ".." ->
          base <> " · exposing (..)"

        xs when is_list(xs) and xs != [] ->
          base <> " · exposing (#{length(xs)})"

        _ ->
          base
      end

    pm = Map.get(payload, :port_module)
    pm = if is_boolean(pm), do: pm, else: Map.get(payload, "port_module") == true

    base =
      if pm do
        base <> " · port module"
      else
        base
      end

    if is_binary(mk) and mk != "" and mk != "unknown" do
      base <> " · main #{mk}"
    else
      base
    end
  end

  defp lifecycle_summary(%{type: "debugger.reset"}), do: "full reset"
  defp lifecycle_summary(%{type: "debugger.start"}), do: "session started"

  defp lifecycle_summary(%{type: "debugger.elmc_check", payload: payload})
       when is_map(payload) do
    status = elmc_payload_display(payload, :status)
    errs = elmc_payload_display(payload, :error_count)
    warns = elmc_payload_display(payload, :warning_count)
    path = elmc_payload_display(payload, :checked_path)
    "#{status} · #{errs} err · #{warns} warn · #{path}"
  end

  defp lifecycle_summary(%{type: "debugger.elmc_compile", payload: payload})
       when is_map(payload) do
    status = elmc_payload_display(payload, :status)
    errs = elmc_payload_display(payload, :error_count)
    rev = elmc_payload_display(payload, :revision)
    cached = elmc_payload_display(payload, :cached)
    path = elmc_payload_display(payload, :compiled_path)
    "#{status} · #{errs} err · rev #{rev} · cached=#{cached} · #{path}"
  end

  defp lifecycle_summary(%{type: "debugger.elmc_manifest", payload: payload})
       when is_map(payload) do
    status = elmc_payload_display(payload, :status)
    errs = elmc_payload_display(payload, :error_count)
    strict = elmc_payload_display(payload, :strict)
    schema = elmc_payload_display(payload, :schema_version)
    path = elmc_payload_display(payload, :manifest_path)
    "#{status} · #{errs} err · strict=#{strict} · schema #{schema} · #{path}"
  end

  defp lifecycle_summary(%{type: type}) when is_binary(type), do: type
  defp lifecycle_summary(_), do: "—"

  @spec elmc_payload_display(term(), term()) :: term()
  defp elmc_payload_display(payload, key) when is_map(payload) do
    str = Atom.to_string(key)
    v = Map.get(payload, key) || Map.get(payload, str)

    cond do
      is_binary(v) -> v
      is_integer(v) -> Integer.to_string(v)
      is_boolean(v) -> if(v, do: "true", else: "false")
      is_atom(v) -> Atom.to_string(v)
      true -> "—"
    end
  end

  @spec timeline_upper_seq([map()], maybe_non_neg_integer()) :: non_neg_integer()
  defp timeline_upper_seq(events, cursor_seq) do
    cond do
      is_integer(cursor_seq) ->
        cursor_seq

      events == [] ->
        0

      true ->
        events |> Enum.map(& &1.seq) |> Enum.max()
    end
  end

  @spec protocol_payload_field(map(), atom()) :: String.t() | nil
  defp protocol_payload_field(payload, key) when is_map(payload) do
    str = Atom.to_string(key)
    v = Map.get(payload, key) || Map.get(payload, str)
    if is_binary(v), do: v
  end

  defp protocol_payload_field(_payload, _key), do: nil

  @spec elm_value(term()) :: String.t()
  defp elm_value(%{} = value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor")
    args = Map.get(value, "args") || Map.get(value, "$args") || []

    cond do
      is_binary(ctor) and args == [] ->
        ctor

      is_binary(ctor) and is_list(args) ->
        ([ctor] ++ Enum.map(args, &elm_value/1)) |> Enum.join(" ")

      true ->
        fields =
          value
          |> Enum.reject(fn {key, _field_value} -> key in ["ctor", "args", "$ctor", "$args"] end)
          |> Enum.sort_by(fn {key, _field_value} -> key end)
          |> Enum.map(fn {key, field_value} ->
            "#{elm_field_name(key)} = #{elm_value(field_value)}"
          end)
          |> Enum.join(", ")

        "{ #{fields} }"
    end
  end

  defp elm_value(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &elm_value/1) <> "]"
  end

  defp elm_value(value) when is_binary(value), do: inspect(value)
  defp elm_value(true), do: "True"
  defp elm_value(false), do: "False"
  defp elm_value(nil), do: "null"
  defp elm_value(value), do: to_string(value)

  @spec elm_field_name(term()) :: String.t()
  defp elm_field_name(key) when is_binary(key), do: key
  defp elm_field_name(key), do: to_string(key)

  @spec normalize_debugger_timeline_mode(term()) :: String.t()
  defp normalize_debugger_timeline_mode("watch"), do: "watch"
  defp normalize_debugger_timeline_mode("companion"), do: "companion"
  defp normalize_debugger_timeline_mode("separate"), do: "separate"
  defp normalize_debugger_timeline_mode(_), do: "mixed"

  @spec debugger_target(term()) :: String.t()
  defp debugger_target("companion"), do: "companion"
  defp debugger_target("protocol"), do: "companion"
  defp debugger_target(:companion), do: "companion"
  defp debugger_target(:protocol), do: "companion"
  defp debugger_target(_), do: "watch"

  @spec debugger_target_runtime(String.t(), map() | nil, map() | nil) :: map() | nil
  defp debugger_target_runtime("companion", _watch_runtime, companion_runtime),
    do: companion_runtime

  defp debugger_target_runtime(_target, watch_runtime, _companion_runtime), do: watch_runtime

  @spec debugger_other_runtime(String.t(), map() | nil, map() | nil) :: map() | nil
  defp debugger_other_runtime("companion", watch_runtime, _companion_runtime), do: watch_runtime
  defp debugger_other_runtime(_target, _watch_runtime, companion_runtime), do: companion_runtime

  @spec filtered_event_summaries([map()] | term(), timeline_kind(), pos_integer()) :: [
          event_summary()
        ]
  def filtered_event_summaries(events, kind, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    events
    |> event_summaries()
    |> Enum.filter(fn row -> kind == :all or timeline_kind_for_type(row.type) == kind end)
    |> Enum.take(limit)
  end

  def filtered_event_summaries(_events, _kind, _limit), do: []

  @spec filtered_event_summaries([map()] | term(), timeline_kind(), pos_integer(), String.t()) ::
          [event_summary()]
  def filtered_event_summaries(events, kind, limit, query)
      when is_binary(query) do
    query_norm = String.downcase(String.trim(query))

    filtered_event_summaries(events, kind, limit * 5)
    |> Enum.filter(fn row ->
      query_norm == "" or
        String.contains?(String.downcase(row.type), query_norm) or
        String.contains?(String.downcase(row.message || ""), query_norm)
    end)
    |> Enum.take(limit)
  end

  @spec highlight_fragments(String.t(), String.t()) :: [highlight_fragment()]
  def highlight_fragments(value, query) when is_binary(value) and is_binary(query) do
    query_norm = String.trim(query)

    if query_norm == "" do
      [%{text: value, match?: false}]
    else
      pattern = Regex.compile!(Regex.escape(query_norm), "i")
      downcased_query = String.downcase(query_norm)

      pattern
      |> Regex.split(value, include_captures: true, trim: false)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn part ->
        %{text: part, match?: String.downcase(part) == downcased_query}
      end)
    end
  end

  @spec seq_bounds([map()] | term()) :: {non_neg_integer(), non_neg_integer()} | nil
  def seq_bounds(events) when is_list(events) and events != [] do
    seqs = Enum.map(events, & &1.seq)
    {Enum.min(seqs), Enum.max(seqs)}
  end

  def seq_bounds(_events), do: nil

  @spec min_seq([map()] | term()) :: non_neg_integer()
  def min_seq(events) do
    case seq_bounds(events) do
      {min_seq, _max_seq} -> min_seq
      nil -> 0
    end
  end

  @spec max_seq([map()] | term()) :: non_neg_integer()
  def max_seq(events) do
    case seq_bounds(events) do
      {_min_seq, max_seq} -> max_seq
      nil -> 0
    end
  end

  @spec parse_types(term()) :: [String.t()]
  defp parse_types(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_types(_value), do: []

  @spec parse_since_seq(term()) :: maybe_non_neg_integer()
  defp parse_since_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_since_seq(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_since_seq(_value), do: nil

  @spec parse_replay_count(term()) :: pos_integer()
  defp parse_replay_count(value) when is_integer(value) and value >= 1, do: min(value, 50)

  defp parse_replay_count(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 1 -> min(parsed, 50)
      _ -> 1
    end
  end

  defp parse_replay_count(_value), do: 1

  @spec parse_replay_target(term()) :: String.t() | nil
  defp parse_replay_target(value) when value in ["watch", "companion", "protocol", "phone"],
    do: value

  defp parse_replay_target(_value), do: nil

  @spec parse_replay_cursor_bound(term()) :: boolean()
  defp parse_replay_cursor_bound(value) when value in [true, "true", "on", 1, "1"], do: true
  defp parse_replay_cursor_bound(_value), do: false

  @spec parse_replay_mode(term()) :: String.t()
  defp parse_replay_mode("live"), do: "live"
  defp parse_replay_mode(_), do: "frozen"

  @spec filter_form(String.t(), String.t()) :: Phoenix.HTML.Form.t()
  defp filter_form(types_text, since_seq_text)
       when is_binary(types_text) and is_binary(since_seq_text) do
    Component.to_form(%{"types" => types_text, "since_seq" => since_seq_text},
      as: :debugger_filter
    )
  end

  @spec filter_form([String.t()], maybe_non_neg_integer()) :: Phoenix.HTML.Form.t()
  defp filter_form(types, since_seq) when is_list(types) do
    since_seq_text = if is_integer(since_seq), do: Integer.to_string(since_seq), else: ""
    filter_form(Enum.join(types, ","), since_seq_text)
  end

  @spec replay_form(String.t(), String.t(), boolean(), String.t()) :: Phoenix.HTML.Form.t()
  defp replay_form(count_text, target, cursor_bound?, mode)
       when is_binary(count_text) and is_binary(target) and is_boolean(cursor_bound?) and
              is_binary(mode) do
    Component.to_form(
      %{
        "count" => count_text,
        "target" => target,
        "cursor_bound" => if(cursor_bound?, do: "true", else: "false"),
        "mode" => parse_replay_mode(mode)
      },
      as: :debugger_replay
    )
  end

  @spec compare_form(maybe_non_neg_integer()) :: Phoenix.HTML.Form.t()
  defp compare_form(seq) do
    baseline_text = if is_integer(seq), do: Integer.to_string(seq), else: ""
    Component.to_form(%{"baseline_seq" => baseline_text}, as: :debugger_compare)
  end

  @spec assign_replay_preview(socket(), keyword()) :: socket()
  defp assign_replay_preview(socket, opts \\ []) do
    events =
      case socket.assigns[:debugger_state] do
        %{events: list} when is_list(list) -> list
        _ -> []
      end

    form = socket.assigns[:debugger_replay_form]
    count = form_value(form, :count)
    target = form_value(form, :target)
    cursor_bound? = form_value(form, :cursor_bound) in ["true", true, "on", "1", 1]
    cursor_seq = if cursor_bound?, do: socket.assigns[:debugger_cursor_seq], else: nil

    preview =
      replay_preview_rows(events, %{
        count: count,
        target: target,
        cursor_seq: cursor_seq
      })

    compare = replay_compare(preview, socket.assigns[:debugger_last_replay])
    track_seq? = Keyword.get(opts, :track_seq, false)

    latest_seq =
      case events do
        [] -> nil
        list -> list |> Enum.map(& &1.seq) |> Enum.max()
      end

    preview_seq =
      if track_seq? do
        latest_seq
      else
        socket.assigns[:debugger_replay_preview_seq]
      end

    mode = form_value(form, :mode) || "frozen"
    live_warning = replay_live_warning?(mode, preview_seq, events)
    live_drift = replay_live_drift(mode, preview_seq, events)

    compare_baseline_seq = socket.assigns[:debugger_compare_baseline_seq]

    runtime_compare =
      runtime_fingerprint_compare_at_cursor(
        events,
        socket.assigns[:debugger_cursor_seq],
        compare_baseline_seq
      )

    socket
    |> Component.assign(:debugger_replay_preview, preview)
    |> Component.assign(:debugger_replay_preview_seq, preview_seq)
    |> Component.assign(:debugger_replay_live_warning, live_warning)
    |> Component.assign(:debugger_replay_live_drift, live_drift)
    |> Component.assign(:debugger_replay_compare, compare)
    |> Component.assign(:debugger_compare_form, compare_form(compare_baseline_seq))
    |> Component.assign(:debugger_runtime_fingerprint_compare, runtime_compare)
  end

  @spec form_value(term(), term()) :: term()
  defp form_value(nil, _field), do: nil

  defp form_value(form, field) do
    form[field].value
  end

  @spec maybe_put_export_cursor_opt(term(), term(), term()) :: term()
  defp maybe_put_export_cursor_opt(opts, _key, value) when not is_integer(value), do: opts
  defp maybe_put_export_cursor_opt(opts, _key, value) when value < 0, do: opts
  defp maybe_put_export_cursor_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @spec parse_optional_non_neg_int(term()) :: term()
  defp parse_optional_non_neg_int(value) when is_integer(value) and value >= 0, do: value

  defp parse_optional_non_neg_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_optional_non_neg_int(_), do: nil

  @spec normalize_replay_rows(list()) :: [replay_preview_row()]
  defp normalize_replay_rows(rows) when is_list(rows), do: Enum.map(rows, &normalize_replay_row/1)
  defp normalize_replay_rows(_), do: []

  @spec first_row_mismatch([replay_preview_row()], [replay_preview_row()]) ::
          {replay_preview_row() | nil, replay_preview_row() | nil}
  defp first_row_mismatch(preview_rows, applied_rows) do
    max_len = max(length(preview_rows), length(applied_rows))

    0..max(max_len - 1, 0)
    |> Enum.find_value({List.first(preview_rows), List.first(applied_rows)}, fn index ->
      preview = Enum.at(preview_rows, index)
      applied = Enum.at(applied_rows, index)
      if preview != applied, do: {preview, applied}
    end)
  end

  @spec normalize_replay_row(map()) :: replay_preview_row()
  defp normalize_replay_row(row) when is_map(row) do
    %{
      seq: row[:seq] || row["seq"] || 0,
      target: row[:target] || row["target"] || "watch",
      message: row[:message] || row["message"] || "Tick"
    }
  end

  defp normalize_replay_row(_), do: %{seq: 0, target: "watch", message: "Tick"}

  @spec maybe_filter_preview_events_at_or_before_seq(term(), term()) :: term()
  defp maybe_filter_preview_events_at_or_before_seq(events, nil) when is_list(events), do: events

  defp maybe_filter_preview_events_at_or_before_seq(events, cursor_seq)
       when is_list(events) and is_integer(cursor_seq) and cursor_seq >= 0 do
    Enum.filter(events, &(&1.seq <= cursor_seq))
  end

  @spec normalize_preview_target(term()) :: term()
  defp normalize_preview_target("watch"), do: "watch"
  defp normalize_preview_target("protocol"), do: "protocol"
  defp normalize_preview_target("companion"), do: "protocol"
  defp normalize_preview_target("phone"), do: "phone"
  defp normalize_preview_target(_), do: "watch"

  @spec preview_target_label(term()) :: term()
  defp preview_target_label("watch"), do: "watch"
  defp preview_target_label("protocol"), do: "protocol"
  defp preview_target_label("phone"), do: "phone"
  defp preview_target_label(_), do: "watch"

  @spec timeline_form(maybe_non_neg_integer()) :: Phoenix.HTML.Form.t()
  defp timeline_form(seq) do
    seq_text = if is_integer(seq), do: Integer.to_string(seq), else: ""
    Component.to_form(%{"seq" => seq_text}, as: :debugger_timeline)
  end

  @spec assign_timeline(socket(), map()) :: socket()
  defp assign_timeline(socket, debugger_state) do
    events = Map.get(debugger_state, :events, [])
    cursor_seq = normalize_cursor_seq(events, socket.assigns[:debugger_cursor_seq])

    compare_baseline_seq =
      normalize_optional_cursor_seq(events, socket.assigns[:debugger_compare_baseline_seq])

    {selected, newer, older} = selected_and_neighbors(events, cursor_seq)

    snapshot_runtime =
      events
      |> snapshot_runtime_at_cursor(cursor_seq)
      |> with_live_runtime_fallback(debugger_state)

    last_replay = replay_metadata_at_cursor(events, cursor_seq)

    debugger =
      debugger_assigns(socket.assigns[:debugger_cursor_seq], snapshot_runtime, debugger_state)

    socket
    |> Component.assign(:debugger_state, debugger_state)
    |> Component.assign(:debugger_cursor_seq, cursor_seq)
    |> Component.assign(:debugger_selected_event, selected)
    |> Component.assign(:debugger_newer_event, newer)
    |> Component.assign(:debugger_older_event, older)
    |> Component.assign(:debugger_cursor_watch_runtime, snapshot_runtime.watch)
    |> Component.assign(:debugger_cursor_companion_runtime, snapshot_runtime.companion)
    |> Component.assign(:debugger_cursor_phone_runtime, snapshot_runtime.phone)
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
    |> Component.assign(:debugger_trigger_buttons, trigger_buttons(debugger_state))
    |> Component.assign(
      :debugger_watch_trigger_buttons,
      subscription_trigger_buttons(debugger_state, :watch)
    )
    |> Component.assign(
      :debugger_companion_trigger_buttons,
      subscription_trigger_buttons(debugger_state, :companion)
    )
    |> Component.assign(:debugger_watch_auto_fire, auto_fire_enabled?(debugger_state, :watch))
    |> Component.assign(
      :debugger_companion_auto_fire,
      auto_fire_enabled?(debugger_state, :companion)
    )
    |> Component.assign(
      :debugger_auto_fire_subscriptions,
      auto_fire_subscriptions(debugger_state)
    )
    |> Component.assign(:debugger_disabled_subscriptions, disabled_subscriptions(debugger_state))
    |> Component.assign(:debugger_timeline_form, timeline_form(cursor_seq))
    |> Component.assign(:debugger_compare_baseline_seq, compare_baseline_seq)
    |> Component.assign(:debugger_compare_form, compare_form(compare_baseline_seq))
    |> Component.assign(:debugger_last_replay, last_replay)
    |> assign_replay_preview()
  end

  @spec assign_cursor(socket(), maybe_non_neg_integer()) :: socket()
  defp assign_cursor(socket, cursor_seq) do
    events =
      case socket.assigns[:debugger_state] do
        %{events: list} when is_list(list) -> list
        _ -> []
      end

    normalized_cursor = normalize_cursor_seq(events, cursor_seq)

    {selected, newer, older} = selected_and_neighbors(events, normalized_cursor)

    snapshot_runtime =
      events
      |> snapshot_runtime_at_cursor(normalized_cursor)
      |> with_live_runtime_fallback(socket.assigns[:debugger_state])

    last_replay = replay_metadata_at_cursor(events, normalized_cursor)

    debugger =
      debugger_assigns(
        socket.assigns[:debugger_cursor_seq],
        snapshot_runtime,
        socket.assigns[:debugger_state]
      )

    socket
    |> Component.assign(:debugger_cursor_seq, normalized_cursor)
    |> Component.assign(:debugger_selected_event, selected)
    |> Component.assign(:debugger_newer_event, newer)
    |> Component.assign(:debugger_older_event, older)
    |> Component.assign(:debugger_cursor_watch_runtime, snapshot_runtime.watch)
    |> Component.assign(:debugger_cursor_companion_runtime, snapshot_runtime.companion)
    |> Component.assign(:debugger_cursor_phone_runtime, snapshot_runtime.phone)
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
    |> Component.assign(:debugger_timeline_form, timeline_form(normalized_cursor))
    |> Component.assign(:debugger_last_replay, last_replay)
    |> assign_replay_preview()
  end

  @spec move_cursor(socket(), :back | :forward) :: socket()
  defp move_cursor(socket, direction) do
    events =
      case socket.assigns[:debugger_state] do
        %{events: list} when is_list(list) -> list
        _ -> []
      end

    cursor_seq = socket.assigns[:debugger_cursor_seq]
    seqs = Enum.map(events, & &1.seq)

    next_cursor =
      case Enum.find_index(seqs, &(&1 == cursor_seq)) do
        nil ->
          normalize_cursor_seq(events, nil)

        index ->
          max_index = max(length(seqs) - 1, 0)

          case direction do
            :back -> Enum.at(seqs, min(index + 1, max_index))
            :forward -> Enum.at(seqs, max(index - 1, 0))
          end
      end

    assign_cursor(socket, next_cursor)
  end

  @spec assign_debugger_cursor(socket(), maybe_non_neg_integer()) :: socket()
  defp assign_debugger_cursor(socket, debugger_cursor_seq) do
    debugger_state = socket.assigns[:debugger_state]

    snapshot_runtime = %{
      watch: socket.assigns[:debugger_cursor_watch_runtime],
      companion: socket.assigns[:debugger_cursor_companion_runtime],
      phone: socket.assigns[:debugger_cursor_phone_runtime]
    }

    debugger = debugger_assigns(debugger_cursor_seq, snapshot_runtime, debugger_state)

    socket
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
  end

  @spec jump_latest_debugger(socket()) :: socket()
  defp jump_latest_debugger(socket) do
    rows =
      case socket.assigns[:debugger_state] do
        %{} = debugger_state -> debugger_rows(debugger_state, 1)
        _ -> []
      end

    case rows do
      [%{seq: seq} | _] -> assign_debugger_cursor(socket, seq)
      _ -> socket
    end
  end

  @spec debugger_cursor_at_latest?(socket()) :: boolean()
  defp debugger_cursor_at_latest?(socket) do
    rows =
      case socket.assigns[:debugger_state] do
        %{} = debugger_state -> debugger_rows(debugger_state, 1)
        _ -> []
      end

    case rows do
      [%{seq: latest_seq} | _] ->
        cursor_seq = socket.assigns[:debugger_cursor_seq]
        is_nil(cursor_seq) or cursor_seq == latest_seq

      _ ->
        true
    end
  end

  @spec debugger_assigns(
          maybe_non_neg_integer(),
          %{
            watch: map() | nil,
            companion: map() | nil,
            phone: map() | nil
          },
          map() | nil
        ) :: map()
  defp debugger_assigns(cursor_seq, snapshot_runtime, debugger_state) do
    rows = debugger_rows(debugger_state)
    selected = selected_debugger_row(debugger_state, cursor_seq)
    resolved_cursor_seq = if selected, do: selected.seq, else: nil

    watch_runtime =
      case selected do
        %{watch_runtime: %{} = runtime} -> runtime
        _ -> snapshot_runtime.watch
      end

    companion_runtime =
      case selected do
        %{companion_runtime: %{} = runtime} -> runtime
        _ -> snapshot_runtime.companion
      end

    watch_view_runtime =
      Debugger.render_runtime_preview_for_debugger(
        watch_runtime,
        latest_debugger_runtime(debugger_state, :watch),
        :watch
      )

    %{
      rows: rows,
      cursor_seq: resolved_cursor_seq,
      selected: selected,
      watch_runtime: watch_runtime,
      companion_runtime: companion_runtime,
      watch_view_runtime: watch_view_runtime
    }
  end

  @spec latest_debugger_runtime(map() | nil, :watch | :companion | :phone) :: map() | nil
  defp latest_debugger_runtime(debugger_state, target) when is_map(debugger_state) do
    case Map.get(debugger_state, target) do
      %{} = runtime -> runtime
      _ -> nil
    end
  end

  defp latest_debugger_runtime(_debugger_state, _target), do: nil

  @spec normalize_cursor_seq([map()], maybe_non_neg_integer()) :: maybe_non_neg_integer()
  defp normalize_cursor_seq(events, cursor_seq) do
    CursorSeq.resolve_at_or_before(events, cursor_seq)
  end

  @spec normalize_optional_cursor_seq([map()], maybe_non_neg_integer()) :: maybe_non_neg_integer()
  defp normalize_optional_cursor_seq(_events, nil), do: nil

  defp normalize_optional_cursor_seq(events, cursor_seq) when is_integer(cursor_seq),
    do: normalize_cursor_seq(events, cursor_seq)

  defp normalize_optional_cursor_seq(_events, _cursor_seq), do: nil

  @spec selected_and_neighbors([map()], maybe_non_neg_integer()) ::
          {map() | nil, map() | nil, map() | nil}
  defp selected_and_neighbors(events, cursor_seq) when is_integer(cursor_seq) do
    case Enum.find_index(events, &(&1.seq == cursor_seq)) do
      nil ->
        {nil, nil, nil}

      index ->
        selected = Enum.at(events, index)
        newer = if index > 0, do: Enum.at(events, index - 1), else: nil
        older = Enum.at(events, index + 1)
        {selected, newer, older}
    end
  end

  defp selected_and_neighbors(_events, _cursor_seq), do: {nil, nil, nil}

  @spec snapshot_runtime_at_cursor([map()], maybe_non_neg_integer()) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  def snapshot_runtime_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = normalize_cursor_seq(events, cursor_seq)
    upper = timeline_upper_seq(events, normalized)

    %{
      watch: nearest_surface_runtime_at_or_before(events, upper, :watch),
      companion: nearest_surface_runtime_at_or_before(events, upper, :companion),
      phone: nearest_surface_runtime_at_or_before(events, upper, :phone)
    }
  end

  def snapshot_runtime_at_cursor(_events, _cursor_seq),
    do: %{watch: nil, companion: nil, phone: nil}

  @spec with_live_runtime_fallback(map(), map() | nil) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  defp with_live_runtime_fallback(snapshot_runtime, debugger_state)
       when is_map(snapshot_runtime) and is_map(debugger_state) do
    %{
      watch: snapshot_runtime.watch || Map.get(debugger_state, :watch),
      companion: snapshot_runtime.companion || Map.get(debugger_state, :companion),
      phone: snapshot_runtime.phone || Map.get(debugger_state, :phone)
    }
  end

  defp with_live_runtime_fallback(snapshot_runtime, _debugger_state), do: snapshot_runtime

  @spec trigger_buttons(map()) :: [map()]
  def trigger_buttons(debugger_state) when is_map(debugger_state) do
    [:watch, :companion]
    |> Enum.flat_map(&Debugger.trigger_candidates(debugger_state, &1))
    |> Enum.map(fn row ->
      %{
        id: Map.get(row, :id) || Map.get(row, "id"),
        label: Map.get(row, :label) || Map.get(row, "label"),
        trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
        target: Map.get(row, :target) || Map.get(row, "target"),
        message: Map.get(row, :message) || Map.get(row, "message"),
        source: Map.get(row, :source) || Map.get(row, "source")
      }
    end)
    |> Enum.filter(fn row ->
      is_binary(row.id) and row.id != "" and is_binary(row.trigger) and row.trigger != ""
    end)
  end

  def trigger_buttons(_), do: []

  @spec subscription_trigger_buttons(map(), :watch | :companion) :: [map()]
  defp subscription_trigger_buttons(debugger_state, target)
       when is_map(debugger_state) and target in [:watch, :companion] do
    debugger_state
    |> Debugger.trigger_candidates(target)
    |> Enum.map(fn row ->
      %{
        id: Map.get(row, :id) || Map.get(row, "id"),
        label: Map.get(row, :label) || Map.get(row, "label"),
        trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
        target: Map.get(row, :target) || Map.get(row, "target"),
        message: Map.get(row, :message) || Map.get(row, "message"),
        source: Map.get(row, :source) || Map.get(row, "source")
      }
    end)
    |> Enum.filter(fn row ->
      row.source == "subscription" and is_binary(row.id) and row.id != "" and
        is_binary(row.trigger) and row.trigger != ""
    end)
  end

  defp subscription_trigger_buttons(_debugger_state, _target), do: []

  @spec auto_fire_enabled?(map(), :watch | :companion) :: boolean()
  defp auto_fire_enabled?(debugger_state, target)
       when is_map(debugger_state) and target in [:watch, :companion] do
    auto_tick = Map.get(debugger_state, :auto_tick, %{})
    source_root = if target == :companion, do: "protocol", else: "watch"

    Map.get(auto_tick, :enabled) == true and
      source_root in List.wrap(Map.get(auto_tick, :targets, []))
  end

  defp auto_fire_enabled?(_debugger_state, _target), do: false

  defp auto_fire_subscriptions(debugger_state) when is_map(debugger_state) do
    auto_tick = Map.get(debugger_state, :auto_tick, %{})

    case Map.get(auto_tick, :subscriptions) do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  defp auto_fire_subscriptions(_debugger_state), do: []

  defp disabled_subscriptions(debugger_state) when is_map(debugger_state) do
    case Map.get(debugger_state, :disabled_subscriptions) ||
           Map.get(debugger_state, "disabled_subscriptions") do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  defp disabled_subscriptions(_debugger_state), do: []

  @spec cursor_runtime(map() | nil, :watch | :companion | :phone) :: map() | nil
  defp cursor_runtime(nil, _kind), do: nil

  defp cursor_runtime(event, :watch) when is_map(event), do: Map.get(event, :watch)
  defp cursor_runtime(event, :companion) when is_map(event), do: Map.get(event, :companion)
  defp cursor_runtime(event, :phone) when is_map(event), do: Map.get(event, :phone)

  @spec nearest_surface_runtime_at_or_before(
          [map()],
          non_neg_integer(),
          :watch | :companion | :phone
        ) ::
          map() | nil
  defp nearest_surface_runtime_at_or_before(events, upper_seq, surface)
       when is_list(events) and is_integer(upper_seq) and upper_seq >= 0 and
              surface in [:watch, :companion, :phone] do
    events
    |> Enum.filter(fn event ->
      seq = Map.get(event, :seq)
      is_integer(seq) and seq <= upper_seq
    end)
    |> Enum.sort_by(&Map.get(&1, :seq), :desc)
    |> Enum.find_value(fn event ->
      case cursor_runtime(event, surface) do
        %{} = runtime -> runtime
        _ -> nil
      end
    end)
  end

  @spec payload_target(map()) :: String.t() | nil
  defp payload_target(payload) when is_map(payload) do
    cond do
      is_binary(Map.get(payload, :target)) -> Map.get(payload, :target)
      is_binary(Map.get(payload, "target")) -> Map.get(payload, "target")
      is_binary(Map.get(payload, :to)) -> Map.get(payload, :to)
      is_binary(Map.get(payload, "to")) -> Map.get(payload, "to")
      true -> nil
    end
  end

  defp payload_target(_payload), do: nil

  @spec rendered_view_preview(map() | nil) :: String.t()
  def rendered_view_preview(nil), do: "(no snapshot)"

  def rendered_view_preview(runtime) when is_map(runtime) do
    tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")
    model = preview_runtime_model(runtime)
    runtime_ops = runtime_view_output_lines(runtime)

    case tree do
      %{} = node ->
        tree_text = format_rendered_node(node, 0, model, nil) |> String.trim_trailing()
        join_preview_sections(runtime_ops, tree_text)

      _ ->
        "(no rendered view in snapshot)"
    end
  end

  def rendered_view_preview(_), do: "(no snapshot)"

  @spec format_rendered_node(term(), term(), term(), term()) :: term()
  defp format_rendered_node(node, depth, model, arg_name)
       when is_map(node) and is_integer(depth) and is_map(model) do
    indent = String.duplicate("  ", max(depth, 0))
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")

    children = Map.get(node, "children") || Map.get(node, :children) || []

    child_text =
      children
      |> Enum.filter(&is_map/1)
      |> rendered_child_rows(node)
      |> Enum.map_join("", fn {child, child_arg_name} ->
        format_rendered_node(child, depth + 1, model, child_arg_name)
      end)

    if hidden_rendered_node_type?(type) do
      child_text
    else
      summary = rendered_node_summary(node, model, arg_name)

      "#{indent}- #{summary}\n#{child_text}"
    end
  end

  defp format_rendered_node(_node, _depth, _model, _arg_name), do: ""

  @spec hidden_rendered_node_type?(String.t()) :: boolean()
  defp hidden_rendered_node_type?(type) when is_binary(type) do
    type in ["debuggerRenderStep", "elmcRuntimeStep"]
  end

  @spec render_suffix(term()) :: term()
  defp render_suffix(""), do: ""
  defp render_suffix(nil), do: ""
  defp render_suffix(value), do: "[#{value}]"

  @spec rendered_node_summary(map(), map(), term()) :: String.t()
  def rendered_node_summary(node, model, arg_name \\ nil)

  def rendered_node_summary(node, model, arg_name) when is_map(node) and is_map(model) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")
    label = Map.get(node, "label") || Map.get(node, :label) || ""
    text = Map.get(node, "text") || Map.get(node, :text) || ""
    value_hint = rendered_value_hint(node, model)
    value = rendered_node_value(node, value_hint)
    arg_name = rendered_arg_name(arg_name)

    cond do
      arg_name != nil and value != "" ->
        "#{value} [#{arg_name}]"

      arg_name != nil ->
        [type, render_suffix(arg_name)]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      true ->
        [type, render_suffix(label), render_suffix(text), render_suffix(value_hint)]
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.join(" ")
    end
  end

  def rendered_node_summary(_node, _model, _arg_name), do: "node"

  @spec rendered_child_rows([map()], map()) :: [{map(), String.t() | nil}]
  defp rendered_child_rows(children, parent) when is_list(children) and is_map(parent) do
    arg_names = rendered_node_arg_names(parent, length(children))

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      {child, Enum.at(arg_names, index)}
    end)
  end

  @spec rendered_arg_name(term()) :: String.t() | nil
  defp rendered_arg_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: nil, else: trimmed
  end

  defp rendered_arg_name(_name), do: nil

  @spec rendered_node_arg_names(map(), non_neg_integer()) :: [String.t()]
  defp rendered_node_arg_names(parent, child_count)
       when is_map(parent) and is_integer(child_count) do
    explicit = Map.get(parent, "arg_names") || Map.get(parent, :arg_names) || []

    if explicit != [] do
      explicit
    else
      []
    end
  end

  @spec rendered_node_value(map(), term()) :: String.t()
  defp rendered_node_value(node, value_hint) when is_map(node) do
    cond do
      value_hint not in [nil, ""] ->
        to_string(value_hint)

      Map.has_key?(node, "value") ->
        rendered_scalar_value(Map.get(node, "value"))

      Map.has_key?(node, :value) ->
        rendered_scalar_value(Map.get(node, :value))

      true ->
        rendered_label_value(node)
    end
  end

  @spec rendered_label_value(map()) :: String.t()
  defp rendered_label_value(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    label = Map.get(node, "label") || Map.get(node, :label)

    if type in ["expr", "var"] do
      rendered_scalar_value(label)
    else
      ""
    end
  end

  @spec rendered_scalar_value(term()) :: String.t()
  defp rendered_scalar_value(value) when is_integer(value), do: Integer.to_string(value)

  defp rendered_scalar_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp rendered_scalar_value(value) when is_binary(value), do: value
  defp rendered_scalar_value(value) when is_boolean(value), do: to_string(value)
  defp rendered_scalar_value(_value), do: ""

  @spec preview_runtime_model(term()) :: term()
  defp preview_runtime_model(runtime) when is_map(runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)
    if is_map(runtime_model), do: runtime_model, else: model
  end

  @spec rendered_value_hint(term(), term()) :: term()
  defp rendered_value_hint(node, model) when is_map(node) and is_map(model) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    label = to_string(Map.get(node, "label") || Map.get(node, :label) || "")
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")

    cond do
      type == "field" ->
        node
        |> rendered_node_children()
        |> List.first()
        |> evaluated_rendered_scalar_hint(model)

      type == "call" ->
        evaluated_rendered_scalar_hint(node, model)

      type == "expr" and op in ["tuple_first_expr", "tuple_second_expr"] ->
        evaluated_rendered_scalar_hint(node, model)

      type == "expr" and op == "field_access" and String.starts_with?(label, "model.") ->
        evaluated_rendered_scalar_hint(node, model) ||
          label
          |> String.replace_prefix("model.", "")
          |> then(&Map.get(model, &1))
          |> rendered_int_hint()

      type == "var" ->
        evaluated_rendered_scalar_hint(node, model) || rendered_int_hint(Map.get(model, label))

      true ->
        nil
    end
  end

  defp rendered_value_hint(_node, _model), do: nil

  @spec rendered_node_children(map()) :: [map()]
  defp rendered_node_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      children when is_list(children) -> Enum.filter(children, &is_map/1)
      _ -> []
    end
  end

  @spec evaluated_rendered_scalar_hint(term(), map()) :: String.t() | nil
  defp evaluated_rendered_scalar_hint(node, model) when is_map(node) and is_map(model) do
    ElmExecutor.Runtime.SemanticExecutor
    |> apply(:evaluate_view_tree_value, [node, model, %{}])
    |> rendered_scalar_hint()
  end

  defp evaluated_rendered_scalar_hint(_node, _model), do: nil

  @spec rendered_scalar_hint(term()) :: String.t() | nil
  defp rendered_scalar_hint(value) when is_integer(value), do: Integer.to_string(value)

  defp rendered_scalar_hint(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp rendered_scalar_hint(value) when is_binary(value), do: value
  defp rendered_scalar_hint(value) when is_boolean(value), do: to_string(value)
  defp rendered_scalar_hint(_value), do: nil

  @spec rendered_int_hint(term()) :: term()
  defp rendered_int_hint(value) when is_integer(value), do: Integer.to_string(value)
  defp rendered_int_hint(value) when is_float(value), do: Integer.to_string(trunc(value))
  defp rendered_int_hint(_), do: nil

  @spec runtime_view_output_lines(term()) :: term()
  defp runtime_view_output_lines(runtime) when is_map(runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    ops = Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || []

    ops
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&runtime_op_line/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> ""
      lines -> Enum.join(lines, "\n")
    end
  end

  @spec runtime_op_line(term()) :: term()
  defp runtime_op_line(op) when is_map(op) do
    kind = to_string(Map.get(op, "kind") || Map.get(op, :kind) || "")

    case kind do
      "clear" ->
        "- clear [#{map_integer_value(op, "color", 0)}]"

      "round_rect" ->
        "- roundRect [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, w=#{map_integer_value(op, "w", 0)}, h=#{map_integer_value(op, "h", 0)}, r=#{map_integer_value(op, "radius", 0)}, fill=#{map_integer_value(op, "fill", 0)}]"

      "rect" ->
        "- rect [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, w=#{map_integer_value(op, "w", 0)}, h=#{map_integer_value(op, "h", 0)}, fill=#{map_integer_value(op, "fill", 0)}]"

      "line" ->
        "- line [#{map_integer_value(op, "x1", 0)}, #{map_integer_value(op, "y1", 0)} -> #{map_integer_value(op, "x2", 0)}, #{map_integer_value(op, "y2", 0)}]"

      "pixel" ->
        "- pixel [#{map_integer_value(op, "x", 0)}, #{map_integer_value(op, "y", 0)}, c=#{map_integer_value(op, "color", 0)}]"

      "text_int" ->
        text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

        "- textInt [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, #{text}]"

      "text_label" ->
        text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

        "- textLabel [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, #{text}]"

      "unresolved" ->
        node_type = to_string(Map.get(op, "node_type") || Map.get(op, :node_type) || "node")
        provided = map_integer_value(op, "provided_int_count", 0)
        required = map_integer_value(op, "required_int_count", 0)
        label = to_string(Map.get(op, "label") || Map.get(op, :label) || "")
        "- unresolved [#{node_type}, ints=#{provided}/#{required}, #{label}]"

      _ ->
        ""
    end
  end

  defp runtime_op_line(_op), do: ""

  @spec map_integer_value(term(), term(), term()) :: term()
  defp map_integer_value(map, key, default)
       when is_map(map) and is_binary(key) and is_integer(default) do
    atom_key =
      case key do
        "x" -> :x
        "y" -> :y
        "w" -> :w
        "h" -> :h
        "x1" -> :x1
        "y1" -> :y1
        "x2" -> :x2
        "y2" -> :y2
        "radius" -> :radius
        "fill" -> :fill
        "color" -> :color
        _ -> nil
      end

    value = Map.get(map, key) || Map.get(map, atom_key)

    cond do
      is_integer(value) ->
        value

      is_float(value) ->
        trunc(value)

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default
        end

      true ->
        default
    end
  end

  @spec join_preview_sections(term(), term()) :: term()
  defp join_preview_sections("", tree_text), do: tree_text
  defp join_preview_sections(runtime_text, ""), do: runtime_text

  defp join_preview_sections(runtime_text, tree_text) do
    "#{runtime_text}\n#{tree_text}"
  end

  @spec map_string(map(), atom()) :: String.t() | nil
  defp map_string(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_binary(value) -> value
      _ -> nil
    end
  end

  @spec map_scalar_string(map(), atom()) :: String.t() | nil
  defp map_scalar_string(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, nil} -> nil
      {:ok, value} when is_binary(value) -> value
      {:ok, value} when is_boolean(value) -> to_string(value)
      {:ok, value} when is_integer(value) -> Integer.to_string(value)
      {:ok, value} when is_float(value) -> :erlang.float_to_binary(value, [:compact])
      {:ok, value} when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  @spec map_integer(map(), atom()) :: integer() | nil
  defp map_integer(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_integer(value) -> value
      _ -> nil
    end
  end

  defp map_integer(_map, _key), do: nil

  @spec map_lookup(map(), atom()) :: {:ok, term()} | :error
  defp map_lookup(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) ->
        {:ok, Map.get(map, key)}

      Map.has_key?(map, string_key) ->
        {:ok, Map.get(map, string_key)}

      true ->
        :error
    end
  end

  defp map_lookup(_map, _key), do: :error

  @spec map_map(map(), atom()) :: map()
  defp map_map(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  @spec map_list(map(), atom()) :: list()
  defp map_list(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_list(value) -> value
      _ -> []
    end
  end

  @spec payload_message(map()) :: String.t() | nil
  defp payload_message(payload) when is_map(payload) do
    mod = Map.get(payload, :module) || Map.get(payload, "module")
    tgt = Map.get(payload, :target) || Map.get(payload, "target")

    cond do
      is_binary(mod) and is_binary(tgt) ->
        vr = Map.get(payload, :view_root) || Map.get(payload, "view_root")
        mk = Map.get(payload, :main_kind) || Map.get(payload, "main_kind")
        ic = Map.get(payload, :init_cmd_count) || Map.get(payload, "init_cmd_count")
        uc = Map.get(payload, :update_cmd_count) || Map.get(payload, "update_cmd_count")
        ucs = Map.get(payload, :update_case_subject) || Map.get(payload, "update_case_subject")
        ub = Map.get(payload, :update_branch_count) || Map.get(payload, "update_branch_count")
        vcs = Map.get(payload, :view_case_subject) || Map.get(payload, "view_case_subject")
        vb = Map.get(payload, :view_branch_count) || Map.get(payload, "view_branch_count")

        ibc =
          Map.get(payload, :init_case_branch_count) || Map.get(payload, "init_case_branch_count")

        ics = Map.get(payload, :init_case_subject) || Map.get(payload, "init_case_subject")

        sbc =
          Map.get(payload, :subscriptions_case_branch_count) ||
            Map.get(payload, "subscriptions_case_branch_count")

        scs =
          Map.get(payload, :subscriptions_case_subject) ||
            Map.get(payload, "subscriptions_case_subject")

        pc = Map.get(payload, :port_count) || Map.get(payload, "port_count")
        icx = Map.get(payload, :import_count) || Map.get(payload, "import_count")

        iec =
          Map.get(payload, :import_entry_count) || Map.get(payload, "import_entry_count")

        base =
          if is_binary(vr), do: "#{mod} · #{tgt} · #{vr}", else: "#{mod} · #{tgt}"

        base =
          if is_binary(mk) and mk != "" and mk != "unknown" do
            base <> " · main " <> mk
          else
            base
          end

        base =
          if is_integer(ub) and ub > 0 and is_binary(ucs) and ucs != "" do
            base <> " · case " <> ucs
          else
            base
          end

        base =
          if is_integer(vb) and vb > 0 and is_binary(vcs) and vcs != "" do
            base <> " · view case " <> vcs
          else
            base
          end

        base =
          if is_integer(ibc) and ibc > 0 and is_binary(ics) and ics != "" do
            base <> " · init case " <> ics
          else
            base
          end

        base =
          if is_integer(sbc) and sbc > 0 and is_binary(scs) and scs != "" do
            base <> " · subs case " <> scs
          else
            base
          end

        me = Map.get(payload, :module_exposing) || Map.get(payload, "module_exposing")

        base =
          case me do
            ".." ->
              base <> " · exposing (..)"

            xs when is_list(xs) and xs != [] ->
              base <> " · exposing (#{length(xs)})"

            _ ->
              base
          end

        base =
          if is_integer(pc) and pc > 0 do
            base <> " · #{pc} ports"
          else
            base
          end

        base =
          if is_integer(icx) and icx > 0 do
            base <> " · #{icx} imports"
          else
            base
          end

        base =
          if is_integer(iec) and iec > 0 do
            base <> " · #{iec} import lines"
          else
            base
          end

        tac = Map.get(payload, :type_alias_count) || Map.get(payload, "type_alias_count")
        unc = Map.get(payload, :union_type_count) || Map.get(payload, "union_type_count")

        fnc =
          Map.get(payload, :top_level_function_count) ||
            Map.get(payload, "top_level_function_count")

        base =
          if is_integer(tac) and tac > 0 do
            base <> " · #{tac} aliases"
          else
            base
          end

        base =
          if is_integer(unc) and unc > 0 do
            base <> " · #{unc} unions"
          else
            base
          end

        base =
          if is_integer(fnc) and fnc > 0 do
            base <> " · #{fnc} functions"
          else
            base
          end

        pm = Map.get(payload, :port_module)
        pm = if is_boolean(pm), do: pm, else: Map.get(payload, "port_module") == true

        base =
          if pm do
            base <> " · port module"
          else
            base
          end

        base =
          if is_integer(uc) and uc > 0 do
            base <> " · #{uc} update cmds"
          else
            base
          end

        if is_integer(ic) and ic > 0 do
          base <> " · #{ic} init cmds"
        else
          base
        end

      is_binary(Map.get(payload, :message)) ->
        Map.get(payload, :message)

      is_binary(Map.get(payload, "message")) ->
        Map.get(payload, "message")

      is_binary(Map.get(payload, :reason)) ->
        Map.get(payload, :reason)

      is_binary(Map.get(payload, "reason")) ->
        Map.get(payload, "reason")

      is_binary(Map.get(payload, :root)) ->
        Map.get(payload, :root)

      is_binary(Map.get(payload, "root")) ->
        Map.get(payload, "root")

      true ->
        nil
    end
  end

  @spec timeline_kind_for_type(String.t()) :: timeline_kind()
  defp timeline_kind_for_type(type) when is_binary(type) do
    cond do
      String.starts_with?(type, "debugger.protocol_") ->
        :protocol

      String.starts_with?(type, "debugger.update_") ->
        :update

      String.starts_with?(type, "debugger.view_") ->
        :render

      type in [
        "debugger.start",
        "debugger.reset",
        "debugger.reload",
        "debugger.elm_introspect",
        "debugger.elmc_check",
        "debugger.elmc_compile",
        "debugger.elmc_manifest"
      ] ->
        :lifecycle

      true ->
        :other
    end
  end

  defp timeline_kind_for_type(_type), do: :other
end
