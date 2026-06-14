defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.{Extract, Hash}

  @spec body() :: Types.c_source()
  def body do
    [
      "#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)\n",
      Hash.body(),
      Extract.body(),
      "#endif\n"
    ]
    |> IO.iodata_to_binary()
  end
end
