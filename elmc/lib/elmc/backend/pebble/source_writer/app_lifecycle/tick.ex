defmodule Elmc.Backend.Pebble.SourceWriter.AppLifecycle.Tick do
  @moduledoc false

  alias Elmc.Backend.Pebble.{MsgCodegen, Types}

  @spec body(Types.app_lifecycle_bindings()) :: Types.c_source()
  def body(%{msg: msg}) do
    """
    int elmc_pebble_tick(ElmcPebbleApp *app) {
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_TICK)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_TICK);
      if (tag <= 0) return -6;
    #{MsgCodegen.tick_dispatch_line(msg.tick_has_payload?)}
      return elmc_pebble_dispatch_int(app, tag);
    }
    """
  end
end
