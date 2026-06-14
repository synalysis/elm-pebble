defmodule Elmc.Backend.Pebble.HeaderWriter.AppTypes.KindEnums do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.header_app_types_bindings()) :: Types.c_source()
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
