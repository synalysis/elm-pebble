defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.SubHelpers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_is_subscribed(ElmcPebbleApp *app, int64_t flag) {
      if (!app || !app->initialized) return 0;
      int64_t active = elmc_worker_subscriptions(&app->worker);
      return (active & flag) != 0;
    }

    static elmc_int_t elmc_pebble_sub_tag(ElmcPebbleApp *app, int64_t flag) {
      return elmc_worker_sub_msg_tag(&app->worker, flag);
    }
"""
  end
end
