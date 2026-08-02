defmodule Elmx.Pebble.Contract.CmdSub do
  @moduledoc """
  Shared contract for supported Pebble Cmd / Sub kinds.

  One row per runtime constant so elmc C macros (`ELMC_PEBBLE_CMD_*` /
  `ELMC_SUBSCRIPTION_*`) and elmx wire/masks stay aligned with Elm API targets.

  - **Cmd** `numeric` / `c_macro` must match `Elmc.Backend.Pebble.Kinds.Tables.CommandKinds`
  - **Sub** `bit` must match `ELMC_PEBBLE_SUB_*` / `ELMC_SUBSCRIPTION_*` / `SubscriptionMasks`
  - `elm_targets` are the qualified call names apps use (no Msg-constructor guessing)
  """

  @type elmx_wire ::
          :none
          | {:device, String.t()}
          | {:timer, String.t()}
          | {:storage, String.t()}
          | {:effect, String.t(), String.t() | nil}
          | {:backlight, nil}
          | {:data_log, String.t()}
          | {:protocol, String.t()}
          | {:dictation, String.t()}
          | {:stub_none, atom()}

  @type cmd_row :: %{
          required(:id) => atom(),
          required(:numeric) => non_neg_integer(),
          required(:c_macro) => String.t(),
          required(:elm_targets) => [String.t()],
          required(:elmx_wire) => elmx_wire(),
          required(:sdk_calls) => [String.t()]
        }

  @type sub_row :: %{
          required(:id) => atom(),
          required(:bit) => non_neg_integer(),
          required(:c_runtime) => String.t() | nil,
          required(:c_lowering) => String.t(),
          required(:elm_targets) => [String.t()],
          required(:sdk_calls) => [String.t()]
        }

  defmodule Row do
    @moduledoc false

    def cmd(id, numeric, targets, wire) do
      %{
        id: id,
        numeric: numeric,
        c_macro: "ELMC_PEBBLE_CMD_" <> (id |> Atom.to_string() |> String.upcase()),
        elm_targets: List.wrap(targets),
        elmx_wire: wire
      }
    end

    def sub(id, bit, c_runtime, c_lowering, targets) do
      %{
        id: id,
        bit: bit,
        c_runtime: c_runtime,
        c_lowering: c_lowering,
        elm_targets: List.wrap(targets)
      }
    end
  end

  @cmds [
    Row.cmd(:none, 0, [], :none),
    Row.cmd(:timer_after_ms, 1, ~w(Pebble.Cmd.timerAfter Elm.Kernel.PebbleWatch.timerAfter), {:timer, "after"}),
    Row.cmd(:storage_write_int, 2, ~w(Pebble.Storage.writeInt Pebble.Cmd.storageWriteInt Elm.Kernel.PebbleWatch.storageWriteInt), {:storage, "write_int"}),
    Row.cmd(:storage_read_int, 3, ~w(Pebble.Storage.readInt Pebble.Cmd.storageReadInt Elm.Kernel.PebbleWatch.storageReadInt), {:storage, "read_int"}),
    Row.cmd(:storage_delete, 4, ~w(Pebble.Storage.delete Pebble.Cmd.storageDelete Elm.Kernel.PebbleWatch.storageDelete), {:storage, "delete"}),
    Row.cmd(
      :companion_send,
      5,
      ~w(Companion.Watch.sendWatchToPhone Pebble.Internal.Companion.companionSend Elm.Kernel.PebbleWatch.companionSend),
      {:protocol, "companion_send"}
    ),
    Row.cmd(
      :backlight,
      6,
      ~w(Pebble.Light.enable Pebble.Light.disable Pebble.Light.interaction Pebble.Cmd.backlight Elm.Kernel.PebbleWatch.backlight),
      {:backlight, nil}
    ),
    Row.cmd(
      :get_current_time_string,
      7,
      ~w(Pebble.Cmd.getCurrentTimeString Pebble.Time.currentTimeString Elm.Kernel.PebbleWatch.getCurrentTimeString),
      {:device, "current_time_string"}
    ),
    Row.cmd(
      :get_clock_style_24h,
      8,
      ~w(Pebble.Cmd.getClockStyle24h Pebble.Time.clockStyle24h Elm.Kernel.PebbleWatch.getClockStyle24h),
      {:device, "clock_style_24h"}
    ),
    Row.cmd(
      :get_timezone_is_set,
      9,
      ~w(Pebble.Cmd.getTimezoneIsSet Pebble.Time.timezoneIsSet Elm.Kernel.PebbleWatch.getTimezoneIsSet),
      {:device, "timezone_is_set"}
    ),
    Row.cmd(
      :get_timezone,
      10,
      ~w(Pebble.Cmd.getTimezone Pebble.Time.timezone Elm.Kernel.PebbleWatch.getTimezone),
      {:device, "timezone"}
    ),
    Row.cmd(
      :get_watch_model,
      11,
      ~w(Pebble.Cmd.getWatchModel Pebble.WatchInfo.getModel Elm.Kernel.PebbleWatch.getWatchModel),
      {:device, "watch_model"}
    ),
    Row.cmd(
      :get_firmware_version,
      12,
      ~w(Pebble.Cmd.getFirmwareVersion Pebble.WatchInfo.getFirmwareVersion Elm.Kernel.PebbleWatch.getFirmwareVersion),
      {:device, "firmware_version"}
    ),
    Row.cmd(:vibes_cancel, 13, ~w(Pebble.Vibes.cancel Pebble.Cmd.vibesCancel Elm.Kernel.PebbleWatch.vibesCancel), {:effect, "vibes", "cancel"}),
    Row.cmd(
      :vibes_short_pulse,
      14,
      ~w(Pebble.Vibes.shortPulse Pebble.Cmd.vibesShortPulse Elm.Kernel.PebbleWatch.vibesShortPulse),
      {:effect, "vibes", "short_pulse"}
    ),
    Row.cmd(
      :vibes_long_pulse,
      15,
      ~w(Pebble.Vibes.longPulse Pebble.Cmd.vibesLongPulse Elm.Kernel.PebbleWatch.vibesLongPulse),
      {:effect, "vibes", "long_pulse"}
    ),
    Row.cmd(
      :vibes_double_pulse,
      16,
      ~w(Pebble.Vibes.doublePulse Pebble.Cmd.vibesDoublePulse Elm.Kernel.PebbleWatch.vibesDoublePulse),
      {:effect, "vibes", "double_pulse"}
    ),
    Row.cmd(:get_watch_color, 17, ~w(Pebble.WatchInfo.getColor Elm.Kernel.PebbleWatch.getColor), {:device, "watch_color"}),
    Row.cmd(
      :wakeup_schedule_after_seconds,
      18,
      ~w(Pebble.Wakeup.scheduleAfterSeconds Elm.Kernel.PebbleWatch.wakeupScheduleAfterSeconds),
      {:stub_none, :wakeup}
    ),
    Row.cmd(:wakeup_cancel, 19, ~w(Pebble.Wakeup.cancel Elm.Kernel.PebbleWatch.wakeupCancel), {:stub_none, :wakeup}),
    Row.cmd(:log_info_code, 20, ~w(Pebble.Log.infoCode Elm.Kernel.PebbleWatch.logInfoCode), {:stub_none, :log}),
    Row.cmd(:log_warn_code, 21, ~w(Pebble.Log.warnCode Elm.Kernel.PebbleWatch.logWarnCode), {:stub_none, :log}),
    Row.cmd(:log_error_code, 22, ~w(Pebble.Log.errorCode Elm.Kernel.PebbleWatch.logErrorCode), {:stub_none, :log}),
    Row.cmd(
      :get_current_date_time,
      23,
      ~w(Pebble.Cmd.getCurrentDateTime Pebble.Time.currentDateTime Elm.Kernel.PebbleWatch.getCurrentDateTime),
      {:device, "current_date_time"}
    ),
    Row.cmd(
      :get_battery_level,
      24,
      ~w(Pebble.System.batteryLevel Elm.Kernel.PebbleWatch.getBatteryLevel),
      {:device, "battery_level"}
    ),
    Row.cmd(
      :get_connection_status,
      25,
      ~w(Pebble.System.connectionStatus Elm.Kernel.PebbleWatch.getConnectionStatus),
      {:device, "connection_status"}
    ),
    Row.cmd(
      :storage_write_string,
      26,
      ~w(Pebble.Storage.writeString Elm.Kernel.PebbleWatch.storageWriteString),
      {:storage, "write_string"}
    ),
    Row.cmd(
      :storage_read_string,
      27,
      ~w(Pebble.Storage.readString Elm.Kernel.PebbleWatch.storageReadString),
      {:storage, "read_string"}
    ),
    Row.cmd(:random_generate, 28, ~w(Random.generate Elm.Kernel.Random.generate), {:device, "random"}),
    Row.cmd(
      :health_value,
      29,
      ~w(Pebble.Health.value Elm.Kernel.PebbleWatch.healthValue),
      {:device, "health_value"}
    ),
    Row.cmd(
      :health_sum_today,
      30,
      ~w(Pebble.Health.sumToday Elm.Kernel.PebbleWatch.healthSumToday),
      {:device, "health_sum_today"}
    ),
    Row.cmd(
      :health_sum,
      31,
      ~w(Pebble.Health.sum Elm.Kernel.PebbleWatch.healthSum),
      {:device, "health_sum"}
    ),
    Row.cmd(
      :health_accessible,
      32,
      ~w(Pebble.Health.accessible Elm.Kernel.PebbleWatch.healthAccessible),
      {:device, "health_accessible"}
    ),
    Row.cmd(
      :vibes_custom_pattern,
      33,
      ~w(Pebble.Vibes.pattern Elm.Kernel.PebbleWatch.vibesCustomPattern),
      {:effect, "vibes", "pattern"}
    ),
    Row.cmd(:data_log_bytes, 34, ~w(Pebble.DataLog.logBytes Elm.Kernel.PebbleWatch.dataLogBytes), {:data_log, "bytes"}),
    Row.cmd(:data_log_int32, 35, ~w(Pebble.DataLog.logInt32 Elm.Kernel.PebbleWatch.dataLogInt32), {:data_log, "int32"}),
    Row.cmd(:compass_peek, 36, ~w(Pebble.Compass.current Elm.Kernel.PebbleWatch.compassCurrent), {:device, "compass_peek"}),
    Row.cmd(:dictation_start, 37, ~w(Pebble.Dictation.start Elm.Kernel.PebbleWatch.dictationStart), {:dictation, "start"}),
    Row.cmd(:dictation_stop, 38, ~w(Pebble.Dictation.stop Elm.Kernel.PebbleWatch.dictationStop), {:dictation, "stop"}),
    Row.cmd(
      :unobstructed_bounds_peek,
      39,
      ~w(Pebble.UnobstructedArea.currentBounds Elm.Kernel.PebbleWatch.unobstructedCurrentBounds),
      {:device, "unobstructed_bounds_peek"}
    ),
    Row.cmd(
      :health_supported,
      40,
      ~w(Pebble.Health.supported Elm.Kernel.PebbleWatch.healthSupported),
      {:device, "health_supported"}
    ),
    Row.cmd(
      :storage_read_max_size,
      41,
      ~w(Pebble.Storage.maxSize Elm.Kernel.PebbleWatch.storageReadMaxSize),
      {:storage, "read_max_size"}
    ),
    Row.cmd(:speaker_is_muted, 42, ~w(Pebble.Speaker.isMuted Elm.Kernel.PebbleWatch.speakerIsMuted), {:device, "speaker_is_muted"}),
    Row.cmd(
      :speaker_play_tone,
      43,
      ~w(Pebble.Speaker.playTone Elm.Kernel.PebbleWatch.speakerPlayTone),
      {:effect, "speaker", "play_tone"}
    ),
    Row.cmd(
      :speaker_play_notes,
      44,
      ~w(Pebble.Speaker.playNotes Elm.Kernel.PebbleWatch.speakerPlayNotes),
      {:effect, "speaker", "play_notes"}
    ),
    Row.cmd(
      :speaker_play_tracks,
      45,
      ~w(Pebble.Speaker.playTracks Elm.Kernel.PebbleWatch.speakerPlayTracks),
      {:effect, "speaker", "play_tracks"}
    ),
    Row.cmd(:speaker_stop, 46, ~w(Pebble.Speaker.stop Elm.Kernel.PebbleWatch.speakerStop), {:effect, "speaker", "stop"}),
    Row.cmd(
      :speaker_set_volume,
      47,
      ~w(Pebble.Speaker.setVolume Elm.Kernel.PebbleWatch.speakerSetVolume),
      {:effect, "speaker", "set_volume"}
    ),
    Row.cmd(
      :speaker_get_status,
      48,
      ~w(Pebble.Speaker.status Elm.Kernel.PebbleWatch.speakerGetStatus),
      {:device, "speaker_status"}
    ),
    Row.cmd(
      :speaker_stream_open,
      49,
      ~w(Pebble.Speaker.streamOpen Elm.Kernel.PebbleWatch.speakerStreamOpen),
      {:effect, "speaker", "stream_open"}
    ),
    Row.cmd(
      :speaker_stream_write,
      50,
      ~w(Pebble.Speaker.streamWrite Elm.Kernel.PebbleWatch.speakerStreamWrite),
      {:effect, "speaker", "stream_write"}
    ),
    Row.cmd(
      :speaker_stream_close,
      51,
      ~w(Pebble.Speaker.streamClose Elm.Kernel.PebbleWatch.speakerStreamClose),
      {:effect, "speaker", "stream_close"}
    )
  ]

  @subs [
    Row.sub(:second_change, 1, "ELMC_PEBBLE_SUB_TICK", "ELMC_SUBSCRIPTION_SECOND_CHANGE", ~w(
      Pebble.Events.onSecondChange Elm.Kernel.PebbleWatch.onSecondChange Elm.Kernel.Time.every
    )),
    Row.sub(:button_up, 2, "ELMC_PEBBLE_SUB_BUTTON_UP", "ELMC_SUBSCRIPTION_BUTTON_UP", ~w(
      Elm.Kernel.PebbleWatch.onButtonUp
    )),
    Row.sub(:button_select, 4, "ELMC_PEBBLE_SUB_BUTTON_SELECT", "ELMC_SUBSCRIPTION_BUTTON_SELECT", ~w(
      Elm.Kernel.PebbleWatch.onButtonSelect
    )),
    Row.sub(:button_down, 8, "ELMC_PEBBLE_SUB_BUTTON_DOWN", "ELMC_SUBSCRIPTION_BUTTON_DOWN", ~w(
      Elm.Kernel.PebbleWatch.onButtonDown
    )),
    Row.sub(:accel_tap, 16, "ELMC_PEBBLE_SUB_ACCEL_TAP", "ELMC_SUBSCRIPTION_ACCEL_TAP", ~w(
      Pebble.Accel.onTap Elm.Kernel.PebbleWatch.onAccelTap
    )),
    Row.sub(:battery, 32, "ELMC_PEBBLE_SUB_BATTERY", "ELMC_SUBSCRIPTION_BATTERY", ~w(
      Pebble.System.onBatteryChange Elm.Kernel.PebbleWatch.onBatteryChange
    )),
    Row.sub(:connection, 64, "ELMC_PEBBLE_SUB_CONNECTION", "ELMC_SUBSCRIPTION_CONNECTION", ~w(
      Pebble.System.onConnectionChange Elm.Kernel.PebbleWatch.onConnectionChange
    )),
    # Long-press bits exist in ELMC_SUBSCRIPTION_* lowering only (no ELMC_PEBBLE_SUB_* twin).
    Row.sub(:button_long_up, 128, nil, "ELMC_SUBSCRIPTION_BUTTON_LONG_UP", ~w(
      Elm.Kernel.PebbleWatch.onButtonLongUp
    )),
    Row.sub(:button_long_select, 256, nil, "ELMC_SUBSCRIPTION_BUTTON_LONG_SELECT", ~w(
      Elm.Kernel.PebbleWatch.onButtonLongSelect
    )),
    Row.sub(:button_long_down, 512, nil, "ELMC_SUBSCRIPTION_BUTTON_LONG_DOWN", ~w(
      Elm.Kernel.PebbleWatch.onButtonLongDown
    )),
    Row.sub(:hour_change, 1024, "ELMC_PEBBLE_SUB_HOUR", "ELMC_SUBSCRIPTION_HOUR_CHANGE", ~w(
      Pebble.Events.onHourChange Elm.Kernel.PebbleWatch.onHourChange
    )),
    Row.sub(:minute_change, 2048, "ELMC_PEBBLE_SUB_MINUTE", "ELMC_SUBSCRIPTION_MINUTE_CHANGE", ~w(
      Pebble.Events.onMinuteChange Elm.Kernel.PebbleWatch.onMinuteChange
    )),
    Row.sub(:appmessage, 4096, "ELMC_PEBBLE_SUB_APPMESSAGE", "ELMC_SUBSCRIPTION_APPMESSAGE", ~w(
      Companion.Watch.onPhoneToWatch
    )),
    Row.sub(:frame, 8192, "ELMC_PEBBLE_SUB_FRAME", "ELMC_SUBSCRIPTION_FRAME_BASE", ~w(
      Pebble.Frame.every Pebble.Frame.atFps
    )),
    Row.sub(:button_raw, 16384, "ELMC_PEBBLE_SUB_BUTTON_RAW", "ELMC_SUBSCRIPTION_BUTTON_RAW", ~w(
      Pebble.Button.on Pebble.Button.onPress Pebble.Button.onRelease Pebble.Button.onLongPress
      Elm.Kernel.PebbleWatch.onButtonRaw
    )),
    Row.sub(:accel_data, 32768, "ELMC_PEBBLE_SUB_ACCEL_DATA", "ELMC_SUBSCRIPTION_ACCEL_DATA", ~w(
      Pebble.Accel.onData Elm.Kernel.PebbleWatch.onAccelData
    )),
    Row.sub(:day_change, 65536, "ELMC_PEBBLE_SUB_DAY", "ELMC_SUBSCRIPTION_DAY_CHANGE", ~w(
      Pebble.Events.onDayChange Elm.Kernel.PebbleWatch.onDayChange
    )),
    Row.sub(:month_change, 131072, "ELMC_PEBBLE_SUB_MONTH", "ELMC_SUBSCRIPTION_MONTH_CHANGE", ~w(
      Pebble.Events.onMonthChange Elm.Kernel.PebbleWatch.onMonthChange
    )),
    Row.sub(:year_change, 262144, "ELMC_PEBBLE_SUB_YEAR", "ELMC_SUBSCRIPTION_YEAR_CHANGE", ~w(
      Pebble.Events.onYearChange Elm.Kernel.PebbleWatch.onYearChange
    )),
    Row.sub(:app_focus, 524288, "ELMC_PEBBLE_SUB_APP_FOCUS", "ELMC_SUBSCRIPTION_APP_FOCUS", ~w(
      Pebble.AppFocus.onChange Elm.Kernel.PebbleWatch.onAppFocusChange
    )),
    Row.sub(:compass, 1048576, "ELMC_PEBBLE_SUB_COMPASS", "ELMC_SUBSCRIPTION_COMPASS", ~w(
      Pebble.Compass.onChange Elm.Kernel.PebbleWatch.onCompassChange
    )),
    Row.sub(:dictation, 2097152, "ELMC_PEBBLE_SUB_DICTATION", "ELMC_SUBSCRIPTION_DICTATION", ~w(
      Pebble.Dictation.onStatus Pebble.Dictation.onResult
      Elm.Kernel.PebbleWatch.onDictationStatus Elm.Kernel.PebbleWatch.onDictationResult
    )),
    Row.sub(:unobstructed_area, 4194304, "ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA", "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA", ~w(
      Pebble.UnobstructedArea.onWillChange Pebble.UnobstructedArea.onChanging Pebble.UnobstructedArea.onDidChange
      Elm.Kernel.PebbleWatch.onUnobstructedWillChange Elm.Kernel.PebbleWatch.onUnobstructedChanging
      Elm.Kernel.PebbleWatch.onUnobstructedDidChange
    )),
    Row.sub(:animation_finished, 8388608, "ELMC_PEBBLE_SUB_ANIMATION_FINISHED", "ELMC_SUBSCRIPTION_ANIMATION_FINISHED", ~w(
      Pebble.Events.onAnimationFinished Elm.Kernel.PebbleWatch.onAnimationFinished
    )),
    Row.sub(:backlight, 16777216, "ELMC_PEBBLE_SUB_BACKLIGHT", "ELMC_SUBSCRIPTION_BACKLIGHT", ~w(
      Pebble.Light.onChange Elm.Kernel.PebbleWatch.onBacklightChange
    )),
    Row.sub(:screen_change, 33554432, "ELMC_PEBBLE_SUB_SCREEN_CHANGE", "ELMC_SUBSCRIPTION_SCREEN_CHANGE", ~w(
      Pebble.Platform.onScreenChange Elm.Kernel.PebbleWatch.onScreenChange
    )),
    Row.sub(:speaker_finished, 67108864, "ELMC_PEBBLE_SUB_SPEAKER_FINISHED", "ELMC_SUBSCRIPTION_SPEAKER_FINISHED", ~w(
      Pebble.Speaker.onFinished Elm.Kernel.PebbleWatch.onSpeakerFinished
    )),
    Row.sub(:health, 2147483648, "ELMC_PEBBLE_SUB_HEALTH", "ELMC_SUBSCRIPTION_HEALTH", ~w(
      Pebble.Health.onEvent Elm.Kernel.PebbleWatch.onHealthEvent
    ))
  ]

  @spec cmds() :: [cmd_row()]
  def cmds do
    Enum.map(@cmds, &enrich_cmd/1)
  end

  @spec subs() :: [sub_row()]
  def subs do
    Enum.map(@subs, &enrich_sub/1)
  end

  defp enrich_cmd(row) do
    Map.put(row, :sdk_calls, Elmx.Pebble.Contract.SdkCalls.cmd(row.id))
  end

  defp enrich_sub(row) do
    Map.put(row, :sdk_calls, Elmx.Pebble.Contract.SdkCalls.sub(row.id))
  end

  @spec cmd!(atom()) :: cmd_row()
  def cmd!(id) when is_atom(id) do
    Enum.find(@cmds, &(&1.id == id)) || raise KeyError, key: id, term: :cmd_contract
  end

  @spec sub!(atom()) :: sub_row()
  def sub!(id) when is_atom(id) do
    Enum.find(@subs, &(&1.id == id)) || raise KeyError, key: id, term: :sub_contract
  end

  @spec cmd_ids() :: [atom()]
  def cmd_ids, do: Enum.map(@cmds, & &1.id)

  @spec sub_ids() :: [atom()]
  def sub_ids, do: Enum.map(@subs, & &1.id)

  @spec elmx_supported_cmds() :: [cmd_row()]
  def elmx_supported_cmds do
    Enum.reject(@cmds, fn
      %{elmx_wire: {:stub_none, _}} -> true
      %{id: :none} -> true
      _ -> false
    end)
  end

  @spec elmx_wire_kind(elmx_wire()) :: String.t() | nil
  def elmx_wire_kind(:none), do: nil
  def elmx_wire_kind({:device, slug}), do: "cmd.device.#{slug}"
  def elmx_wire_kind({:timer, "after"}), do: "cmd.timer.after"
  def elmx_wire_kind({:storage, slug}), do: "cmd.storage.#{slug}"
  def elmx_wire_kind({:effect, family, _variant}), do: "cmd.effect.#{family}"
  def elmx_wire_kind({:backlight, nil}), do: "cmd.backlight"
  def elmx_wire_kind({:data_log, "bytes"}), do: "cmd.data_log.bytes"
  def elmx_wire_kind({:data_log, "int32"}), do: "cmd.data_log.int32"
  def elmx_wire_kind({:protocol, _}), do: "protocol"
  def elmx_wire_kind({:dictation, _}), do: "cmd.dictation.followup"
  def elmx_wire_kind({:stub_none, _}), do: nil

end
