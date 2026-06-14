defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.TagCallbacks.StorageRandom do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.event_dispatch_bindings()) :: Types.c_source()
  def body(%{msg: msg, random_generate_tag: random_generate_tag}) do
    """
    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value) {
      if (!app || !app->initialized) return -1;
      if (#{msg.storage_string_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_string(app, #{msg.storage_string_tag}, value ? value : "");
    }

    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value) {
      if (!app || !app->initialized) return -1;
      if (#{random_generate_tag} <= 0) return -6;
      return elmc_pebble_dispatch_tag_value(app, #{random_generate_tag}, value);
    }
"""
  end
end
