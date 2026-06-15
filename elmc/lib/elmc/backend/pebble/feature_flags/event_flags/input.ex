defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags.Input do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.{EventFlags.Lookup, TargetSet}
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set(), Types.msg_constructor_list()) :: Types.event_input_flags()
  def compute(targets, msg_constructors) do
    %{
      button_events:
        Lookup.has_any_constructor?(msg_constructors, ["UpPressed", "SelectPressed", "DownPressed"]),
      raw_button_events:
        TargetSet.member?(targets, "Pebble.Button.on") or
          TargetSet.member?(targets, "Pebble.Button.onPress") or
          TargetSet.member?(targets, "Pebble.Button.onRelease") or
          TargetSet.member?(targets, "Pebble.Button.onLongPress") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onButtonRaw"),
      accel_events: Lookup.has_any_constructor?(msg_constructors, ["Shake", "AccelTap", "Tapped"]),
      accel_data_events:
        TargetSet.member?(targets, "Pebble.Accel.onData") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onAccelData")
    }
  end
end
