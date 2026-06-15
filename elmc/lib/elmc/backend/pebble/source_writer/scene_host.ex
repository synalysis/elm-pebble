defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.{
    CmdFromValue,
    DirtyRegion,
    SceneDecode,
    SubHelpers,
    VirtualUi,
    WindowDrawEmit
  }

  @spec body() :: Types.c_source()
  def body do
    [
      SceneDecode.body(),
      DirtyRegion.body(),
      WindowDrawEmit.body(),
      CmdFromValue.body(),
      VirtualUi.body(),
      SubHelpers.body()
    ]
    |> IO.iodata_to_binary()
  end
end
