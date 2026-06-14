defmodule Elmc.Backend.Pebble.HeaderWriter.AppTypes do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.HeaderWriter.AppTypes.{DrawCmdDecl, KindEnums, MsgEnums}

  @spec body(Types.header_app_types_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    [MsgEnums.body(bindings), DrawCmdDecl.body(bindings), KindEnums.body(bindings)]
    |> IO.iodata_to_binary()
  end
end
