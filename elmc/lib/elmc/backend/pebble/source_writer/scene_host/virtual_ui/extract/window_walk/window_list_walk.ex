defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.WindowWalk.WindowListWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      ElmcValue *window_cursor = root->second;
      ElmcValue *top_window = NULL;
      int64_t seen_window_ids[16] = {0};
      int seen_window_count = 0;
      while (window_cursor && window_cursor->tag == ELMC_TAG_LIST && window_cursor->payload != NULL) {
        ElmcCons *window_node = (ElmcCons *)window_cursor->payload;
        if (window_node->head && window_node->head->tag == ELMC_TAG_TUPLE2 && window_node->head->payload != NULL) {
          ElmcTuple2 *candidate_tuple = (ElmcTuple2 *)window_node->head->payload;
          if (candidate_tuple->first && candidate_tuple->second &&
              elmc_is_virtual_ui_tag(candidate_tuple->first, ELMC_PEBBLE_UI_WINDOW_NODE) &&
              candidate_tuple->second->tag == ELMC_TAG_TUPLE2 &&
              candidate_tuple->second->payload != NULL) {
            ElmcTuple2 *candidate_payload = (ElmcTuple2 *)candidate_tuple->second->payload;
            if (candidate_payload->first) {
              int64_t candidate_id = elmc_as_int(candidate_payload->first);
              for (int i = 0; i < seen_window_count; i++) {
                if (seen_window_ids[i] == candidate_id) return -30;
              }
              if (seen_window_count < 16) seen_window_ids[seen_window_count++] = candidate_id;
            }
          }
        }
        top_window = window_node->head;
        window_cursor = window_node->tail;
      }

    """
  end
end
