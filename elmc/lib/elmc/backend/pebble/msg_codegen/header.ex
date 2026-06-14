defmodule Elmc.Backend.Pebble.MsgCodegen.Header do
  @moduledoc false

  alias Elmc.Backend.Pebble.{Types, Util}

  @spec macros(Types.msg_constructor_list()) :: Types.header_msg_macros()
  def macros(msg_constructors) do
    %{
      enum_members:
        Enum.map_join(msg_constructors, "\n", fn {name, tag} ->
          "  ELMC_PEBBLE_MSG_#{Util.macro_name(name)} = #{tag},"
        end),
      presence_macros:
        Enum.map_join(msg_constructors, "\n", fn {name, _tag} ->
          "#define ELMC_PEBBLE_HAS_MSG_#{Util.macro_name(name)} 1"
        end)
    }
  end
end
