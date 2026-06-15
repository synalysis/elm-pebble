defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.ContextSettings.ContextPushPop do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_CONTEXT
      case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
      case ELMC_PEBBLE_DRAW_POP_CONTEXT:
        return ELMC_SCENE_PL_EMPTY;
    #endif
"""
  end
end
