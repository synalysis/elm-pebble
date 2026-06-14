defmodule Elmc.Backend.Pebble.MsgCodegen do
  @moduledoc false

  alias Elmc.Backend.Pebble.MsgCodegen.{Fragments, Header, TickArity}
  alias Elmc.Backend.Pebble.Types

  @spec header_macros(Types.msg_constructor_list()) :: Types.header_msg_macros()
  defdelegate header_macros(msg_constructors), to: Header, as: :macros

  @spec tick_dispatch_line(boolean()) :: Types.c_source()
  defdelegate tick_dispatch_line(has_payload?), to: TickArity, as: :dispatch_line

  @spec fragments(Types.msg_constructor_list(), Types.msg_constructor_arities()) ::
          Types.msg_fragments()
  defdelegate fragments(msg_constructors, msg_constructor_arities), to: Fragments, as: :build

  @spec storage_string_callback_names() :: [Types.msg_constructor_name()]
  def storage_string_callback_names do
    ["StorageStringLoaded", "GotStorageString", "GotString"]
  end
end
