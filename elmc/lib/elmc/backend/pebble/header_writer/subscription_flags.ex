defmodule Elmc.Backend.Pebble.HeaderWriter.SubscriptionFlags do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #define ELMC_PEBBLE_SUB_TICK (1 << 0)
    #define ELMC_PEBBLE_SUB_BUTTON_UP (1 << 1)
    #define ELMC_PEBBLE_SUB_BUTTON_SELECT (1 << 2)
    #define ELMC_PEBBLE_SUB_BUTTON_DOWN (1 << 3)
    #define ELMC_PEBBLE_SUB_ACCEL_TAP (1 << 4)
    #define ELMC_PEBBLE_SUB_BATTERY (1 << 5)
    #define ELMC_PEBBLE_SUB_CONNECTION (1 << 6)
    #define ELMC_PEBBLE_SUB_HOUR (1 << 10)
    #define ELMC_PEBBLE_SUB_MINUTE (1 << 11)
    #define ELMC_PEBBLE_SUB_APPMESSAGE (1 << 12)
    #define ELMC_PEBBLE_SUB_FRAME (1 << 13)
    #define ELMC_PEBBLE_SUB_BUTTON_RAW (1 << 14)
    #define ELMC_PEBBLE_SUB_ACCEL_DATA (1 << 15)
    #define ELMC_PEBBLE_SUB_DAY (1 << 16)
    #define ELMC_PEBBLE_SUB_MONTH (1 << 17)
    #define ELMC_PEBBLE_SUB_YEAR (1 << 18)
    #define ELMC_PEBBLE_SUB_APP_FOCUS (1 << 19)
    #define ELMC_PEBBLE_SUB_COMPASS (1 << 20)
    #define ELMC_PEBBLE_SUB_DICTATION (1 << 21)
    #define ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA (1 << 22)
    #define ELMC_PEBBLE_SUB_ANIMATION_FINISHED (1 << 23)
    #define ELMC_PEBBLE_SUB_HEALTH (1LL << 31)
"""
  end
end
