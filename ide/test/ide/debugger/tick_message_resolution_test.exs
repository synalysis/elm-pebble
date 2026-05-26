defmodule Ide.Debugger.TickMessageResolutionTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TickMessageResolution

  test "pick_subscription_message prefers minute ops for tick trigger" do
    {message, op} =
      TickMessageResolution.pick_subscription_message(
        ["HourChanged", "MinuteChanged"],
        ["onMinuteChange", "onHourChange"],
        "tick"
      )

    assert message == "MinuteChanged"
    assert op == "onMinuteChange"
  end

  test "tickish_message? matches clock-related constructors" do
    assert TickMessageResolution.tickish_message?("Tick")
    refute TickMessageResolution.tickish_message?("Save")
  end
end
