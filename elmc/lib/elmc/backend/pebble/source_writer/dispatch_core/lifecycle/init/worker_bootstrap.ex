defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.WorkerBootstrap do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      elmc_pebble_heap_log("init:before");
      int rc = elmc_worker_init(&app->worker, flags);
      if (rc == 0) app->initialized = 1;
      elmc_pebble_heap_log("init:after");
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_init_with_mode", rc);
    }

    """
  end
end
