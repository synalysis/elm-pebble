defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.LayerWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.LayerWalk.{
    Finish,
    LayerListWalk,
    LayerUnpack
  }

  @spec body() :: Types.c_source()
  def body do
    [LayerListWalk.body(), LayerUnpack.body(), Finish.body()]
    |> IO.iodata_to_binary()
  end
end
