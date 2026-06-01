defmodule ElmExecutor.PebbleDictationBuiltinTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package
  test "Elm.Kernel.PebbleWatch.dictationStart emits batched dictation followups" do
    assert {:ok, %{"kind" => "cmd.batch", "commands" => commands}} =
             Package.eval("elm.kernel.pebblewatch", "dictationstart", [], %{})

    messages = Enum.map(commands, & &1["message"])
    assert Enum.count(messages, &(&1 == "DictationStatusChanged")) == 3
    assert "DictationFinished" in messages

    finished = Enum.find(commands, &(&1["message"] == "DictationFinished"))
    assert finished["kind"] == "cmd.dictation.followup"
    assert %{"ctor" => "DictationFinished", "args" => [%{"ctor" => "Ok", "args" => ["Hello"]}]} =
             finished["message_value"]
  end

  test "Elm.Kernel.PebbleWatch.dictationStop emits cancelled DictationFinished followup" do
    assert {:ok, command} = Package.eval("elm.kernel.pebblewatch", "dictationstop", [], %{})

    assert command["kind"] == "cmd.dictation.followup"
    assert command["message"] == "DictationFinished"

    assert %{
             "ctor" => "DictationFinished",
             "args" => [%{"ctor" => "Err", "args" => [%{"ctor" => "Cancelled", "args" => []}]}]
           } = command["message_value"]
  end

  test "Pebble.Dictation.start and stop route through pebble.dictation module" do
    assert {:ok, %{"kind" => "cmd.batch"}} = Package.eval("pebble.dictation", "start", [], %{})
    assert {:ok, %{"kind" => "cmd.dictation.followup"}} = Package.eval("pebble.dictation", "stop", [], %{})
  end
end
