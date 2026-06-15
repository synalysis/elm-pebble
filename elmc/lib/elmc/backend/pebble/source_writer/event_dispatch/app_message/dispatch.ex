defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.AppMessage.Dispatch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value) {
      int64_t tag = 0;
      int rc = elmc_pebble_msg_from_appmessage(key, value, &tag);
      if (rc != 0) return rc;
      return elmc_pebble_dispatch_int(app, tag);
    }

"""
  end
end
