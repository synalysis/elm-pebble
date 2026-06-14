defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.{Arena, PayloadCodec}

  @spec body() :: Types.c_source()
  def body do
    [Arena.body(), PayloadCodec.body()]
    |> IO.iodata_to_binary()
  end
end
