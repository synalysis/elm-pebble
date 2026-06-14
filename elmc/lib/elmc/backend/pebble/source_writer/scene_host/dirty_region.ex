defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.{CmdBounds, Compute, RectUtils}

  @spec body() :: Types.c_source()
  def body do
    [
      "#if ELMC_PEBBLE_DIRTY_REGION_ENABLED\n",
      RectUtils.body(),
      CmdBounds.body(),
      Compute.body(),
      "#else\n#endif\n"
    ]
    |> IO.iodata_to_binary()
  end
end
