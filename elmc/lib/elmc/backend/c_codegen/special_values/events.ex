defmodule Elmc.Backend.CCodegen.SpecialValues.Events do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.SpecialValues.Dispatcher
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Subscriptions

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()


  def special_value_from_target("Pebble.Events.onSecondChange", args),
    do: Helpers.subscription_special_value("Pebble.Events.onSecondChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onSecondChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onSecondChange", args)

  def special_value_from_target("Pebble.Frame.every", args),
    do: Helpers.subscription_special_value("Pebble.Frame.every", args)

  def special_value_from_target("Pebble.Frame.atFps", args),
    do: Helpers.subscription_special_value("Pebble.Frame.atFps", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onFrame", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onFrame", args)

  def special_value_from_target("Pebble.Events.onHourChange", args),
    do: Helpers.subscription_special_value("Pebble.Events.onHourChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onHourChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onHourChange", args)

  def special_value_from_target("Pebble.Events.onMinuteChange", args),
    do: Helpers.subscription_special_value("Pebble.Events.onMinuteChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onMinuteChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onMinuteChange", args)

  def special_value_from_target("Pebble.Events.onDayChange", args),
    do: Helpers.subscription_special_value("Pebble.Events.onDayChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onDayChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onDayChange", args)

  def special_value_from_target("Pebble.Events.onMonthChange", args),
    do: Helpers.subscription_special_value("Pebble.Events.onMonthChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onMonthChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onMonthChange", args)

  def special_value_from_target("Pebble.Events.onYearChange", args),
    do: Helpers.subscription_special_value("Pebble.Events.onYearChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onYearChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onYearChange", args)

  def special_value_from_target("Pebble.Events.onAnimationFinished", args),
    do: Helpers.subscription_special_value("Pebble.Events.onAnimationFinished", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAnimationFinished", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onAnimationFinished", args)

  def special_value_from_target("Pebble.Button.onPress", args),
    do: Helpers.subscription_special_value("Pebble.Button.onPress", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonUp", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonUp", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonSelect", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonSelect", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonDown", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonDown", args)

  def special_value_from_target("Pebble.Button.on", args),
    do: Helpers.subscription_special_value("Pebble.Button.on", args)

  def special_value_from_target("Pebble.Button.onRelease", args),
    do: Helpers.subscription_special_value("Pebble.Button.onRelease", args)

  def special_value_from_target("Pebble.Button.onLongPress", args),
    do: Helpers.subscription_special_value("Pebble.Button.onLongPress", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonRaw", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonRaw", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongUp", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonLongUp", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongSelect", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonLongSelect", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongDown", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onButtonLongDown", args)

  def special_value_from_target("Pebble.Accel.onTap", args),
    do: Helpers.subscription_special_value("Pebble.Accel.onTap", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAccelTap", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onAccelTap", args)

  def special_value_from_target("Pebble.Accel.onData", args),
    do: Helpers.subscription_special_value("Pebble.Accel.onData", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAccelData", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onAccelData", args)

  def special_value_from_target("Pebble.System.onBatteryChange", args),
    do: Helpers.subscription_special_value("Pebble.System.onBatteryChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onBatteryChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onBatteryChange", args)

  def special_value_from_target("Pebble.System.onConnectionChange", args),
    do: Helpers.subscription_special_value("Pebble.System.onConnectionChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onConnectionChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onConnectionChange", args)

  def special_value_from_target("Pebble.Health.onEvent", args),
    do: Helpers.subscription_special_value("Pebble.Health.onEvent", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onHealthEvent", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onHealthEvent", args)

  def special_value_from_target("Pebble.Health.supported", args),
    do: Dispatcher.special_value_from_target("Elm.Kernel.PebbleWatch.healthSupported", args)

  def special_value_from_target("Pebble.Health.value", [metric, to_msg]),
    do:
      Dispatcher.special_value_from_target("Elm.Kernel.PebbleWatch.healthValue", [
        Helpers.health_metric_to_kernel_expr(metric),
        to_msg
      ])

  def special_value_from_target("Pebble.Health.sumToday", [metric, to_msg]),
    do:
      Dispatcher.special_value_from_target("Elm.Kernel.PebbleWatch.healthSumToday", [
        Helpers.health_metric_to_kernel_expr(metric),
        to_msg
      ])

  def special_value_from_target("Pebble.Health.sum", [metric, start_seconds, end_seconds, to_msg]),
      do:
        Dispatcher.special_value_from_target("Elm.Kernel.PebbleWatch.healthSum", [
          Helpers.health_metric_to_kernel_expr(metric),
          start_seconds,
          end_seconds,
          to_msg
        ])

  def special_value_from_target("Pebble.Health.accessible", [
        metric,
        start_seconds,
        end_seconds,
        to_msg
      ]),
      do:
        Dispatcher.special_value_from_target("Elm.Kernel.PebbleWatch.healthAccessible", [
          Helpers.health_metric_to_kernel_expr(metric),
          start_seconds,
          end_seconds,
          to_msg
        ])

  def special_value_from_target("Pebble.AppFocus.onChange", args),
    do: Helpers.subscription_special_value("Pebble.AppFocus.onChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAppFocusChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onAppFocusChange", args)

  def special_value_from_target("Pebble.Light.onChange", args),
    do: Helpers.subscription_special_value("Pebble.Light.onChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onBacklightChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onBacklightChange", args)

  def special_value_from_target("Pebble.Platform.onScreenChange", args),
    do: Helpers.subscription_special_value("Pebble.Platform.onScreenChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onScreenChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onScreenChange", args)

  def special_value_from_target("Pebble.Speaker.onFinished", args),
    do: Helpers.subscription_special_value("Pebble.Speaker.onFinished", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onSpeakerFinished", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onSpeakerFinished", args)

  def special_value_from_target("Pebble.Compass.onChange", args),
    do: Helpers.subscription_special_value("Pebble.Compass.onChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onCompassChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onCompassChange", args)

  def special_value_from_target("Pebble.Dictation.onStatus", args),
    do: Helpers.subscription_special_value("Pebble.Dictation.onStatus", args)

  def special_value_from_target("Pebble.Dictation.onResult", args),
    do: Helpers.subscription_special_value("Pebble.Dictation.onResult", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onDictationStatus", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onDictationStatus", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onDictationResult", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onDictationResult", args)

  def special_value_from_target("Pebble.UnobstructedArea.onWillChange", args),
    do: Helpers.subscription_special_value("Pebble.UnobstructedArea.onWillChange", args)

  def special_value_from_target("Pebble.UnobstructedArea.onChanging", args),
    do: Helpers.subscription_special_value("Pebble.UnobstructedArea.onChanging", args)

  def special_value_from_target("Pebble.UnobstructedArea.onDidChange", args),
    do: Helpers.subscription_special_value("Pebble.UnobstructedArea.onDidChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onUnobstructedWillChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onUnobstructedWillChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onUnobstructedChanging", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onUnobstructedChanging", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onUnobstructedDidChange", args),
    do: Helpers.subscription_special_value("Elm.Kernel.PebbleWatch.onUnobstructedDidChange", args)

  def special_value_from_target("Pebble.UnobstructedArea.currentBounds", [to_msg]),
    do:
      Helpers.encoded_cmd_expr(Helpers.command_kind(:unobstructed_bounds_peek), [Helpers.constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.unobstructedCurrentBounds", [to_msg]),
    do:
      Helpers.encoded_cmd_expr(Helpers.command_kind(:unobstructed_bounds_peek), [Helpers.constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Companion.Watch.onPhoneToWatch", args),
    do: Helpers.subscription_special_value("Companion.Watch.onPhoneToWatch", args)

  def special_value_from_target("Pebble.Events.batch", args),
    do: Subscriptions.subscription_batch_expr(args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.batch", args),
    do: Subscriptions.subscription_batch_expr(args)


  def special_value_from_target(_target, _args), do: nil
end
