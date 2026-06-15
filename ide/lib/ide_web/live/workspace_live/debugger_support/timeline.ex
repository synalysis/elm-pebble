defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Timeline do
  @moduledoc false
  @dialyzer :no_match

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline.{DebuggerRows, Lifecycle}

  defdelegate debugger_rows(source, limit \\ 80), to: DebuggerRows
  defdelegate debugger_rows_for_target(rows, target), to: DebuggerRows
  defdelegate debugger_rows_for_mode(rows, mode), to: DebuggerRows
  defdelegate filter_debugger_rows_for_display(rows, debug_mode), to: DebuggerRows
  defdelegate debugger_runtime_status_row?(row), to: DebuggerRows
  defdelegate debugger_http_row?(row), to: DebuggerRows
  defdelegate debugger_timeline_text(rows), to: DebuggerRows
  defdelegate debugger_message_label(message), to: DebuggerRows
  defdelegate selected_debugger_row(source, cursor_seq), to: DebuggerRows
  defdelegate select_debugger_row(rows, cursor_seq), to: DebuggerRows

  defdelegate lifecycle_events_at_cursor(events, cursor_seq, limit \\ 12), to: Lifecycle

  alias Ide.Debugger.CursorSeq
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @spec event_json(Types.events()) :: String.t()
  def event_json(events) when is_list(events) do
    events
    |> Enum.reverse()
    |> Jason.encode!(pretty: true)
  end

  def event_json(event) when is_map(event), do: Jason.encode!(event, pretty: true)
  def event_json(_events), do: "[]"

  @spec payload_diff_json(Types.timeline_event() | nil, Types.timeline_event() | nil) :: String.t()
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

  @spec event_type_counts(Types.events()) :: Types.event_type_counts()
  def event_type_counts(events) when is_list(events) do
    events
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, grouped} -> {type, length(grouped)} end)
    |> Enum.sort_by(fn {type, _} -> type end)
  end

  def event_type_counts(_events), do: []

  @spec event_summaries(Types.events()) :: [Types.event_summary()]
  def event_summaries(events) when is_list(events) do
    Enum.map(events, fn event ->
      payload = Map.get(event, :payload, %{})

      %{
        seq: Map.get(event, :seq, 0),
        type: Map.get(event, :type, "unknown"),
        target: Util.payload_target(payload),
        message: Util.payload_message(payload)
      }
    end)
  end

  def event_summaries(_events), do: []

  @spec protocol_exchange_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) ::
          [
            Types.protocol_row()
          ]
  def protocol_exchange_at_cursor(events, cursor_seq, limit \\ 40)

  def protocol_exchange_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

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
        from: Util.protocol_payload_field(payload, :from),
        to: Util.protocol_payload_field(payload, :to),
        message: Util.protocol_payload_field(payload, :message)
      }
    end)
  end

  def protocol_exchange_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec update_messages_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) ::
          [
            Types.update_message_row()
          ]
  def update_messages_at_cursor(events, cursor_seq, limit \\ 40)

  def update_messages_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e -> e.type == "debugger.update_in" and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}

      %{
        seq: e.seq,
        target: Util.protocol_payload_field(payload, :target),
        message: Util.protocol_payload_field(payload, :message)
      }
    end)
  end

  def update_messages_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec debug_mode_enabled?(Types.socket()) :: boolean()
  def debug_mode_enabled?(socket) do
    case socket do
      %{assigns: %{debug_mode: true}} -> true
      _ -> false
    end
  end

  @spec render_events_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) :: [
          Types.render_event_row()
        ]
  def render_events_at_cursor(events, cursor_seq, limit \\ 24)

  def render_events_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e -> e.type == "debugger.view_render" and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}

      %{
        seq: e.seq,
        target: Util.protocol_payload_field(payload, :target),
        root: Util.protocol_payload_field(payload, :root)
      }
    end)
  end

  def render_events_at_cursor(_events, _cursor_seq, _limit), do: []


  @spec filtered_event_summaries(Types.events(), Types.timeline_kind(), pos_integer()) :: [
          Types.event_summary()
        ]
  def filtered_event_summaries(events, kind, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    events
    |> event_summaries()
    |> Enum.filter(fn row -> kind == :all or Util.timeline_kind_for_type(row.type) == kind end)
    |> Enum.take(limit)
  end

  def filtered_event_summaries(_events, _kind, _limit), do: []

  @spec filtered_event_summaries(Types.events(), Types.timeline_kind(), pos_integer(), String.t()) ::
          [Types.event_summary()]
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

  @spec highlight_fragments(String.t(), String.t()) :: [Types.highlight_fragment()]
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

  @spec seq_bounds(Types.events()) :: {non_neg_integer(), non_neg_integer()} | nil
  def seq_bounds(events) when is_list(events) and events != [] do
    seqs = Enum.map(events, & &1.seq)
    {Enum.min(seqs), Enum.max(seqs)}
  end

  def seq_bounds(_events), do: nil

  @spec min_seq(Types.events()) :: non_neg_integer()
  def min_seq(events) do
    case seq_bounds(events) do
      {min_seq, _max_seq} -> min_seq
      nil -> 0
    end
  end

  @spec max_seq(Types.events()) :: non_neg_integer()
  def max_seq(events) do
    case seq_bounds(events) do
      {_min_seq, max_seq} -> max_seq
      nil -> 0
    end
  end

  @spec normalize_cursor_seq(Types.events(), Types.maybe_non_neg_integer()) ::
          Types.maybe_non_neg_integer()
  def normalize_cursor_seq(events, cursor_seq) do
    CursorSeq.resolve_at_or_before(events, cursor_seq)
  end
end
