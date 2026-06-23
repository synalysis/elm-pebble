defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Live.Cursor do
  @moduledoc false

  alias Ide.Debugger.CursorSeq
  alias Ide.Debugger.RuntimePreview
  alias Phoenix.Component
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Live.{RuntimeSnapshot, Triggers}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util.Debugger, as: DebuggerUtil

  @type socket :: Types.socket()
  @type debugger_state_map :: Types.debugger_state_map()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type cursor_snapshot_runtime :: Types.cursor_snapshot_runtime()
  @type debugger_assigns_result :: Types.debugger_assigns_result()

  @spec assign_timeline(socket(), debugger_state_map()) :: socket()
  def assign_timeline(socket, debugger_state) do
    events = Map.get(debugger_state, :events, [])

    cursor_seq =
      normalize_cursor_seq(debugger_state, events, socket.assigns[:debugger_cursor_seq])

    snapshot_runtime =
      events
      |> RuntimeSnapshot.snapshot_runtime_at_cursor(cursor_seq)
      |> RuntimeSnapshot.with_live_runtime_fallback(debugger_state)

    debug_mode = Timeline.debug_mode_enabled?(socket)
    debugger = build_assigns(cursor_seq, snapshot_runtime, debugger_state, debug_mode)

    socket
    |> Component.assign(:debugger_state, debugger_state)
    |> Component.assign(:debugger_cursor_watch_runtime, snapshot_runtime.watch)
    |> Component.assign(:debugger_cursor_companion_runtime, snapshot_runtime.companion)
    |> Component.assign(:debugger_cursor_phone_runtime, snapshot_runtime.phone)
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
    |> Component.assign(:debugger_trigger_buttons, Triggers.trigger_buttons(debugger_state))
    |> Component.assign(
      :debugger_watch_trigger_buttons,
      Triggers.subscription_trigger_buttons(debugger_state, :watch)
    )
    |> Component.assign(
      :debugger_companion_trigger_buttons,
      Triggers.subscription_trigger_buttons(debugger_state, :companion)
    )
    |> Component.assign(:debugger_watch_auto_fire, Triggers.auto_fire_enabled?(debugger_state, :watch))
    |> Component.assign(
      :debugger_companion_auto_fire,
      Triggers.auto_fire_enabled?(debugger_state, :companion)
    )
    |> Component.assign(
      :debugger_auto_fire_subscriptions,
      Triggers.auto_fire_subscriptions(debugger_state)
    )
    |> Component.assign(:debugger_disabled_subscriptions, Triggers.disabled_subscriptions(debugger_state))
    |> Component.assign(:debugger_speaker_effect, Ide.Debugger.SpeakerEffects.latest(debugger_state))
  end

  @spec assign_cursor(socket(), maybe_non_neg_integer()) :: socket()
  def assign_cursor(socket, cursor_seq) do
    events = events_from_socket(socket)
    normalized_cursor = Timeline.normalize_cursor_seq(events, cursor_seq)

    snapshot_runtime =
      events
      |> RuntimeSnapshot.snapshot_runtime_at_cursor(normalized_cursor)
      |> RuntimeSnapshot.with_live_runtime_fallback(socket.assigns[:debugger_state])

    debug_mode = Timeline.debug_mode_enabled?(socket)

    debugger =
      build_assigns(
        normalized_cursor,
        snapshot_runtime,
        socket.assigns[:debugger_state],
        debug_mode
      )

    socket
    |> Component.assign(:debugger_cursor_watch_runtime, snapshot_runtime.watch)
    |> Component.assign(:debugger_cursor_companion_runtime, snapshot_runtime.companion)
    |> Component.assign(:debugger_cursor_phone_runtime, snapshot_runtime.phone)
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
  end

  @spec move_cursor(socket(), :back | :forward) :: socket()
  def move_cursor(socket, direction) do
    events = events_from_socket(socket)
    cursor_seq = socket.assigns[:debugger_cursor_seq]
    seqs = Enum.map(events, & &1.seq)

    next_cursor =
      case Enum.find_index(seqs, &(&1 == cursor_seq)) do
        nil ->
          Timeline.normalize_cursor_seq(events, nil)

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
  def assign_debugger_cursor(socket, debugger_cursor_seq) do
    debugger_state = socket.assigns[:debugger_state]

    snapshot_runtime = %{
      watch: socket.assigns[:debugger_cursor_watch_runtime],
      companion: socket.assigns[:debugger_cursor_companion_runtime],
      phone: socket.assigns[:debugger_cursor_phone_runtime]
    }

    debug_mode = Timeline.debug_mode_enabled?(socket)
    debugger = build_assigns(debugger_cursor_seq, snapshot_runtime, debugger_state, debug_mode)

    socket
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
  end

  @spec jump_latest(socket()) :: socket()
  def jump_latest(socket) do
    debug_mode = Timeline.debug_mode_enabled?(socket)

    latest_seq =
      case socket.assigns[:debugger_state] do
        %{} = debugger_state -> latest_seq(debugger_state, debug_mode)
        _ -> nil
      end

    case latest_seq do
      seq when is_integer(seq) ->
        socket
        |> assign_debugger_cursor(seq)
        |> Component.assign(:debugger_follow_latest, true)

      _ ->
        socket
    end
  end

  @spec at_latest?(socket()) :: boolean()
  def at_latest?(socket) do
    debug_mode = Timeline.debug_mode_enabled?(socket)

    latest_seq =
      case socket.assigns[:debugger_state] do
        %{} = debugger_state -> latest_seq(debugger_state, debug_mode)
        _ -> nil
      end

    case latest_seq do
      seq when is_integer(seq) ->
        cursor_seq = socket.assigns[:debugger_cursor_seq]
        is_nil(cursor_seq) or cursor_seq == seq

      _ ->
        is_nil(socket.assigns[:debugger_cursor_seq])
    end
  end

  @spec latest_seq(debugger_state_map(), boolean()) :: maybe_non_neg_integer()
  def latest_seq(debugger_state, debug_mode) when is_map(debugger_state) do
    debugger_state
    |> Timeline.debugger_rows()
    |> Timeline.filter_debugger_rows_for_display(debug_mode)
    |> Enum.map(&Map.get(&1, :seq))
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      seqs -> Enum.max(seqs)
    end
  end

  @spec build_assigns(
          maybe_non_neg_integer(),
          cursor_snapshot_runtime(),
          debugger_state_map() | nil,
          boolean()
        ) :: debugger_assigns_result()
  def build_assigns(cursor_seq, snapshot_runtime, debugger_state, debug_mode) do
    rows =
      debugger_state
      |> Timeline.debugger_rows()
      |> Timeline.filter_debugger_rows_for_display(debug_mode)

    selected = Timeline.select_debugger_row(rows, cursor_seq)
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

    phone_runtime =
      case selected do
        %{phone_runtime: %{} = runtime} -> runtime
        _ -> snapshot_runtime.phone
      end

    companion_runtime = DebuggerUtil.companion_or_phone_runtime(companion_runtime, phone_runtime)

    watch_view_runtime =
      case watch_runtime do
        %{} = runtime -> RuntimePreview.render_view_from_surface(runtime, :watch) || runtime
        _ -> nil
      end

    %{
      rows: rows,
      cursor_seq: resolved_cursor_seq,
      selected: selected,
      watch_runtime: watch_runtime,
      companion_runtime: companion_runtime,
      watch_view_runtime: watch_view_runtime
    }
  end

  @spec normalize_cursor_seq(debugger_state_map(), Types.events(), maybe_non_neg_integer()) ::
          maybe_non_neg_integer()
  def normalize_cursor_seq(debugger_state, events, cursor_seq) do
    case Timeline.normalize_cursor_seq(events, cursor_seq) do
      seq when is_integer(seq) ->
        seq

      _ ->
        debugger_state
        |> Timeline.debugger_rows(500)
        |> CursorSeq.resolve_at_or_before(cursor_seq)
    end
  end

  @spec events_from_socket(socket()) :: Types.events()
  defp events_from_socket(socket) do
    case socket.assigns[:debugger_state] do
      %{events: list} when is_list(list) -> list
      _ -> []
    end
  end
end
