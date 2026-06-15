defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags.Platform.SubscriptionEvents do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.event_subscription_platform_flags()
  def compute(targets) do
    %{
      health_events:
        TargetSet.member?(targets, "Pebble.Health.onEvent") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onHealthEvent"),
      app_focus_events:
        TargetSet.member?(targets, "Pebble.AppFocus.onChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onAppFocusChange"),
      compass_events:
        TargetSet.member?(targets, "Pebble.Compass.onChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onCompassChange"),
      dictation_events:
        TargetSet.member?(targets, "Pebble.Dictation.onStatus") or
          TargetSet.member?(targets, "Pebble.Dictation.onResult") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onDictationStatus") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onDictationResult"),
      unobstructed_area_events:
        TargetSet.member?(targets, "Pebble.UnobstructedArea.onWillChange") or
          TargetSet.member?(targets, "Pebble.UnobstructedArea.onChanging") or
          TargetSet.member?(targets, "Pebble.UnobstructedArea.onDidChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onUnobstructedWillChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onUnobstructedChanging") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onUnobstructedDidChange"),
      inbox_events: TargetSet.member?(targets, "Companion.Watch.onPhoneToWatch")
    }
  end
end
