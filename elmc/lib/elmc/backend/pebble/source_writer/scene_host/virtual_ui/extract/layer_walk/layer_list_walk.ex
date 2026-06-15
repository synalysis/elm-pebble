defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.LayerWalk.LayerListWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      ElmcValue *layer_cursor = window_payload->second;
      ElmcValue *top_layer = NULL;
      int64_t seen_layer_ids[32] = {0};
      int seen_layer_count = 0;
      while (layer_cursor && layer_cursor->tag == ELMC_TAG_LIST && layer_cursor->payload != NULL) {
        ElmcCons *layer_node = (ElmcCons *)layer_cursor->payload;
        if (layer_node->head && layer_node->head->tag == ELMC_TAG_TUPLE2 && layer_node->head->payload != NULL) {
          ElmcTuple2 *candidate_tuple = (ElmcTuple2 *)layer_node->head->payload;
          if (candidate_tuple->first && candidate_tuple->second &&
              elmc_is_virtual_ui_tag(candidate_tuple->first, ELMC_PEBBLE_UI_CANVAS_LAYER) &&
              candidate_tuple->second->tag == ELMC_TAG_TUPLE2 &&
              candidate_tuple->second->payload != NULL) {
            ElmcTuple2 *candidate_payload = (ElmcTuple2 *)candidate_tuple->second->payload;
            if (candidate_payload->first) {
              int64_t candidate_id = elmc_as_int(candidate_payload->first);
              for (int i = 0; i < seen_layer_count; i++) {
                if (seen_layer_ids[i] == candidate_id) return -31;
              }
              if (seen_layer_count < 32) seen_layer_ids[seen_layer_count++] = candidate_id;
            }
          }
        }
        top_layer = layer_node->head;
        layer_cursor = layer_node->tail;
      }

    """
  end
end
