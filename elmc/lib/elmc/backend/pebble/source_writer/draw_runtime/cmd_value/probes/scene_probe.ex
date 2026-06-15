defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes.SceneProbe do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes.SceneProbe.{
    EmitFn,
    EnabledFn
  }

  @spec body() :: Types.c_source()
  def body do
    [EnabledFn.body(), EmitFn.body()]
    |> IO.iodata_to_binary()
  end
end
