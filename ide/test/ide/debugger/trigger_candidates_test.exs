defmodule Ide.Debugger.TriggerCandidatesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TriggerCandidates

  test "best_message_for_trigger maps on_minute_change to MinuteChanged before CurrentDateTime" do
    known = ["CurrentDateTime", "MinuteChanged", "FromPhone"]

    assert TriggerCandidates.best_message_for_trigger(known, "on_minute_change") == "MinuteChanged"
    assert TriggerCandidates.best_message_for_trigger(known, "Events.onMinuteChange") == "MinuteChanged"
  end

  test "best_message_for_trigger maps on_hour_change to HourChanged before CurrentDateTime" do
    known = ["CurrentDateTime", "HourChanged", "MinuteChanged"]

    assert TriggerCandidates.best_message_for_trigger(known, "on_hour_change") == "HourChanged"
  end
end
