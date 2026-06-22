defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SequenceHelpers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT || ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT
    #ifndef ELM_PEBBLE_RESOURCE_ID_MISSING
    #define ELM_PEBBLE_RESOURCE_ID_MISSING UINT32_MAX
    #endif

    static ElmcPebbleApp *s_sequence_playback_app = NULL;

    static void elmc_sequence_track_app(ElmcPebbleApp *app) {
      if (app) {
        s_sequence_playback_app = app;
      }
    }

    static int64_t elmc_sequence_monotonic_ms(void) {
      time_t seconds = 0;
      uint16_t milliseconds = 0;
      time_ms(&seconds, &milliseconds);
      return ((int64_t)seconds * 1000) + milliseconds;
    }

    static bool elmc_sequence_play_loops(uint32_t play_count) {
      return play_count == 0 || play_count == PLAY_COUNT_INFINITE || play_count == 0xFFFF;
    }

    __attribute__((weak)) void elmc_pebble_schedule_layer_redraw(void) {
    }

    __attribute__((weak)) void elmc_pebble_after_worker_dispatch(void) {
    }
    #endif
    """
  end
end
