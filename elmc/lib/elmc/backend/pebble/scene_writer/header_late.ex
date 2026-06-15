defmodule Elmc.Backend.Pebble.SceneWriter.HeaderLate do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SceneWriter.HeaderLate.{DecodeDecl, Decls, FormatInt}

  @spec body() :: Types.c_source()
  def body do
    [Decls.body(), FormatInt.body(), DecodeDecl.body()]
    |> IO.iodata_to_binary()
  end
end
