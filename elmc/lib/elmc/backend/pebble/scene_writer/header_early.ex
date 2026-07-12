defmodule Elmc.Backend.Pebble.SceneWriter.HeaderEarly do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec enums() :: Types.c_source()
  def enums do
    """
    enum {
      ELMC_SCENE_PL_EMPTY = 0,
      ELMC_SCENE_PL_U8 = 1,
      ELMC_SCENE_PL_I32 = 4,
      ELMC_SCENE_PL_PIXEL = 5,
      ELMC_SCENE_PL_CIRCLE_U8 = 7,
      ELMC_SCENE_PL_TEXT_LABEL_BASE = 8,
      ELMC_SCENE_PL_COORDS_COLOR_U8 = 9,
      ELMC_SCENE_PL_CIRCLE_I32 = 10,
      ELMC_SCENE_PL_ROUND_U8 = 11,
      ELMC_SCENE_PL_COORDS_COLOR_I32 = 12,
      ELMC_SCENE_PL_ROUND_I32 = 14,
      ELMC_SCENE_PL_TEXT_BASE = 16,
      ELMC_SCENE_PL_FULL = 24
    };

    """
  end

  @spec body() :: Types.c_source()
  def body do
    """
    typedef struct ElmcPebbleApp ElmcPebbleApp;

    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    #{enums()}
    #endif
    """
  end

  @spec struct_decl() :: Types.c_source()
  def struct_decl do
    """
    typedef struct {
      ElmcPebbleApp *app;
      int command_count;
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
      ElmcPebbleDrawCmd *out_cmds;
      int max_cmds;
      int out_count;
      int skip_remaining;
    #endif
    } ElmcSceneWriter;

    void elmc_scene_writer_init_app(ElmcSceneWriter *writer, ElmcPebbleApp *app);
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
    void elmc_scene_writer_init_stream(
        ElmcSceneWriter *writer,
        ElmcPebbleApp *app,
        ElmcPebbleDrawCmd *out_cmds,
        int max_cmds,
        int skip);
    #endif

    """
  end
end
