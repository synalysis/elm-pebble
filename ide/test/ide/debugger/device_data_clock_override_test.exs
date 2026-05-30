defmodule Ide.Debugger.DeviceDataClockOverrideTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceData

  test "subscription_clock_overrides parses MinuteChanged wire payloads for device responses" do
    assert DeviceData.subscription_clock_overrides("MinuteChanged 54") == %{"minute" => 54}

    assert DeviceData.subscription_clock_overrides(
             ~s(MinuteChanged {"args":[54],"ctor":"MinuteChanged"})
           ) == %{"minute" => 54}
  end

  test "apply_subscription_clock_overrides adjusts simulated device time not runtime model" do
    base = ~N[2026-05-27 08:53:00]

    adjusted =
      base
      |> DeviceData.apply_subscription_clock_overrides(DeviceData.subscription_clock_overrides("MinuteChanged 54"))

    assert adjusted.minute == 54
    assert adjusted.hour == 8
  end
end
