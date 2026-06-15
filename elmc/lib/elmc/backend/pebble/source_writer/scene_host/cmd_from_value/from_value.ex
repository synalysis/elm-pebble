defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.{
    CmdPayload,
    Prologue,
    TupleDefault,
    TupleSpecial
  }

  @spec body() :: Types.c_source()
  def body do
    [Prologue.body(), CmdPayload.body(), TupleSpecial.body(), TupleDefault.body()]
    |> IO.iodata_to_binary()
  end
end
