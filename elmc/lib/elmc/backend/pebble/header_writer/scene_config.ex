defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.HeaderWriter.SceneConfig.{ConfigDefaults, PathProbes, StructDecls}

  @spec body() :: Types.c_source()
  def body do
    [ConfigDefaults.body(), PathProbes.body(), StructDecls.body()]
    |> IO.iodata_to_binary()
  end
end
