defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.TagCallbacks.StorageRandom do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body(Types.event_dispatch_bindings()) :: Types.c_source()
  def body(%{msg: _msg, random_generate_tag: _random_generate_tag}) do
    """
    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value) {
      (void)value;
      if (!app || !app->initialized) return -1;
      /* Storage string dispatch requires the Msg tag encoded in the cmd (cmd.p1). */
      return -6;
    }

    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value) {
      (void)value;
      if (!app || !app->initialized) return -1;
      /* Random.generate must encode the callback tag in the cmd (cmd.p0). */
      return -6;
    }
"""
  end
end
