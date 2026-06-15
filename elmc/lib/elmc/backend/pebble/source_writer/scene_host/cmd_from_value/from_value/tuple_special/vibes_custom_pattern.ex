defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial.VibesCustomPattern do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN
        if (out_cmd->kind == ELMC_PEBBLE_CMD_VIBES_CUSTOM_PATTERN) {
          int32_t count = 0;
          if (elmc_serialize_int_list(tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
          out_cmd->p0 = count;
          return 0;
        }
    #endif

    """
  end
end
