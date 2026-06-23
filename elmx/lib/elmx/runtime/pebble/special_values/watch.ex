defmodule Elmx.Runtime.Pebble.SpecialValues.Watch do
  @moduledoc false

  @behaviour Elmx.Runtime.Pebble.SpecialValues.Dispatcher

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "Pebble.Health.supported" -> kernel_watch("healthSupported", args)
      "Pebble.Health.value" -> kernel_watch("healthValue", args)
      "Pebble.Health.sumToday" -> kernel_watch("healthSumToday", args)
      "Pebble.Health.sum" -> kernel_watch("healthSum", args)
      "Pebble.Health.accessible" -> kernel_watch("healthAccessible", args)
      "Pebble.Compass.current" -> ui_call("elmx_compass_peek", args)
      "Pebble.Time.Monday" -> {:ok, %{op: :int_literal, value: 0}}
      "Pebble.Time.Tuesday" -> {:ok, %{op: :int_literal, value: 1}}
      "Pebble.Time.Wednesday" -> {:ok, %{op: :int_literal, value: 2}}
      "Pebble.Time.Thursday" -> {:ok, %{op: :int_literal, value: 3}}
      "Pebble.Time.Friday" -> {:ok, %{op: :int_literal, value: 4}}
      "Pebble.Time.Saturday" -> {:ok, %{op: :int_literal, value: 5}}
      "Pebble.Time.Sunday" -> {:ok, %{op: :int_literal, value: 6}}
      "Pebble.Time.currentDateTime" -> ui_call("elmx_time_current_date_time", args)
      "Pebble.Time.currentTimeString" -> ui_call("elmx_time_current_time_string", args)
      "Pebble.Time.clockStyle24h" -> ui_call("elmx_time_clock_style_24h", args)
      "Pebble.Time.timezoneIsSet" -> ui_call("elmx_time_timezone_is_set", args)
      "Pebble.Time.timezone" -> ui_call("elmx_time_timezone", args)
      "Pebble.WatchInfo.getModel" -> ui_call("elmx_watch_info_get_model", args)
      "Pebble.WatchInfo.getColor" -> ui_call("elmx_watch_info_get_color", args)
      "Pebble.WatchInfo.getFirmwareVersion" -> ui_call("elmx_watch_info_get_firmware_version", args)
      "Pebble.System.batteryLevel" -> ui_call("elmx_system_battery_level", args)
      "Pebble.System.connectionStatus" -> ui_call("elmx_system_connection_status", args)
      "Pebble.Events.batch" -> subscription_batch(args)
      "Elm.Kernel.PebbleWatch.batch" -> subscription_batch(args)
      "Pebble.Events.onSecondChange" -> subscription_mask("Pebble.Events.onSecondChange")
      "Elm.Kernel.PebbleWatch.onSecondChange" -> subscription_mask("Elm.Kernel.PebbleWatch.onSecondChange")
      "Pebble.Events.onHourChange" -> subscription_mask("Pebble.Events.onHourChange")
      "Elm.Kernel.PebbleWatch.onHourChange" -> subscription_mask("Elm.Kernel.PebbleWatch.onHourChange")
      "Pebble.Events.onMinuteChange" -> subscription_mask("Pebble.Events.onMinuteChange")
      "Elm.Kernel.PebbleWatch.onMinuteChange" -> subscription_mask("Elm.Kernel.PebbleWatch.onMinuteChange")
      "Pebble.Events.onDayChange" -> subscription_mask("Pebble.Events.onDayChange")
      "Elm.Kernel.PebbleWatch.onDayChange" -> subscription_mask("Elm.Kernel.PebbleWatch.onDayChange")
      "Pebble.Events.onMonthChange" -> subscription_mask("Pebble.Events.onMonthChange")
      "Elm.Kernel.PebbleWatch.onMonthChange" -> subscription_mask("Elm.Kernel.PebbleWatch.onMonthChange")
      "Pebble.Events.onYearChange" -> subscription_mask("Pebble.Events.onYearChange")
      "Elm.Kernel.PebbleWatch.onYearChange" -> subscription_mask("Elm.Kernel.PebbleWatch.onYearChange")
      "Pebble.Events.onAnimationFinished" -> subscription_mask("Pebble.Events.onAnimationFinished")
      "Elm.Kernel.PebbleWatch.onAnimationFinished" -> subscription_mask("Elm.Kernel.PebbleWatch.onAnimationFinished")
      "Pebble.Button.on" -> subscription_mask("Pebble.Button.on")
      "Pebble.Button.onPress" -> subscription_mask("Pebble.Button.onPress")
      "Pebble.Button.onLongPress" -> subscription_mask("Pebble.Button.onLongPress")
      "Pebble.Accel.onTap" -> subscription_mask("Pebble.Accel.onTap")
      "Elm.Kernel.PebbleWatch.onAccelTap" -> subscription_mask("Elm.Kernel.PebbleWatch.onAccelTap")
      "Pebble.Frame.every" -> frame_subscription(args)
      "Elm.Kernel.PebbleWatch.onFrame" -> frame_subscription(args)
      "Pebble.Frame.atFps" -> frame_fps_subscription(args)
      "Pebble.Cmd.getClockStyle24h" -> ui_call("elmx_time_clock_style_24h", args)
      "Pebble.Cmd.getTimezoneIsSet" -> ui_call("elmx_time_timezone_is_set", args)
      "Pebble.Cmd.getTimezone" -> ui_call("elmx_time_timezone", args)
      "Pebble.Cmd.getWatchModel" -> ui_call("elmx_watch_info_get_model", args)
      "Pebble.Cmd.getFirmwareVersion" -> ui_call("elmx_watch_info_get_firmware_version", args)
      "Pebble.Cmd.getCurrentTimeString" -> ui_call("elmx_time_current_time_string", args)
      "Pebble.Cmd.getCurrentDateTime" -> ui_call("elmx_time_current_date_time", args)
      "Elm.Kernel.PebbleWatch.getCurrentTimeString" -> ui_call("elmx_time_current_time_string", args)
      "Elm.Kernel.PebbleWatch.getCurrentDateTime" -> ui_call("elmx_time_current_date_time", args)
      "Pebble.Cmd.timerAfter" -> ui_call("elmx_cmd_timer_after", args)
      "Pebble.Storage.readInt" -> ui_call("elmx_storage_read_int", args)
      "Pebble.Storage.readString" -> ui_call("elmx_storage_read_string", args)
      "Pebble.Cmd.storageReadString" -> ui_call("elmx_storage_read_string", args)
      "Elm.Kernel.PebbleWatch.storageReadString" -> ui_call("elmx_storage_read_string", args)
      "Pebble.Storage.writeInt" -> ui_call("elmx_storage_write_int", args)
      "Pebble.Storage.writeString" -> ui_call("elmx_storage_write_string", args)
      "Pebble.Storage.delete" -> ui_call("elmx_storage_delete", args)
      "Elm.Kernel.PebbleWatch.timerAfter" -> ui_call("elmx_cmd_timer_after", args)
      "Elm.Kernel.PebbleWatch.storageWriteString" -> ui_call("elmx_storage_write_string", args)
      "Elm.Kernel.PebbleWatch.storageWriteInt" -> ui_call("elmx_storage_write_int", args)
      "Elm.Kernel.PebbleWatch.storageReadInt" -> ui_call("elmx_storage_read_int", args)
      "Elm.Kernel.PebbleWatch.storageDelete" -> ui_call("elmx_storage_delete", args)
      "Pebble.Game.Math.clamp" -> math_clamp(args)
      "Pebble.Vibes.shortPulse" -> ui_call("elmx_vibes_short_pulse", args)
      "Pebble.Vibes.longPulse" -> ui_call("elmx_vibes_long_pulse", args)
      "Pebble.Vibes.doublePulse" -> ui_call("elmx_vibes_double_pulse", args)
      "Pebble.Vibes.pattern" -> ui_call("elmx_vibes_pattern", args)
      "Pebble.Vibes.cancel" -> ui_call("elmx_vibes_cancel", args)
      "Pebble.Cmd.vibesShortPulse" -> ui_call("elmx_vibes_short_pulse", args)
      "Pebble.Cmd.vibesLongPulse" -> ui_call("elmx_vibes_long_pulse", args)
      "Pebble.Cmd.vibesDoublePulse" -> ui_call("elmx_vibes_double_pulse", args)
      "Pebble.Cmd.vibesCancel" -> ui_call("elmx_vibes_cancel", args)
      "Pebble.Button.onRelease" -> subscription_mask("Pebble.Button.onRelease")
      "Pebble.Light.enable" -> ui_call("elmx_light_enable", args)
      "Pebble.Light.disable" -> ui_call("elmx_light_disable", args)
      "Pebble.Light.interaction" -> ui_call("elmx_light_interaction", args)
      "Pebble.Game.Collision.rectRect" -> ui_call("elmx_collision_rect_rect", args)
      "Pebble.Cmd.storageWriteInt" -> ui_call("elmx_storage_write_int", args)
      "Pebble.Cmd.storageReadInt" -> ui_call("elmx_storage_read_int", args)
      "Pebble.Cmd.storageWriteString" -> ui_call("elmx_storage_write_string", args)
      "Pebble.Cmd.storageDelete" -> ui_call("elmx_storage_delete", args)
      "Pebble.Cmd.backlight" -> ui_call("elmx_cmd_backlight", args)
      "Elm.Kernel.PebbleWatch.backlight" -> ui_call("elmx_cmd_backlight", args)
      "Pebble.Accel.onData" -> subscription_mask("Pebble.Accel.onData")
      "Pebble.System.onBatteryChange" -> subscription_mask("Pebble.System.onBatteryChange")
      "Pebble.System.onConnectionChange" -> subscription_mask("Pebble.System.onConnectionChange")
      "Pebble.Health.onEvent" -> subscription_mask("Pebble.Health.onEvent")
      "Pebble.AppFocus.onChange" -> subscription_mask("Pebble.AppFocus.onChange")
      "Pebble.Compass.onChange" -> subscription_mask("Pebble.Compass.onChange")
      "Pebble.Dictation.start" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_start", args: []}}
      "Pebble.Dictation.stop" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_stop", args: []}}
      "Elm.Kernel.PebbleWatch.dictationStart" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_start", args: []}}
      "Elm.Kernel.PebbleWatch.dictationStop" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_stop", args: []}}
      "Pebble.DataLog.tag" -> data_log_tag(args)
      "Pebble.DataLog.logBytes" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_bytes", args: args}}
      "Pebble.DataLog.logInt32" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_int32", args: args}}
      "Elm.Kernel.PebbleWatch.dataLogBytes" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_bytes", args: args}}
      "Elm.Kernel.PebbleWatch.dataLogInt32" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_int32", args: args}}
      "Pebble.Dictation.onStatus" -> subscription_mask("Pebble.Dictation.onStatus")
      "Pebble.Dictation.onResult" -> subscription_mask("Pebble.Dictation.onResult")
      "Pebble.UnobstructedArea.onWillChange" -> subscription_mask("Pebble.UnobstructedArea.onWillChange")
      "Pebble.UnobstructedArea.onChanging" -> subscription_mask("Pebble.UnobstructedArea.onChanging")
      "Pebble.UnobstructedArea.onDidChange" -> subscription_mask("Pebble.UnobstructedArea.onDidChange")
      "Pebble.UnobstructedArea.currentBounds" -> ui_call("elmx_unobstructed_current_bounds", args)
      "Elm.Kernel.PebbleWatch.unobstructedCurrentBounds" -> ui_call("elmx_unobstructed_current_bounds", args)
      "Pebble.Internal.Companion.companionSend" -> ui_call("elmx_companion_send", args)
      "Elm.Kernel.PebbleWatch.companionSend" -> ui_call("elmx_companion_send", args)
      _ -> :unmatched
    end
  end
end
