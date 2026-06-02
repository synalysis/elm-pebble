defmodule Ide.Debugger.EventLogFilters do
  @moduledoc false

  alias Ide.Debugger.Types

  @type event :: Types.runtime_event()

  @spec at_or_before_seq([event()], non_neg_integer() | nil) :: [event()]
  def at_or_before_seq(events, nil) when is_list(events), do: events

  def at_or_before_seq(events, cursor_seq)
      when is_list(events) and is_integer(cursor_seq) and cursor_seq >= 0 do
    Enum.filter(events, &(&1.seq <= cursor_seq))
  end

  @spec by_types(Types.runtime_state(), [String.t()] | Types.wire_input() | nil) ::
          Types.runtime_state()
  def by_types(state, nil), do: state
  def by_types(state, []), do: state

  def by_types(state, types) when is_map(state) and is_list(types) do
    allowed = MapSet.new(types)
    %{state | events: Enum.filter(state.events, &MapSet.member?(allowed, &1.type))}
  end

  def by_types(state, _types), do: state

  @spec since_seq(Types.runtime_state(), non_neg_integer() | Types.wire_input() | nil) ::
          Types.runtime_state()
  def since_seq(state, nil), do: state

  def since_seq(state, since_seq)
      when is_map(state) and is_integer(since_seq) and since_seq >= 0 do
    %{state | events: Enum.filter(state.events, &(&1.seq > since_seq))}
  end

  def since_seq(state, _since_seq), do: state
end
