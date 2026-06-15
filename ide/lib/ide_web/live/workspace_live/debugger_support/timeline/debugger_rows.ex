defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Timeline.DebuggerRows do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Live.RuntimeSnapshot
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @type debugger_row_source :: Types.debugger_row_source()
  @type debugger_row_wire :: Types.debugger_row_wire()
  @type debugger_row :: Types.debugger_row()
  @type events :: Types.events()

  @debugger_row_keys [
    :seq,
    :debugger_seq,
    :raw_seq,
    :type,
    :target,
    :message,
    :message_source,
    :selected_runtime,
    :other_runtime,
    :watch_runtime,
    :companion_runtime,
    :phone_runtime
  ]

  @spec debugger_rows(debugger_row_source(), pos_integer()) :: [debugger_row()]
  def debugger_rows(source, limit \\ 80)

  def debugger_rows(%{} = debugger_state, limit) when is_integer(limit) and limit > 0 do
    case Map.get(debugger_state, :debugger_timeline) ||
           Map.get(debugger_state, "debugger_timeline") do
      rows when is_list(rows) and rows != [] ->
        rows
        |> Enum.sort_by(&debugger_row_seq/1, :desc)
        |> Enum.take(limit)
        |> Enum.map(&normalize_debugger_row/1)
        |> Enum.map(&ensure_debugger_row/1)

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
      target = Util.debugger_target(Util.protocol_payload_field(payload, :target))

      watch_runtime = RuntimeSnapshot.nearest_surface_runtime_at_or_before(events, raw_seq, :watch)
      companion_runtime = RuntimeSnapshot.nearest_surface_runtime_at_or_before(events, raw_seq, :companion)
      phone_runtime = RuntimeSnapshot.nearest_surface_runtime_at_or_before(events, raw_seq, :phone)
      companion_app_runtime = Util.companion_or_phone_runtime(companion_runtime, phone_runtime)

      %{
        seq: debugger_seq,
        debugger_seq: debugger_seq,
        raw_seq: raw_seq,
        type: debugger_type_from_event(event),
        target: target,
        message: Util.protocol_payload_field(payload, :message) || "",
        message_source: Util.protocol_payload_field(payload, :message_source),
        selected_runtime:
          Util.debugger_target_runtime(target, watch_runtime, companion_app_runtime),
        other_runtime: Util.debugger_other_runtime(target, watch_runtime, companion_app_runtime),
        watch_runtime: watch_runtime,
        companion_runtime: companion_app_runtime,
        phone_runtime: phone_runtime
      }
      |> ensure_debugger_row()
    end)
  end

  def debugger_rows(_source, _limit), do: []

  @spec ensure_debugger_row(debugger_row_wire() | debugger_row()) :: debugger_row()
  defp ensure_debugger_row(%{} = row) do
    row
    |> normalize_debugger_row()
    |> Map.take(@debugger_row_keys)
  end

  @spec debugger_rows_for_target([debugger_row_wire() | debugger_row()], String.t()) :: [
          debugger_row()
        ]
  def debugger_rows_for_target(rows, target)
      when is_list(rows) and target in ["watch", "companion"] do
    rows
    |> Enum.filter(fn row -> Map.get(row, :target) == target end)
    |> Enum.map(&ensure_debugger_row/1)
    |> newest_first()
  end

  def debugger_rows_for_target(_rows, _target), do: []

  @spec debugger_rows_for_mode([debugger_row_wire() | debugger_row()], String.t()) :: [
          debugger_row()
        ]
  def debugger_rows_for_mode(rows, "watch"), do: debugger_rows_for_target(rows, "watch")
  def debugger_rows_for_mode(rows, "companion"), do: debugger_rows_for_target(rows, "companion")

  def debugger_rows_for_mode(rows, "mixed") when is_list(rows),
    do: rows |> Enum.map(&ensure_debugger_row/1) |> newest_first()

  def debugger_rows_for_mode(rows, "separate") when is_list(rows),
    do: rows |> Enum.map(&ensure_debugger_row/1) |> newest_first()

  def debugger_rows_for_mode(_rows, _mode), do: []

  @doc """
  Hides internal runtime executor diagnostics from the user-facing timeline unless
  IDE debug mode is enabled.
  """
  @spec filter_debugger_rows_for_display([Types.debugger_row()], boolean()) :: [
          Types.debugger_row()
        ]
  def filter_debugger_rows_for_display(rows, true) when is_list(rows), do: rows

  def filter_debugger_rows_for_display(rows, _debug_mode) when is_list(rows) do
    Enum.reject(rows, fn row ->
      debugger_runtime_status_row?(row) or debugger_http_row?(row)
    end)
  end

  def filter_debugger_rows_for_display(_rows, _debug_mode), do: []

  @spec debugger_runtime_status_row?(Types.debugger_row()) :: boolean()
  def debugger_runtime_status_row?(row) when is_map(row) do
    type = Map.get(row, :type) || Map.get(row, "type")
    source = Map.get(row, :message_source) || Map.get(row, "message_source")
    type == "runtime" and source == "runtime_status"
  end

  def debugger_runtime_status_row?(_row), do: false

  @spec debugger_http_row?(Types.debugger_row()) :: boolean()
  def debugger_http_row?(row) when is_map(row) do
    type = Map.get(row, :type) || Map.get(row, "type")
    source = Map.get(row, :message_source) || Map.get(row, "message_source")

    type == "http" or source in ["http", "http_pending"]
  end

  def debugger_http_row?(_row), do: false

  @spec debugger_timeline_text([Types.debugger_row()]) :: String.t()
  def debugger_timeline_text(rows) when is_list(rows) do
    rows
    |> newest_first()
    |> Enum.map(&debugger_timeline_line/1)
    |> Enum.join("\n")
  end

  def debugger_timeline_text(_rows), do: ""

  @spec newest_first(Types.events()) :: Types.events()
  defp newest_first(rows) when is_list(rows),
    do: Enum.sort_by(rows, &Map.get(&1, :seq, 0), :desc)

  @spec debugger_timeline_line(debugger_row()) :: String.t()
  defp debugger_timeline_line(row) when is_map(row) do
    seq = Map.get(row, :seq) || Map.get(row, "seq") || "?"
    target = Map.get(row, :target) || Map.get(row, "target") || "-"
    type = Map.get(row, :type) || Map.get(row, "type") || "update"
    message = Map.get(row, :message) || Map.get(row, "message") || ""
    source = Map.get(row, :message_source) || Map.get(row, "message_source")

    type_label =
      case {type, source} do
        {"http", _} -> "http"
        {_, "http"} -> "http"
        {_, "http_pending"} -> "http (pending)"
        {other, _} -> other
      end

    "##{seq} [#{target}] #{type_label} #{message}"
    |> String.trim()
  end

  @spec normalize_debugger_row(debugger_row_wire()) :: debugger_row()
  defp normalize_debugger_row(row) when is_map(row) do
    seq = debugger_row_seq(row)
    raw_seq = Map.get(row, :raw_seq) || Map.get(row, "raw_seq") || seq
    target = Util.debugger_target(Map.get(row, :target) || Map.get(row, "target"))
    watch_runtime =
      Map.get(row, :watch_runtime) || Map.get(row, "watch_runtime") || Map.get(row, :watch) ||
        Map.get(row, "watch")

    companion_runtime =
      Map.get(row, :companion_runtime) || Map.get(row, "companion_runtime") ||
        Map.get(row, :companion) || Map.get(row, "companion")

    phone_runtime =
      Map.get(row, :phone_runtime) || Map.get(row, "phone_runtime") || Map.get(row, :phone) ||
        Map.get(row, "phone")
    companion_app_runtime = Util.companion_or_phone_runtime(companion_runtime, phone_runtime)

    %{
      seq: seq,
      debugger_seq: seq,
      raw_seq: raw_seq,
      type: Map.get(row, :type) || Map.get(row, "type") || "update",
      target: target,
      message: Map.get(row, :message) || Map.get(row, "message") || "",
      message_source: Map.get(row, :message_source) || Map.get(row, "message_source"),
      selected_runtime:
        Util.debugger_target_runtime(target, watch_runtime, companion_app_runtime),
      other_runtime: Util.debugger_other_runtime(target, watch_runtime, companion_app_runtime),
      watch_runtime: watch_runtime,
      companion_runtime: companion_app_runtime,
      phone_runtime: phone_runtime
    }
  end

  @spec debugger_row_seq(debugger_row_wire()) :: non_neg_integer()
  defp debugger_row_seq(row) when is_map(row) do
    case Map.get(row, :seq) || Map.get(row, "seq") || Map.get(row, :debugger_seq) ||
           Map.get(row, "debugger_seq") do
      seq when is_integer(seq) and seq >= 0 -> seq
      _ -> 0
    end
  end

  defp debugger_row_seq(_row), do: 0

  @spec debugger_type_from_event(Types.timeline_event()) :: String.t()
  defp debugger_type_from_event(%{type: "debugger.init_in"}), do: "init"
  defp debugger_type_from_event(%{type: "debugger.update_in"}), do: "update"
  defp debugger_type_from_event(_event), do: "update"

  @spec debugger_message_label(String.t() | nil | Types.wire_value()) :: String.t()
  def debugger_message_label(message) when is_binary(message) do
    case Regex.run(~r/^([A-Z][A-Za-z0-9_]*)(?:\s+)([\{\[].*)$/, String.trim(message)) do
      [_, constructor, json] ->
        case Jason.decode(json) do
          {:ok, value} -> "#{constructor} #{Util.elm_value(value)}"
          {:error, _reason} -> message
        end

      _ ->
        message
    end
  end

  def debugger_message_label(nil), do: ""
  def debugger_message_label(message), do: to_string(message)

  @spec selected_debugger_row(debugger_row_source(), Types.maybe_non_neg_integer()) ::
          debugger_row() | nil
  def selected_debugger_row(source, cursor_seq) do
    select_debugger_row(debugger_rows(source, 500), cursor_seq)
  end

  @spec select_debugger_row([debugger_row()], Types.maybe_non_neg_integer()) ::
          debugger_row() | nil
  def select_debugger_row(rows, cursor_seq) when is_list(rows) do
    newest_rows = Enum.sort_by(rows, &Map.get(&1, :seq, 0), :desc)
    oldest_rows = Enum.reverse(newest_rows)

    cond do
      rows == [] ->
        nil

      is_integer(cursor_seq) ->
        Enum.find(oldest_rows, fn row -> row.seq >= cursor_seq end) || List.first(newest_rows)

      true ->
        List.first(newest_rows)
    end
  end
end
