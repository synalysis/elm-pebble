defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.FixedScalars do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          switch (payload_len) {
          case ELMC_SCENE_PL_EMPTY:
            return 0;
        #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR || ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR || ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR || ELMC_PEBBLE_FEATURE_DRAW_CLEAR || ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE || ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH || ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
          case ELMC_SCENE_PL_U8:
            return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p0);
          case ELMC_SCENE_PL_I32:
            return elmc_scene_writer_put_i32(writer, cmd->p0);
        #endif
    """
  end
end
