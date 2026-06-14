defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.{LayerWalk, UiTag, WindowWalk}

  @spec body() :: Types.c_source()
  def body do
    [UiTag.body(), WindowWalk.body(), LayerWalk.body()]
    |> IO.iodata_to_binary()
  end
end
