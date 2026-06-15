defmodule Elmc.Backend.Pebble.MsgCodegen.DecodeCases do
  @moduledoc false

  alias Elmc.Backend.Pebble.{Types, Util}

  @spec switch_cases(Types.msg_constructor_list()) :: Types.c_source()
  def switch_cases(msg_constructors) do
    Enum.map_join(msg_constructors, "\n", fn {name, tag} ->
      "      case ELMC_PEBBLE_MSG_#{Util.macro_name(name)}: *out_tag = #{tag}; return 0;"
    end)
  end
end
