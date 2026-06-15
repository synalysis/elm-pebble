defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.LayerWalk.Finish do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      // #region agent log
      elmc_agent_scene_probe(0xED996600 | elmc_agent_value_shape(layer_payload->first));
      elmc_agent_scene_probe(0xED996700 | elmc_agent_value_shape(layer_payload->second));
      if (layer_payload->second->tag == ELMC_TAG_TUPLE2 && layer_payload->second->payload != NULL) {
        ElmcTuple2 *ops_payload = (ElmcTuple2 *)layer_payload->second->payload;
        elmc_agent_scene_probe(0xED996800 | elmc_agent_value_shape(ops_payload->first));
        elmc_agent_scene_probe(0xED996900 | elmc_agent_value_shape(ops_payload->second));
      }
      // #endregion

      *out_layer_id = elmc_as_int(layer_payload->first);
      *out_ops = layer_payload->second;
      return 0;
    }
    """
  end
end
