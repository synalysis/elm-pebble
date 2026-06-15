defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes.{
    SceneProbe,
    ValueShape
  }

  @spec body() :: Types.c_source()
  def body do
    [SceneProbe.body(), ValueShape.body()]
    |> IO.iodata_to_binary()
  end
end
