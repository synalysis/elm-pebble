defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ValueHelpers.ScalarRead do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int32_t elmc_scene_read_i16(const unsigned char *bytes, int *offset, int limit) {
      if (!bytes || !offset || *offset + 2 > limit) return 0;
      uint16_t raw = (uint16_t)bytes[*offset] | ((uint16_t)bytes[*offset + 1] << 8);
      *offset += 2;
      return (int32_t)((int16_t)raw);
    }

    static int32_t elmc_pebble_scene_read_i32(const unsigned char *bytes, int *offset, int limit) {
      if (!bytes || !offset || *offset + 4 > limit) return 0;
      uint32_t raw = 0;
      for (int i = 0; i < 4; i++) {
        raw |= ((uint32_t)bytes[*offset + i]) << (i * 8);
      }
      *offset += 4;
      return (int32_t)raw;
    }

    """
  end
end
