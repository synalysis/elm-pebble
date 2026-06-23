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
      "Pebble.Events.onSecondChange" -> subscription_register_call("Pebble.Events.onSecondChange", args)
      "Elm.Kernel.PebbleWatch.onSecondChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onSecondChange", args)

      "Pebble.Events.onHourChange" -> subscription_register_call("Pebble.Events.onHourChange", args)
      "Elm.Kernel.PebbleWatch.onHourChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onHourChange", args)

      "Pebble.Events.onMinuteChange" -> subscription_register_call("Pebble.Events.onMinuteChange", args)
      "Elm.Kernel.PebbleWatch.onMinuteChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onMinuteChange", args)

      "Pebble.Events.onDayChange" -> subscription_register_call("Pebble.Events.onDayChange", args)
      "Elm.Kernel.PebbleWatch.onDayChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onDayChange", args)

      "Pebble.Events.onMonthChange" -> subscription_register_call("Pebble.Events.onMonthChange", args)
      "Elm.Kernel.PebbleWatch.onMonthChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onMonthChange", args)

      "Pebble.Events.onYearChange" -> subscription_register_call("Pebble.Events.onYearChange", args)
      "Elm.Kernel.PebbleWatch.onYearChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onYearChange", args)

      "Pebble.Events.onAnimationFinished" ->
        subscription_register_call("Pebble.Events.onAnimationFinished", args)

      "Elm.Kernel.PebbleWatch.onAnimationFinished" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onAnimationFinished", args)

      "Pebble.Button.on" -> subscription_register_call("Pebble.Button.on", args)
      "Pebble.Button.onPress" -> subscription_register_call("Pebble.Button.onPress", args)
      "Pebble.Button.onLongPress" -> subscription_register_call("Pebble.Button.onLongPress", args)
      "Pebble.Accel.onTap" -> subscription_register_call("Pebble.Accel.onTap", args)

      "Elm.Kernel.PebbleWatch.onAccelTap" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onAccelTap", args)

      "Pebble.Frame.every" -> frame_subscription_register(args)
      "Elm.Kernel.PebbleWatch.onFrame" -> frame_subscription_register(args)
      "Pebble.Frame.atFps" -> frame_fps_subscription_register(args)
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
      "Pebble.Storage.maxSize" -> ui_call("elmx_storage_read_max_size", args)
      "Pebble.Wakeup.scheduleAfterSeconds" -> {:ok, %{op: :cmd_none}}
      "Pebble.Wakeup.cancel" -> {:ok, %{op: :cmd_none}}
      "Pebble.Log.infoCode" -> {:ok, %{op: :cmd_none}}
      "Pebble.Log.warnCode" -> {:ok, %{op: :cmd_none}}
      "Pebble.Log.errorCode" -> {:ok, %{op: :cmd_none}}
      "Elm.Kernel.PebbleWatch.storageReadMaxSize" -> ui_call("elmx_storage_read_max_size", args)
      "Pebble.Speaker.isMuted" -> ui_call("elmx_kernel_pebble_watch_speaker_is_muted", args)
      "Elm.Kernel.PebbleWatch.speakerIsMuted" -> ui_call("elmx_kernel_pebble_watch_speaker_is_muted", args)
      "Pebble.Speaker.playTone" -> ui_call("elmx_speaker_play_tone", args)
      "Elm.Kernel.PebbleWatch.speakerPlayTone" -> ui_call("elmx_speaker_play_tone", args)
      "Pebble.Speaker.playNotes" -> ui_call("elmx_speaker_play_notes", args)
      "Elm.Kernel.PebbleWatch.speakerPlayNotes" -> ui_call("elmx_speaker_play_notes", args)
      "Pebble.Speaker.playTracks" -> ui_call("elmx_speaker_play_tracks", args)
      "Elm.Kernel.PebbleWatch.speakerPlayTracks" -> ui_call("elmx_speaker_play_tracks", args)
      "Pebble.Speaker.stop" -> ui_call("elmx_speaker_stop", args)
      "Elm.Kernel.PebbleWatch.speakerStop" -> ui_call("elmx_speaker_stop", args)
      "Pebble.Speaker.setVolume" -> ui_call("elmx_speaker_set_volume", args)
      "Elm.Kernel.PebbleWatch.speakerSetVolume" -> ui_call("elmx_speaker_set_volume", args)
      "Pebble.Speaker.status" -> ui_call("elmx_kernel_pebble_watch_speaker_get_status", args)
      "Elm.Kernel.PebbleWatch.speakerGetStatus" -> ui_call("elmx_kernel_pebble_watch_speaker_get_status", args)
      "Pebble.Speaker.streamOpen" -> ui_call("elmx_speaker_stream_open", args)
      "Elm.Kernel.PebbleWatch.speakerStreamOpen" -> ui_call("elmx_speaker_stream_open", args)
      "Pebble.Speaker.streamWrite" -> ui_call("elmx_speaker_stream_write", args)
      "Elm.Kernel.PebbleWatch.speakerStreamWrite" -> ui_call("elmx_speaker_stream_write", args)
      "Pebble.Speaker.streamClose" -> ui_call("elmx_speaker_stream_close", args)
      "Elm.Kernel.PebbleWatch.speakerStreamClose" -> ui_call("elmx_speaker_stream_close", args)
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
      "Pebble.Button.onRelease" -> subscription_register_call("Pebble.Button.onRelease", args)
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
      "Pebble.Accel.onData" -> subscription_register_call("Pebble.Accel.onData", args)
      "Pebble.System.onBatteryChange" -> subscription_register_call("Pebble.System.onBatteryChange", args)
      "Pebble.System.onConnectionChange" -> subscription_register_call("Pebble.System.onConnectionChange", args)
      "Pebble.Health.onEvent" -> subscription_register_call("Pebble.Health.onEvent", args)
      "Pebble.AppFocus.onChange" -> subscription_register_call("Pebble.AppFocus.onChange", args)

      "Elm.Kernel.PebbleWatch.onAppFocusChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onAppFocusChange", args)

      "Pebble.Light.onChange" -> subscription_register_call("Pebble.Light.onChange", args)

      "Elm.Kernel.PebbleWatch.onBacklightChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onBacklightChange", args)

      "Pebble.Platform.onScreenChange" -> subscription_register_call("Pebble.Platform.onScreenChange", args)

      "Elm.Kernel.PebbleWatch.onScreenChange" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onScreenChange", args)

      "Pebble.Speaker.onFinished" -> subscription_register_call("Pebble.Speaker.onFinished", args)

      "Elm.Kernel.PebbleWatch.onSpeakerFinished" ->
        subscription_register_call("Elm.Kernel.PebbleWatch.onSpeakerFinished", args)

      "Pebble.Compass.onChange" -> subscription_register_call("Pebble.Compass.onChange", args)
      "Pebble.Dictation.start" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_start", args: []}}
      "Pebble.Dictation.stop" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_stop", args: []}}
      "Elm.Kernel.PebbleWatch.dictationStart" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_start", args: []}}
      "Elm.Kernel.PebbleWatch.dictationStop" -> {:ok, %{op: :runtime_call, function: "elmx_dictation_stop", args: []}}
      "Pebble.DataLog.tag" -> data_log_tag(args)
      "Pebble.DataLog.logBytes" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_bytes", args: args}}
      "Pebble.DataLog.logInt32" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_int32", args: args}}
      "Elm.Kernel.PebbleWatch.dataLogBytes" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_bytes", args: args}}
      "Elm.Kernel.PebbleWatch.dataLogInt32" -> {:ok, %{op: :runtime_call, function: "elmx_datalog_log_int32", args: args}}
      "Pebble.Dictation.onStatus" -> subscription_register_call("Pebble.Dictation.onStatus", args)
      "Pebble.Dictation.onResult" -> subscription_register_call("Pebble.Dictation.onResult", args)
      "Pebble.UnobstructedArea.onWillChange" ->
        subscription_register_call("Pebble.UnobstructedArea.onWillChange", args)

      "Pebble.UnobstructedArea.onChanging" ->
        subscription_register_call("Pebble.UnobstructedArea.onChanging", args)

      "Pebble.UnobstructedArea.onDidChange" ->
        subscription_register_call("Pebble.UnobstructedArea.onDidChange", args)
      "Pebble.UnobstructedArea.currentBounds" -> ui_call("elmx_unobstructed_current_bounds", args)
      "Elm.Kernel.PebbleWatch.unobstructedCurrentBounds" -> ui_call("elmx_unobstructed_current_bounds", args)
      "Pebble.Internal.Companion.companionSend" -> ui_call("elmx_companion_send", args)
      "Elm.Kernel.PebbleWatch.companionSend" -> ui_call("elmx_companion_send", args)
      _ -> :unmatched
    end
  end
end
