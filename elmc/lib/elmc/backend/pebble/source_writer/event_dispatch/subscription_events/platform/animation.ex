defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Animation do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_animation_finished(ElmcPebbleApp *app, int animation_id) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ANIMATION_FINISHED)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ANIMATION_FINISHED);
      if (tag <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, tag, animation_id);
    }

"""
  end
end
