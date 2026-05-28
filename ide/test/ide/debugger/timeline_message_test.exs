defmodule Ide.Debugger.TimelineMessageTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TimelineMessage

  test "format includes structured payload" do
    value = %{"ctor" => "CurrentDateTime", "args" => [%{"minute" => 7, "hour" => 8}]}

    assert TimelineMessage.format("CurrentDateTime", value) ==
             "CurrentDateTime " <> Jason.encode!(value)
  end

  test "message_value_for_step parses minute and json payloads" do
    assert TimelineMessage.message_value_for_step("MinuteChanged 42") ==
             {"MinuteChanged", %{"ctor" => "MinuteChanged", "args" => [42]}}

    assert {"CurrentDateTime", %{"ctor" => "CurrentDateTime", "args" => [%{} = payload]}} =
             TimelineMessage.message_value_for_step(
               "CurrentDateTime #{Jason.encode!(%{"minute" => 7, "hour" => 8})}"
             )

    assert payload["minute"] == 7
    assert payload["hour"] == 8
  end

  test "format ignores constructor-only trailing whitespace" do
    assert TimelineMessage.format("MinuteChanged ", nil) == "MinuteChanged"
  end
end
