defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.CopyDrawText do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.CopyDrawText.{
    GuardOpen,
    ListWalk,
    StringPath
  }

  @spec body() :: Types.c_source()
  def body do
    [GuardOpen.body(), StringPath.body(), ListWalk.body()]
    |> IO.iodata_to_binary()
  end
end
