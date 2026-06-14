defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.WindowWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.WindowWalk.{
    Prologue,
    WindowListWalk,
    WindowUnpack
  }

  @spec body() :: Types.c_source()
  def body do
    [Prologue.body(), WindowListWalk.body(), WindowUnpack.body()]
    |> IO.iodata_to_binary()
  end
end
