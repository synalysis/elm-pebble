defmodule Ide.Debugger.DeviceDataClockOverrideTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceData

  test "apply_subscription_overrides_to_runtime_now patches now minute from MinuteChanged message" do
    runtime_model = %{
      "now" => %{
        "ctor" => "Just",
        "args" => [%{"hour" => 8, "minute" => 53, "second" => 0}]
      }
    }

    updated =
      DeviceData.apply_subscription_overrides_to_runtime_now(runtime_model, "MinuteChanged 54")

    assert get_in(updated, ["now", "args", Access.at(0), "minute"]) == 54
    assert get_in(updated, ["now", "args", Access.at(0), "hour"]) == 8
  end

  test "subscription_clock_overrides parses JSON MinuteChanged wire payloads" do
    assert DeviceData.subscription_clock_overrides(
             ~s(MinuteChanged {"args":[54],"ctor":"MinuteChanged"})
           ) == %{"minute" => 54}
  end
end
