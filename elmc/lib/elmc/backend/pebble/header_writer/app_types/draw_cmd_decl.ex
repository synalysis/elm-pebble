defmodule Elmc.Backend.Pebble.HeaderWriter.AppTypes.DrawCmdDecl do
  @moduledoc false

  alias Elmc.Backend.Pebble.SceneWriter
  alias Elmc.Backend.Pebble.Types

  @spec body(Types.header_bindings()) :: Types.c_source()
  def body(%{scene_writer_late: scene_writer_late, entry_view_scene_append: entry_view_scene_append}) do
    """
    typedef struct {
      int32_t kind;
      int32_t p0;
      int32_t p1;
      int32_t p2;
      int32_t p3;
      int32_t p4;
      int32_t p5;
      union {
        char text[64];
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
        struct {
          int16_t path_x[16];
          int16_t path_y[16];
          int16_t path_offset_x;
          int16_t path_offset_y;
          int16_t path_rotation;
          uint8_t path_point_count;
        };
    #endif
      };
    } ElmcPebbleDrawCmd;

    #{SceneWriter.header_struct_decl()}

    #{scene_writer_late}

    RC #{entry_view_scene_append}(
        ElmcValue ** const args,
        const int argc,
        ElmcSceneWriter * const writer);

    """
  end
end
