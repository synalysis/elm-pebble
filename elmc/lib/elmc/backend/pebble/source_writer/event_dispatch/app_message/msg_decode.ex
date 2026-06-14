defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.AppMessage.MsgDecode do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.event_dispatch_bindings()) :: Types.c_source()
  def body(%{msg: msg}) do
    """
    int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag) {
      if (!out_tag) return -1;

      if (key == 0) {
        switch (value) {
    #{msg.value_decode_cases}
          default: return -3;
        }
      }

      if (value == 0) return -4;
      switch (key) {
    #{msg.key_decode_cases}
        default: return -3;
      }
    }

"""
  end
end
