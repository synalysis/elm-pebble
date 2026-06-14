defmodule Elmc.Backend.Pebble.HeaderWriter.ApiDecls do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.HeaderWriter.ApiDecls.{
    EventHandlers,
    InitDispatch,
    RuntimeApi,
    ViewSceneApi
  }

  @spec body() :: Types.c_source()
  def body do
    [InitDispatch.body(), EventHandlers.body(), ViewSceneApi.body(), RuntimeApi.body()]
    |> IO.iodata_to_binary()
  end
end
