defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch do
  @moduledoc false
  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.Emit

  @spec body(Types.source_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    Emit.body(%{
      msg: bindings.msg,
      compass_events?: Map.get(bindings, :compass_events?, false)
    })
  end
end
