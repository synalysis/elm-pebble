defmodule Ide.Debugger.TraceExchange.Events do
  @moduledoc false

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type runtime_event :: Types.runtime_event()

  @spec event_at_seq([runtime_event()], integer() | nil) :: runtime_event() | nil
  def event_at_seq(events, seq) when is_list(events) and is_integer(seq),
    do: Enum.find(events, &(&1.seq == seq))

  def event_at_seq(_events, _seq), do: nil

  @spec snapshot_surface(Surface.t() | map(), Surface.t() | map()) :: map()
  def snapshot_surface(%Surface{} = surface, _fallback), do: Surface.to_map(surface)
  def snapshot_surface(surface, _fallback) when is_map(surface), do: surface
end
