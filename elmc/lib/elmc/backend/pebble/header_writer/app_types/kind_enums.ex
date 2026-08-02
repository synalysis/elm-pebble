defmodule Elmc.Backend.Pebble.HeaderWriter.AppTypes.KindEnums do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body(Types.header_bindings()) :: Types.c_source()
  def body(%{
        draw_kind_enum: draw_kind_enum,
        command_kind_enum: command_kind_enum,
        ui_node_kind_enum: ui_node_kind_enum,
        phone_to_watch_target: phone_to_watch_target,
        watch_model_macros: watch_model_macros,
        watch_color_macros: watch_color_macros
      }) do
    """
    typedef struct {
      int64_t kind;
      int64_t p0;
      int64_t p1;
      int64_t p2;
      int64_t p3;
      int64_t p4;
      int64_t p5;
      char text[128];
      /* Boxed command payload (e.g. companion send message). Owned by the caller
         after elmc_pebble_take_cmd; borrowed from the queue in the *_cmd_at
         inspectors, which clear it. Release with elmc_pebble_cmd_release_value. */
      ElmcValue *value;
    } ElmcPebbleCmd;

    #{draw_kind_enum}

    #{command_kind_enum}

    #{ui_node_kind_enum}

    #define ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET #{phone_to_watch_target}
    #{watch_model_macros}
    #{watch_color_macros}
    """
  end
end
