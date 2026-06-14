defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.{Decode, Init, Probes}

  @spec body() :: Types.c_source()
  def body do
    [Probes.body(), Decode.body(), Init.body()]
    |> IO.iodata_to_binary()
  end
end
