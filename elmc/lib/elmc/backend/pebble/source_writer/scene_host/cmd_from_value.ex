defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.{FromValue, SerializeList}

  @spec body() :: Types.c_source()
  def body do
    [SerializeList.body(), FromValue.body()]
    |> IO.iodata_to_binary()
  end
end
