defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.FromValue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.FromValue.{
    Prologue,
    TupleDefault,
    TupleOpen,
    TuplePath,
    TupleText
  }

  @spec body() :: Types.c_source()
  def body do
    [
      Prologue.body(),
      TupleOpen.body(),
      TuplePath.body(),
      TupleText.body(),
      TupleDefault.body()
    ]
    |> IO.iodata_to_binary()
  end
end
