defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.TagCallbacks.CompassEmbed do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.event_dispatch_bindings()) :: Types.c_source()
  def body(%{compass_dispatch_source: compass_dispatch_source}) do
    compass_dispatch_source
  end
end
