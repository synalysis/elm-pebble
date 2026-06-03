defmodule Elmc.Backend.CCodegen.Subscriptions do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @spec clamp_frame_interval_ms(integer()) :: pos_integer()
  def clamp_frame_interval_ms(ms) when is_integer(ms) do
    ms
    |> max(1)
    |> min(32_767)
  end

  @spec subscription_batch_expr([Types.ir_expr()]) :: Types.ir_expr()
  def subscription_batch_expr([%{op: :list_literal, items: items}]) do
    exprs =
      items
      |> Enum.map(&subscription_item_c_expr/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if length(exprs) == length(items) and exprs != [] do
      %{op: :c_int_expr, value: exprs |> Enum.map(&"(#{&1})") |> Enum.join(" | ")}
    else
      mask =
        Enum.reduce(items, 0, fn item, acc ->
          Bitwise.bor(acc, subscription_item_mask(item))
        end)

      %{op: :int_literal, value: mask}
    end
  end

  def subscription_batch_expr(_), do: %{op: :unsupported}

  defp subscription_item_c_expr(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    case SpecialValues.normalize_special_target(target) do
      "Pebble.Frame.every" ->
        frame_subscription_c_expr(args)

      "Pebble.Frame.atFps" ->
        frame_fps_subscription_c_expr(args)

      "Elm.Kernel.PebbleWatch.onFrame" ->
        frame_subscription_c_expr(args)

      normalized ->
        subscription_item_c_expr(%{op: :qualified_call, target: normalized})
    end
  end

  defp subscription_item_c_expr(%{op: :qualified_call, target: target}) when is_binary(target) do
    case SpecialValues.normalize_special_target(target) do
      "Pebble.Events.onSecondChange" -> "ELMC_SUBSCRIPTION_SECOND_CHANGE"
      "Elm.Kernel.PebbleWatch.onSecondChange" -> "ELMC_SUBSCRIPTION_SECOND_CHANGE"
      "Pebble.Events.onHourChange" -> "ELMC_SUBSCRIPTION_HOUR_CHANGE"
      "Elm.Kernel.PebbleWatch.onHourChange" -> "ELMC_SUBSCRIPTION_HOUR_CHANGE"
      "Pebble.Events.onMinuteChange" -> "ELMC_SUBSCRIPTION_MINUTE_CHANGE"
      "Elm.Kernel.PebbleWatch.onMinuteChange" -> "ELMC_SUBSCRIPTION_MINUTE_CHANGE"
      "Pebble.Events.onDayChange" -> "ELMC_SUBSCRIPTION_DAY_CHANGE"
      "Elm.Kernel.PebbleWatch.onDayChange" -> "ELMC_SUBSCRIPTION_DAY_CHANGE"
      "Pebble.Events.onMonthChange" -> "ELMC_SUBSCRIPTION_MONTH_CHANGE"
      "Elm.Kernel.PebbleWatch.onMonthChange" -> "ELMC_SUBSCRIPTION_MONTH_CHANGE"
      "Pebble.Events.onYearChange" -> "ELMC_SUBSCRIPTION_YEAR_CHANGE"
      "Elm.Kernel.PebbleWatch.onYearChange" -> "ELMC_SUBSCRIPTION_YEAR_CHANGE"
      "Pebble.Button.on" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Pebble.Button.onPress" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Pebble.Button.onRelease" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Pebble.Button.onLongPress" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Elm.Kernel.PebbleWatch.onButtonRaw" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Elm.Kernel.PebbleWatch.onButtonUp" -> "ELMC_SUBSCRIPTION_BUTTON_UP"
      "Elm.Kernel.PebbleWatch.onButtonSelect" -> "ELMC_SUBSCRIPTION_BUTTON_SELECT"
      "Elm.Kernel.PebbleWatch.onButtonDown" -> "ELMC_SUBSCRIPTION_BUTTON_DOWN"
      "Elm.Kernel.PebbleWatch.onButtonLongUp" -> "ELMC_SUBSCRIPTION_BUTTON_LONG_UP"
      "Elm.Kernel.PebbleWatch.onButtonLongSelect" -> "ELMC_SUBSCRIPTION_BUTTON_LONG_SELECT"
      "Elm.Kernel.PebbleWatch.onButtonLongDown" -> "ELMC_SUBSCRIPTION_BUTTON_LONG_DOWN"
      "Pebble.Accel.onTap" -> "ELMC_SUBSCRIPTION_ACCEL_TAP"
      "Elm.Kernel.PebbleWatch.onAccelTap" -> "ELMC_SUBSCRIPTION_ACCEL_TAP"
      _ -> nil
    end
  end

  defp subscription_item_c_expr(_), do: nil

  defp frame_subscription_c_expr([%{op: :int_literal, value: ms}, _to_msg]) when is_integer(ms) do
    "(ELMC_SUBSCRIPTION_FRAME_BASE + (#{clamp_frame_interval_ms(ms)} << 16))"
  end

  defp frame_subscription_c_expr(_args), do: "(ELMC_SUBSCRIPTION_FRAME_BASE + (33 << 16))"

  defp frame_fps_subscription_c_expr([%{op: :int_literal, value: fps}, _to_msg])
       when is_integer(fps) do
    "(ELMC_SUBSCRIPTION_FRAME_BASE + (#{clamp_frame_interval_ms(div(1000, max(fps, 1)))} << 16))"
  end

  defp frame_fps_subscription_c_expr(_args), do: "(ELMC_SUBSCRIPTION_FRAME_BASE + (33 << 16))"

  @spec subscription_item_mask(Types.ir_expr()) :: non_neg_integer()
  defp subscription_item_mask(%{op: :int_literal, value: value}) when is_integer(value), do: value

  defp subscription_item_mask(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    case SpecialValues.special_value_from_target(target, args) do
      %{op: :int_literal, value: value} when is_integer(value) ->
        value

      _ ->
        subscription_item_mask(%{op: :qualified_call, target: target})
    end
  end

  defp subscription_item_mask(%{op: :qualified_call, target: target}) when is_binary(target) do
    case SpecialValues.normalize_special_target(target) do
      "Pebble.Events.onSecondChange" -> 1
      "Pebble.Frame.every" -> 8192
      "Pebble.Frame.atFps" -> 8192
      "Pebble.Events.onHourChange" -> 1024
      "Pebble.Events.onMinuteChange" -> 2048
      "Pebble.Events.onDayChange" -> 65_536
      "Pebble.Events.onMonthChange" -> 131_072
      "Pebble.Events.onYearChange" -> 262_144
      "Pebble.Button.on" -> 16384
      "Pebble.Button.onPress" -> 16384
      "Pebble.Button.onRelease" -> 16384
      "Pebble.Button.onLongPress" -> 16384
      "Pebble.Accel.onTap" -> 16
      "Pebble.Accel.onData" -> 32768
      "Pebble.System.onBatteryChange" -> 32
      "Pebble.System.onConnectionChange" -> 64
      "Pebble.Health.onEvent" -> 2_147_483_648
      "Elm.Kernel.PebbleWatch.onBatteryChange" -> 32
      "Elm.Kernel.PebbleWatch.onConnectionChange" -> 64
      "Elm.Kernel.PebbleWatch.onHealthEvent" -> 2_147_483_648
      "Pebble.AppFocus.onChange" -> 524_288
      "Elm.Kernel.PebbleWatch.onAppFocusChange" -> 524_288
      "Pebble.Compass.onChange" -> 1_048_576
      "Elm.Kernel.PebbleWatch.onCompassChange" -> 1_048_576
      "Pebble.Dictation.onStatus" -> 2_097_152
      "Pebble.Dictation.onResult" -> 2_097_152
      "Elm.Kernel.PebbleWatch.onDictationStatus" -> 2_097_152
      "Elm.Kernel.PebbleWatch.onDictationResult" -> 2_097_152
      "Pebble.UnobstructedArea.onWillChange" -> 4_194_304
      "Pebble.UnobstructedArea.onChanging" -> 4_194_304
      "Pebble.UnobstructedArea.onDidChange" -> 4_194_304
      "Elm.Kernel.PebbleWatch.onUnobstructedWillChange" -> 4_194_304
      "Elm.Kernel.PebbleWatch.onUnobstructedChanging" -> 4_194_304
      "Elm.Kernel.PebbleWatch.onUnobstructedDidChange" -> 4_194_304
      "Elm.Kernel.PebbleWatch.onFrame" -> 8192
      "Elm.Kernel.PebbleWatch.onButtonUp" -> 2
      "Elm.Kernel.PebbleWatch.onButtonSelect" -> 4
      "Elm.Kernel.PebbleWatch.onButtonDown" -> 8
      "Elm.Kernel.PebbleWatch.onButtonLongUp" -> 128
      "Elm.Kernel.PebbleWatch.onButtonLongSelect" -> 256
      "Elm.Kernel.PebbleWatch.onButtonLongDown" -> 512
      "Elm.Kernel.PebbleWatch.onButtonRaw" -> 16384
      "Elm.Kernel.PebbleWatch.onAccelTap" -> 16
      "Elm.Kernel.PebbleWatch.onAccelData" -> 32768
      "Companion.Watch.onPhoneToWatch" -> 4096
      "Elm.Kernel.PebbleWatch.onHourChange" -> 1024
      "Elm.Kernel.PebbleWatch.onMinuteChange" -> 2048
      "Elm.Kernel.PebbleWatch.onSecondChange" -> 1
      "Elm.Kernel.PebbleWatch.onDayChange" -> 65_536
      "Elm.Kernel.PebbleWatch.onMonthChange" -> 131_072
      "Elm.Kernel.PebbleWatch.onYearChange" -> 262_144
      "Elm.Kernel.Time.every" -> 1
      _ -> 0
    end
  end

  defp subscription_item_mask(_), do: 0
end
