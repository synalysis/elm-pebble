defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.{
    ApliteDirectActive,
    ArenaSizing,
    DirtyRegionDefault,
    SceneCacheDefault
  }

  @spec body() :: Types.c_source()
  def body do
    [ApliteDirectActive.body(), SceneCacheDefault.body(), DirtyRegionDefault.body(), ArenaSizing.body()]
    |> IO.iodata_to_binary()
  end
end
