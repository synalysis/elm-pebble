defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Live.RuntimeSnapshot do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @type events :: Types.events()
  @type timeline_event :: Types.timeline_event()
  @type execution_model :: Types.execution_model()
  @type cursor_snapshot_runtime :: Types.cursor_snapshot_runtime()
  @type debugger_state_map :: Types.debugger_state_map()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type surface :: :watch | :companion | :phone

  @spec snapshot_runtime_at_cursor(events(), maybe_non_neg_integer()) ::
          cursor_snapshot_runtime()
  def snapshot_runtime_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = Timeline.normalize_cursor_seq(events, cursor_seq)
    upper = Util.timeline_upper_seq(events, normalized)

    %{
      watch: nearest_surface_runtime_at_or_before(events, upper, :watch),
      companion: nearest_surface_runtime_at_or_before(events, upper, :companion),
      phone: nearest_surface_runtime_at_or_before(events, upper, :phone)
    }
  end

  def snapshot_runtime_at_cursor(_events, _cursor_seq),
    do: %{watch: nil, companion: nil, phone: nil}

  @spec with_live_runtime_fallback(cursor_snapshot_runtime(), debugger_state_map() | nil) ::
          cursor_snapshot_runtime()
  def with_live_runtime_fallback(snapshot_runtime, debugger_state)
      when is_map(snapshot_runtime) and is_map(debugger_state) do
    %{
      watch: snapshot_runtime.watch || Map.get(debugger_state, :watch),
      companion: snapshot_runtime.companion || Map.get(debugger_state, :companion),
      phone: snapshot_runtime.phone || Map.get(debugger_state, :phone)
    }
  end

  def with_live_runtime_fallback(snapshot_runtime, _debugger_state), do: snapshot_runtime

  @spec nearest_surface_runtime_at_or_before(events(), non_neg_integer(), surface()) ::
          execution_model()
  def nearest_surface_runtime_at_or_before(events, upper_seq, surface)
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

  @spec cursor_runtime(timeline_event() | nil, surface()) :: execution_model()
  defp cursor_runtime(nil, _kind), do: nil
  defp cursor_runtime(event, :watch) when is_map(event), do: Map.get(event, :watch)
  defp cursor_runtime(event, :companion) when is_map(event), do: Map.get(event, :companion)
  defp cursor_runtime(event, :phone) when is_map(event), do: Map.get(event, :phone)
end
