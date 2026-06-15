defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.AppMessage do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.AppMessage.{Dispatch, MsgDecode}

  @spec body(Types.event_dispatch_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    [MsgDecode.body(bindings), Dispatch.body()]
    |> IO.iodata_to_binary()
  end
end
