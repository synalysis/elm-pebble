defmodule Elmc.Backend.Pebble.HeaderWriter.AppTypes.MsgEnums do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.header_bindings()) :: Types.c_source()
  def body(%{
        run_mode_enum: run_mode_enum,
        msg_enum_members: msg_enum_members,
        msg_presence_macros: msg_presence_macros,
        button_id_enum: button_id_enum,
        button_event_macros: button_event_macros,
        accel_axis_enum: accel_axis_enum
      }) do
    """
    #{run_mode_enum}

    typedef enum {
      ELMC_PEBBLE_MSG_UNKNOWN = 0,
    #{msg_enum_members}
    } ElmcPebbleMsgTag;

    #{msg_presence_macros}

    #{button_id_enum}
    #{button_event_macros}

    #{accel_axis_enum}

    """
  end
end
