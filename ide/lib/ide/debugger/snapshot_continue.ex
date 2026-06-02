defmodule Ide.Debugger.SnapshotContinue do
  @moduledoc false

  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.TraceExchange
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @spec apply(
          Types.runtime_state(),
          Types.wire_input(),
          append_event_fn()
        ) :: Types.runtime_state()
  def apply(state, cursor_seq, append_event)
      when is_map(state) and is_function(append_event, 3) do
    events = Map.get(state, :events, [])
    resolved_seq = CursorSeq.resolve_at_or_before(events, cursor_seq)
    selected_event = TraceExchange.event_at_seq(events, resolved_seq)

    apply_selected(state, selected_event, resolved_seq, append_event)
  end

  @spec apply_selected(
          Types.runtime_state(),
          Types.runtime_event() | nil,
          non_neg_integer() | nil,
          append_event_fn()
        ) :: Types.runtime_state()
  def apply_selected(state, selected_event, resolved_seq, append_event)
      when is_map(state) and is_function(append_event, 3) do
    if is_map(selected_event) do
      state
      |> Map.put(:running, true)
      |> restore_surfaces(selected_event)
      |> append_event.(
        "debugger.snapshot_continue",
        Types.SnapshotContinueEventPayload.from_cursor(resolved_seq, "cursor_snapshot")
      )
    else
      state
    end
  end

  @spec restore_surfaces(Types.runtime_state(), Types.runtime_event()) :: Types.runtime_state()
  def restore_surfaces(state, selected_event) when is_map(state) and is_map(selected_event) do
    state
    |> Map.put(
      :watch,
      TraceExchange.snapshot_surface(
        Map.get(selected_event, :watch),
        RuntimeSurfaces.default_watch()
      )
    )
    |> Map.put(
      :companion,
      TraceExchange.snapshot_surface(
        Map.get(selected_event, :companion),
        RuntimeSurfaces.default_companion()
      )
    )
    |> Map.put(
      :phone,
      TraceExchange.snapshot_surface(
        Map.get(selected_event, :phone),
        RuntimeSurfaces.default_phone()
      )
    )
  end
end
