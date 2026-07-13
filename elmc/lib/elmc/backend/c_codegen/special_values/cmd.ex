defmodule Elmc.Backend.CCodegen.SpecialValues.Cmd do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.SpecialValues.Stdlib.Effects
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()


  def special_value_from_target("Pebble.Cmd.none", _args),
    do: %{op: :cmd_none}

  def special_value_from_target("Elm.Kernel.PebbleWatch.none", _args),
    do: %{op: :cmd_none}

  def special_value_from_target("Pebble.Cmd.timerAfter", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:timer_after_ms), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.timerAfter", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:timer_after_ms), args, 1)

  def special_value_from_target("Pebble.Cmd.storageWriteInt", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_write_int), args, 2)

  def special_value_from_target("Pebble.Storage.writeInt", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_write_int), args, 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteInt", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_write_int), args, 2)

  def special_value_from_target("Pebble.Cmd.storageReadInt", [key, to_msg]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_read_int), [key, Helpers.constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Pebble.Storage.readInt", [key, to_msg]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_read_int), [key, Helpers.constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageReadInt", [key, to_msg]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_read_int), [key, Helpers.constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.listNthInt", [index, list]) do
    %{
      op: :runtime_call,
      function: "elmc_list_nth_int_default_boxed",
      args: [list, index, %{op: :int_literal, value: 0}]
    }
  end

  def special_value_from_target("Pebble.Cmd.storageDelete", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_delete), args, 1)

  def special_value_from_target("Pebble.Storage.delete", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_delete), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageDelete", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_delete), args, 1)

  def special_value_from_target("Pebble.Storage.writeString", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_write_string), args, 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteString", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_write_string), args, 2)

  def special_value_from_target("Pebble.Storage.readString", [key, to_msg]),
    do:
      Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_read_string), [key, Helpers.constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageReadString", [key, to_msg]),
    do:
      Helpers.encoded_cmd_expr(Helpers.command_kind(:storage_read_string), [key, Helpers.constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Pebble.Storage.maxSize", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:storage_read_max_size, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageReadMaxSize", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:storage_read_max_size, to_msg)

  def special_value_from_target("Pebble.Speaker.isMuted", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:speaker_is_muted, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerIsMuted", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:speaker_is_muted, to_msg)

  def special_value_from_target("Pebble.Speaker.playTone", [frequency, duration, volume, waveform]),
    do:
      Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_play_tone), [frequency, duration, volume, waveform], 4)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerPlayTone", [frequency, duration, volume, waveform]),
    do:
      Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_play_tone), [frequency, duration, volume, waveform], 4)

  def special_value_from_target("Pebble.Speaker.playNotes", [notes, volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_play_notes), [volume, notes], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerPlayNotes", [notes, volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_play_notes), [volume, notes], 2)

  def special_value_from_target("Pebble.Speaker.playTracks", [tracks, volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_play_tracks), [volume, tracks], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerPlayTracks", [tracks, volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_play_tracks), [volume, tracks], 2)

  def special_value_from_target("Pebble.Speaker.stop", _args),
    do: Helpers.command_kind_expr(:speaker_stop)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerStop", _args),
    do: Helpers.command_kind_expr(:speaker_stop)

  def special_value_from_target("Pebble.Speaker.setVolume", [volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_set_volume), [volume], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerSetVolume", [volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_set_volume), [volume], 1)

  def special_value_from_target("Pebble.Speaker.status", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:speaker_get_status, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerGetStatus", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:speaker_get_status, to_msg)

  def special_value_from_target("Pebble.Speaker.streamOpen", [format, volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_stream_open), [format, volume], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerStreamOpen", [format, volume]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_stream_open), [format, volume], 2)

  def special_value_from_target("Pebble.Speaker.streamWrite", [bytes]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_stream_write), [bytes], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerStreamWrite", [bytes]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:speaker_stream_write), [bytes], 1)

  def special_value_from_target("Pebble.Speaker.streamClose", _args),
    do: Helpers.command_kind_expr(:speaker_stream_close)

  def special_value_from_target("Elm.Kernel.PebbleWatch.speakerStreamClose", _args),
    do: Helpers.command_kind_expr(:speaker_stream_close)

  def special_value_from_target("Random.generate", [to_msg, _generator]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:random_generate), [Helpers.constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Elm.Kernel.Random.generate", [to_msg, _generator]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:random_generate), [Helpers.constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Pebble.Internal.Companion.companionSend", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:companion_send), args, 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.companionSend", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:companion_send), args, 2)

  def special_value_from_target("Companion.Watch.sendWatchToPhone", [msg]) do
    case Elmc.Backend.CCodegen.CompanionSendFold.fold_wire_params(msg) do
      {:ok, tag, val} ->
        Helpers.encoded_cmd_expr(
          Helpers.command_kind(:companion_send),
          [%{op: :int_literal, value: tag}, %{op: :int_literal, value: val}],
          2
        )

      :error ->
        Helpers.encoded_cmd_expr(
          Helpers.command_kind(:companion_send),
          [
            %{op: :qualified_call, target: "Companion.Internal.watchToPhoneTag", args: [msg]},
            %{op: :qualified_call, target: "Companion.Internal.watchToPhoneValue", args: [msg]}
          ],
          2
        )
    end
  end

  def special_value_from_target("Pebble.Light.interaction", []),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:backlight), [%{op: :int_literal, value: 0}], 1)

  def special_value_from_target("Pebble.Light.disable", []),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:backlight), [%{op: :int_literal, value: 1}], 1)

  def special_value_from_target("Pebble.Light.enable", []),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:backlight), [%{op: :int_literal, value: 2}], 1)

  def special_value_from_target("Pebble.Cmd.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  def special_value_from_target("Elm.Kernel.PebbleWatch.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  def special_value_from_target("Pebble.Cmd.getCurrentTimeString", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_current_time_string, to_msg)

  def special_value_from_target("Pebble.Time.currentTimeString", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_current_time_string, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentTimeString", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_current_time_string, to_msg)

  def special_value_from_target("Pebble.Cmd.getCurrentDateTime", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_current_date_time, to_msg)

  def special_value_from_target("Pebble.Time.currentDateTime", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_current_date_time, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentDateTime", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_current_date_time, to_msg)

  def special_value_from_target("Pebble.System.batteryLevel", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_battery_level, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getBatteryLevel", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_battery_level, to_msg)

  def special_value_from_target("Pebble.System.connectionStatus", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_connection_status, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getConnectionStatus", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_connection_status, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthSupported", [to_msg]),
    do:
      Helpers.encoded_cmd_expr(
        Helpers.command_kind(:health_supported),
        [Helpers.constructor_tag_expr(to_msg)],
        1
      )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthValue", [metric, to_msg]),
    do:
      Helpers.encoded_cmd_expr(
        Helpers.command_kind(:health_value),
        [metric, Helpers.constructor_tag_expr(to_msg)],
        2
      )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthSumToday", [metric, to_msg]),
    do:
      Helpers.encoded_cmd_expr(
        Helpers.command_kind(:health_sum_today),
        [metric, Helpers.constructor_tag_expr(to_msg)],
        2
      )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthSum", [
        metric,
        start_seconds,
        end_seconds,
        to_msg
      ]),
      do:
        Helpers.encoded_cmd_expr(
          Helpers.command_kind(:health_sum),
          [metric, start_seconds, end_seconds, Helpers.constructor_tag_expr(to_msg)],
          4
        )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthAccessible", [
        metric,
        start_seconds,
        end_seconds,
        to_msg
      ]),
      do:
        Helpers.encoded_cmd_expr(
          Helpers.command_kind(:health_accessible),
          [metric, start_seconds, end_seconds, Helpers.constructor_tag_expr(to_msg)],
          4
        )

  def special_value_from_target("Pebble.Cmd.getClockStyle24h", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_clock_style_24h, to_msg)

  def special_value_from_target("Pebble.Time.clockStyle24h", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_clock_style_24h, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getClockStyle24h", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_clock_style_24h, to_msg)

  def special_value_from_target("Pebble.Cmd.getTimezoneIsSet", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_timezone_is_set, to_msg)

  def special_value_from_target("Pebble.Time.timezoneIsSet", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_timezone_is_set, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getTimezoneIsSet", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_timezone_is_set, to_msg)

  def special_value_from_target("Pebble.Cmd.getTimezone", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_timezone, to_msg)

  def special_value_from_target("Pebble.Time.timezone", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_timezone, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getTimezone", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_timezone, to_msg)

  def special_value_from_target("Pebble.Cmd.getWatchModel", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_watch_model, to_msg)

  def special_value_from_target("Pebble.WatchInfo.getModel", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_watch_model, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getWatchModel", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_watch_model, to_msg)

  def special_value_from_target("Pebble.Cmd.getFirmwareVersion", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_firmware_version, to_msg)

  def special_value_from_target("Pebble.WatchInfo.getFirmwareVersion", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_firmware_version, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getFirmwareVersion", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_firmware_version, to_msg)

  def special_value_from_target("Pebble.WatchInfo.getColor", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_watch_color, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getColor", [to_msg]),
    do: Helpers.encoded_to_msg_cmd(:get_watch_color, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.wakeupScheduleAfterSeconds", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:wakeup_schedule_after_seconds), args, 1)

  def special_value_from_target("Pebble.Wakeup.scheduleAfterSeconds", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:wakeup_schedule_after_seconds), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.wakeupCancel", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:wakeup_cancel), args, 1)

  def special_value_from_target("Pebble.Wakeup.cancel", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:wakeup_cancel), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.logInfoCode", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:log_info_code), args, 1)

  def special_value_from_target("Pebble.Log.infoCode", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:log_info_code), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.logWarnCode", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:log_warn_code), args, 1)

  def special_value_from_target("Pebble.Log.warnCode", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:log_warn_code), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.logErrorCode", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:log_error_code), args, 1)

  def special_value_from_target("Pebble.Log.errorCode", args),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:log_error_code), args, 1)

  def special_value_from_target("Pebble.Cmd.vibesCancel", _args),
    do: Helpers.command_kind_expr(:vibes_cancel)

  def special_value_from_target("Pebble.Vibes.cancel", _args),
    do: Helpers.command_kind_expr(:vibes_cancel)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesCancel", _args),
    do: Helpers.command_kind_expr(:vibes_cancel)

  def special_value_from_target("Pebble.Cmd.vibesShortPulse", _args),
    do: Helpers.command_kind_expr(:vibes_short_pulse)

  def special_value_from_target("Pebble.Vibes.shortPulse", _args),
    do: Helpers.command_kind_expr(:vibes_short_pulse)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesShortPulse", _args),
    do: Helpers.command_kind_expr(:vibes_short_pulse)

  def special_value_from_target("Pebble.Cmd.vibesLongPulse", _args),
    do: Helpers.command_kind_expr(:vibes_long_pulse)

  def special_value_from_target("Pebble.Vibes.longPulse", _args),
    do: Helpers.command_kind_expr(:vibes_long_pulse)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesLongPulse", _args),
    do: Helpers.command_kind_expr(:vibes_long_pulse)

  def special_value_from_target("Pebble.Cmd.vibesDoublePulse", _args),
    do: Helpers.command_kind_expr(:vibes_double_pulse)

  def special_value_from_target("Pebble.Vibes.doublePulse", _args),
    do: Helpers.command_kind_expr(:vibes_double_pulse)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesDoublePulse", _args),
    do: Helpers.command_kind_expr(:vibes_double_pulse)

  def special_value_from_target("Pebble.Vibes.pattern", [segments]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:vibes_custom_pattern), [segments], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesCustomPattern", [segments]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:vibes_custom_pattern), [segments], 1)

  def special_value_from_target("Pebble.DataLog.logBytes", [tag, bytes]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:data_log_bytes), [tag, bytes], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dataLogBytes", [tag, bytes]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:data_log_bytes), [tag, bytes], 2)

  def special_value_from_target("Pebble.DataLog.logInt32", [tag, value]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:data_log_int32), [tag, value], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dataLogInt32", [tag, value]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:data_log_int32), [tag, value], 2)

  def special_value_from_target("Pebble.Compass.current", [to_msg]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:compass_peek), [Helpers.constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.compassCurrent", [to_msg]),
    do: Helpers.encoded_cmd_expr(Helpers.command_kind(:compass_peek), [Helpers.constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Pebble.Dictation.start", _args),
    do: Helpers.command_kind_expr(:dictation_start)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dictationStart", _args),
    do: Helpers.command_kind_expr(:dictation_start)

  def special_value_from_target("Pebble.Dictation.stop", _args),
    do: Helpers.command_kind_expr(:dictation_stop)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dictationStop", _args),
    do: Helpers.command_kind_expr(:dictation_stop)

  def special_value_from_target("Pebble.Cmd.batch", args),
    do: Effects.special_value_from_target("Cmd.batch", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.batch", args),
    do: Effects.special_value_from_target("Cmd.batch", args)

  def special_value_from_target(_target, _args), do: nil
end
