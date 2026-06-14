defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.WindowWalk.Prologue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_extract_virtual_canvas_ops(
        ElmcValue *view,
        int64_t *out_window_id,
        int64_t *out_layer_id,
        ElmcValue **out_ops) {
      if (!view || !out_window_id || !out_layer_id || !out_ops) return -1;
      *out_window_id = 0;
      *out_layer_id = 0;
      *out_ops = NULL;

      if (view->tag != ELMC_TAG_TUPLE2 || view->payload == NULL) return -2;
      ElmcTuple2 *root = (ElmcTuple2 *)view->payload;
      if (!root->first || !root->second) return -3;
      if (!elmc_is_virtual_ui_tag(root->first, ELMC_PEBBLE_UI_WINDOW_STACK)) return -4;

    """
  end
end
