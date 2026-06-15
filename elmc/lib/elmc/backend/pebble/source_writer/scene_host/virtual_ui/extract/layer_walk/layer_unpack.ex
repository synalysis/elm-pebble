defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.LayerWalk.LayerUnpack do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (!top_layer || top_layer->tag != ELMC_TAG_TUPLE2 || top_layer->payload == NULL) return -10;

      ElmcTuple2 *layer_tuple = (ElmcTuple2 *)top_layer->payload;
      if (!layer_tuple->first || !layer_tuple->second) return -11;
      if (!elmc_is_virtual_ui_tag(layer_tuple->first, ELMC_PEBBLE_UI_CANVAS_LAYER)) return -12;

      if (layer_tuple->second->tag != ELMC_TAG_TUPLE2 || layer_tuple->second->payload == NULL) return -13;
      ElmcTuple2 *layer_payload = (ElmcTuple2 *)layer_tuple->second->payload;
      if (!layer_payload->first || !layer_payload->second) return -14;

    """
  end
end
