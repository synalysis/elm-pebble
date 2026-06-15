defmodule Elmc.Backend.Pebble.SourceWriter.AppLifecycle.Runtime do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app) {
      if (!app || !app->initialized) return 0;
      return elmc_worker_subscriptions(&app->worker);
    }

    int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app) {
      if (!app || !app->initialized) return 0;
      ElmcValue *model = elmc_worker_model(&app->worker);
      if (!model) return 0;
      int64_t value = 0;
      if (model->tag == ELMC_TAG_TUPLE2 && model->payload != NULL) {
        ElmcTuple2 *tuple = (ElmcTuple2 *)model->payload;
        if (tuple->first) {
          value = elmc_as_int(tuple->first);
        }
      } else {
        value = elmc_as_int(model);
      }
      elmc_release(model);
      return value;
    }

    int elmc_pebble_run_mode(ElmcPebbleApp *app) {
      if (!app) return ELMC_PEBBLE_MODE_APP;
      return app->run_mode;
    }
    """
  end
end
