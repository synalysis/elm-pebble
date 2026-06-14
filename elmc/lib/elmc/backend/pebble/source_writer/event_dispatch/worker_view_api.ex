defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.WorkerViewApi do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.WorkerViewApi.{TakeCmd, ViewCmds}

  @spec body() :: Types.c_source()
  def body do
    [TakeCmd.body(), ViewCmds.body()]
    |> IO.iodata_to_binary()
  end
end
