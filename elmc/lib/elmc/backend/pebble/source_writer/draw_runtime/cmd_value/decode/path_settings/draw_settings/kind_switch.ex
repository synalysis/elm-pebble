defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.DrawSettings.KindSwitch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          switch (setting_tag) {
        #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH
            case 1: out_cmd->kind = ELMC_PEBBLE_DRAW_STROKE_WIDTH; return 0;
        #endif
        #if ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
            case 2: out_cmd->kind = ELMC_PEBBLE_DRAW_ANTIALIASED; return 0;
        #endif
        #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR
            case 3: out_cmd->kind = ELMC_PEBBLE_DRAW_STROKE_COLOR; return 0;
        #endif
        #if ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR
            case 4: out_cmd->kind = ELMC_PEBBLE_DRAW_FILL_COLOR; return 0;
        #endif
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR
            case 5: out_cmd->kind = ELMC_PEBBLE_DRAW_TEXT_COLOR; return 0;
        #endif
        #if ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
            case 6: out_cmd->kind = ELMC_PEBBLE_DRAW_COMPOSITING_MODE; return 0;
        #endif
            default: return -3;
          }
        }

    """
  end
end
