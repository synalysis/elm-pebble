defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.{FromValue, Helpers, PathSettings}

  @spec body() :: Types.c_source()
  def body do
    [Helpers.body(), FromValue.body(), PathSettings.body()]
    |> IO.iodata_to_binary()
  end
end
