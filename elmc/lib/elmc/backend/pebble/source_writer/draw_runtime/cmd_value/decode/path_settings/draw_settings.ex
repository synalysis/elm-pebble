defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.DrawSettings do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.DrawSettings.{
    KindSwitch,
    ResetFields
  }

  @spec body() :: Types.c_source()
  def body do
    [ResetFields.body(), KindSwitch.body()]
    |> IO.iodata_to_binary()
  end
end
