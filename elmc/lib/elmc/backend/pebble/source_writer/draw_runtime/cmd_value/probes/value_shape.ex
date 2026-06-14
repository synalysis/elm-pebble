defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Probes.ValueShape do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
        static uint32_t elmc_agent_value_shape(ElmcValue *value) {
          if (!value) return 0x0;
          switch (value->tag) {
            case ELMC_TAG_INT: return 0x1;
            case ELMC_TAG_BOOL: return 0x2;
            case ELMC_TAG_STRING: return 0x3;
            case ELMC_TAG_LIST: return value->payload ? 0x41 : 0x40;
            case ELMC_TAG_RESULT: return 0x5;
            case ELMC_TAG_MAYBE: return 0x6;
            case ELMC_TAG_TUPLE2: return value->payload ? 0x71 : 0x70;
            case ELMC_TAG_PORT_PAYLOAD: return 0x9;
            case ELMC_TAG_FLOAT: return 0xA;
            default: return 0xF;
          }
        }
    #endif

        // #endregion

    """
  end
end
