defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial.{
    DataLogBytes,
    PayloadArray,
    SpeakerPlayNotes,
    SpeakerPlayTracks,
    SpeakerStreamWrite,
    StorageWriteString,
    TupleOpen,
    VibesCustomPattern
  }

  @spec body() :: Types.c_source()
  def body do
    [
      TupleOpen.body(),
      StorageWriteString.body(),
      VibesCustomPattern.body(),
      DataLogBytes.body(),
      SpeakerPlayNotes.body(),
      SpeakerPlayTracks.body(),
      SpeakerStreamWrite.body(),
      PayloadArray.body()
    ]
    |> IO.iodata_to_binary()
  end
end
