defmodule Elmc.Backend.Pebble.WatchInfoMap do
  @moduledoc false

  # SDK `WatchInfoColor` / `WatchInfoModel` enumerators → Elm constructor names
  # in `Pebble.WatchInfo`. Integer values are not sequential (Pebble 2 colors
  # have gaps), so the host must map by enumerator, not `color + 1`.

  @colors [
    {"UnknownColor", "WATCH_INFO_COLOR_UNKNOWN"},
    {"Black", "WATCH_INFO_COLOR_BLACK"},
    {"White", "WATCH_INFO_COLOR_WHITE"},
    {"Red", "WATCH_INFO_COLOR_RED"},
    {"Orange", "WATCH_INFO_COLOR_ORANGE"},
    {"Gray", "WATCH_INFO_COLOR_GRAY"},
    {"StainlessSteel", "WATCH_INFO_COLOR_STAINLESS_STEEL"},
    {"MatteBlack", "WATCH_INFO_COLOR_MATTE_BLACK"},
    {"Blue", "WATCH_INFO_COLOR_BLUE"},
    {"Green", "WATCH_INFO_COLOR_GREEN"},
    {"Pink", "WATCH_INFO_COLOR_PINK"},
    {"TimeWhite", "WATCH_INFO_COLOR_TIME_WHITE"},
    {"TimeBlack", "WATCH_INFO_COLOR_TIME_BLACK"},
    {"TimeRed", "WATCH_INFO_COLOR_TIME_RED"},
    {"TimeSteelSilver", "WATCH_INFO_COLOR_TIME_STEEL_SILVER"},
    {"TimeSteelBlack", "WATCH_INFO_COLOR_TIME_STEEL_BLACK"},
    {"TimeSteelGold", "WATCH_INFO_COLOR_TIME_STEEL_GOLD"},
    {"TimeRoundSilver14", "WATCH_INFO_COLOR_TIME_ROUND_SILVER_14"},
    {"TimeRoundBlack14", "WATCH_INFO_COLOR_TIME_ROUND_BLACK_14"},
    {"TimeRoundSilver20", "WATCH_INFO_COLOR_TIME_ROUND_SILVER_20"},
    {"TimeRoundBlack20", "WATCH_INFO_COLOR_TIME_ROUND_BLACK_20"},
    {"TimeRoundRoseGold14", "WATCH_INFO_COLOR_TIME_ROUND_ROSE_GOLD_14"},
    {"Pebble2HrBlack", "WATCH_INFO_COLOR_PEBBLE_2_HR_BLACK"},
    {"Pebble2HrLime", "WATCH_INFO_COLOR_PEBBLE_2_HR_LIME"},
    {"Pebble2HrFlame", "WATCH_INFO_COLOR_PEBBLE_2_HR_FLAME"},
    {"Pebble2HrWhite", "WATCH_INFO_COLOR_PEBBLE_2_HR_WHITE"},
    {"Pebble2HrAqua", "WATCH_INFO_COLOR_PEBBLE_2_HR_AQUA"},
    {"Pebble2SeBlack", "WATCH_INFO_COLOR_PEBBLE_2_SE_BLACK"},
    {"Pebble2SeWhite", "WATCH_INFO_COLOR_PEBBLE_2_SE_WHITE"},
    {"PebbleTime2Black", "WATCH_INFO_COLOR_PEBBLE_TIME_2_BLACK"},
    {"PebbleTime2Silver", "WATCH_INFO_COLOR_PEBBLE_TIME_2_SILVER"},
    {"PebbleTime2Gold", "WATCH_INFO_COLOR_PEBBLE_TIME_2_GOLD"},
    {"CoreDevicesP2DBlack", "WATCH_INFO_COLOR_COREDEVICES_P2D_BLACK"},
    {"CoreDevicesP2DWhite", "WATCH_INFO_COLOR_COREDEVICES_P2D_WHITE"},
    {"CoreDevicesPT2BlackGrey", "WATCH_INFO_COLOR_COREDEVICES_PT2_BLACK_GREY"},
    {"CoreDevicesPT2BlackRed", "WATCH_INFO_COLOR_COREDEVICES_PT2_BLACK_RED"},
    {"CoreDevicesPT2SilverBlue", "WATCH_INFO_COLOR_COREDEVICES_PT2_SILVER_BLUE"},
    {"CoreDevicesPT2SilverGrey", "WATCH_INFO_COLOR_COREDEVICES_PT2_SILVER_GREY"},
    {"CoreDevicesPR2Black20", "WATCH_INFO_COLOR_COREDEVICES_PR2_BLACK_20"},
    {"CoreDevicesPR2Silver20", "WATCH_INFO_COLOR_COREDEVICES_PR2_SILVER_20"},
    {"CoreDevicesPR2Gold14", "WATCH_INFO_COLOR_COREDEVICES_PR2_GOLD_14"},
    {"CoreDevicesPR2Silver14", "WATCH_INFO_COLOR_COREDEVICES_PR2_SILVER_14"}
  ]

  @models [
    {"UnknownModel", "WATCH_INFO_MODEL_UNKNOWN"},
    {"PebbleOriginal", "WATCH_INFO_MODEL_PEBBLE_ORIGINAL"},
    {"PebbleSteel", "WATCH_INFO_MODEL_PEBBLE_STEEL"},
    {"PebbleTime", "WATCH_INFO_MODEL_PEBBLE_TIME"},
    {"PebbleTimeSteel", "WATCH_INFO_MODEL_PEBBLE_TIME_STEEL"},
    {"PebbleTimeRound14", "WATCH_INFO_MODEL_PEBBLE_TIME_ROUND_14"},
    {"PebbleTimeRound20", "WATCH_INFO_MODEL_PEBBLE_TIME_ROUND_20"},
    {"Pebble2Hr", "WATCH_INFO_MODEL_PEBBLE_2_HR"},
    {"Pebble2Se", "WATCH_INFO_MODEL_PEBBLE_2_SE"},
    {"PebbleTime2", "WATCH_INFO_MODEL_PEBBLE_TIME_2"},
    {"CoreDevicesP2D", "WATCH_INFO_MODEL_COREDEVICES_P2D"},
    {"CoreDevicesPT2", "WATCH_INFO_MODEL_COREDEVICES_PT2"},
    {"CoreDevicesPR2", "WATCH_INFO_MODEL_COREDEVICES_PR2"}
  ]

  @spec colors() :: [{String.t(), String.t()}]
  def colors, do: @colors

  @spec models() :: [{String.t(), String.t()}]
  def models, do: @models
end
