defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.{
    CopyDrawText,
    ForwardDecls
  }

  @spec body() :: Types.c_source()
  def body do
    [ForwardDecls.body(), CopyDrawText.body()]
    |> IO.iodata_to_binary()
  end
end
