defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes.SceneProbe.EnabledFn do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        // #region agent log
        #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_AGENT_PROBES && !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
        static bool elmc_agent_scene_probe_enabled(uint32_t tag) {
          return tag == 0xED997A00 ||
                 tag == 0xED997C02 ||
                 tag == 0xED996191 ||
                 tag == 0xED996211 ||
                 tag == 0xED996213 ||
                 tag == 0xED996300 ||
                 tag == 0xED9963F0 ||
                 tag == 0xED996410 ||
                 tag == 0xED996411 ||
                 tag == 0xED996412 ||
                 tag == 0xED996413 ||
                 tag == 0xED996500 ||
                 tag == 0xED996501 ||
                 (tag & 0xFFFFFF00) == 0xED997000 ||
                 (tag & 0xFFFFFF00) == 0xED997100 ||
                 (tag & 0xFFFFFF00) == 0xED997B00 ||
                 (tag & 0xFFFFFF00) == 0xED997D00 ||
                 (tag & 0xFFFFFF00) == 0xED997E00 ||
                 (tag & 0xFFFFFF00) == 0xED997F00 ||
                 (tag & 0xFFFFFF00) == 0xED998000 ||
                 (tag & 0xFFFFFF00) == 0xED998100;
        }
"""
  end
end
