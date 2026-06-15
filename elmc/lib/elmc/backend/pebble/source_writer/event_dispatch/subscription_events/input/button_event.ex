defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input.ButtonEvent do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        static elmc_int_t elmc_pebble_button_event(int32_t pressed) {
          return pressed ? ELMC_BUTTON_EVENT_PRESSED : ELMC_BUTTON_EVENT_RELEASED;
        }

    """
  end
end
