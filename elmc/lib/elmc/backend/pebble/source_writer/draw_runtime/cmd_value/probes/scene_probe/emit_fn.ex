defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes.SceneProbe.EmitFn do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        static void elmc_agent_scene_probe(uint32_t tag) {
          if (!elmc_agent_scene_probe_enabled(tag)) return;
          static uint32_t seen_tags[16];
          static int seen_count = 0;
          for (int i = 0; i < seen_count; i++) {
            if (seen_tags[i] == tag) return;
          }
          if (seen_count >= 16) return;
          DataLoggingSessionRef session =
              data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
          if (session) {
            seen_tags[seen_count++] = tag;
            data_logging_finish(session);
          }
        }
        #else
        #define elmc_agent_scene_probe(tag) do { (void)(tag); } while (0)
        #endif

"""
  end
end
