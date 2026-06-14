defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.WindowWalk.WindowUnpack do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (!top_window || top_window->tag != ELMC_TAG_TUPLE2 || top_window->payload == NULL) return -5;

      ElmcTuple2 *window_tuple = (ElmcTuple2 *)top_window->payload;
      if (!window_tuple->first || !window_tuple->second) return -6;
      if (!elmc_is_virtual_ui_tag(window_tuple->first, ELMC_PEBBLE_UI_WINDOW_NODE)) return -7;

      if (window_tuple->second->tag != ELMC_TAG_TUPLE2 || window_tuple->second->payload == NULL) return -8;
      ElmcTuple2 *window_payload = (ElmcTuple2 *)window_tuple->second->payload;
      if (!window_payload->first || !window_payload->second) return -9;
      *out_window_id = elmc_as_int(window_payload->first);

    """
  end
end
