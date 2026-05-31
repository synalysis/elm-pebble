defmodule ElmExecutor.CompanionSideEffectCmdTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator

  @cmd_none %{"kind" => "cmd.none", "commands" => []}

  defp qualified_call(target, args \\ []) do
    %{"op" => :qualified_call, "target" => target, "args" => args}
  end

  test "companion platform setup and current calls evaluate to cmd.none" do
    for target <- [
          "Pebble.Companion.Battery.setup",
          "Pebble.Companion.Battery.current",
          "Pebble.Companion.Locale.setup",
          "Pebble.Companion.Platform.setup"
        ] do
      assert {:ok, @cmd_none} = CoreIREvaluator.evaluate(qualified_call(target), %{}, %{})
    end
  end

  test "companion phone port and protocol cmds evaluate to cmd.none" do
    for target <- [
          "Pebble.Companion.Phone.outgoing",
          "Pebble.Companion.Phone.sendPhoneToWatch",
          "Pebble.Companion.Phone.send",
          "Pebble.Companion.Phone.request"
        ] do
      assert {:ok, @cmd_none} =
               CoreIREvaluator.evaluate(
                 qualified_call(target, [%{"ctor" => "GotBattery", "args" => []}]),
                 %{},
                 %{}
               )
    end
  end

  test "companion subscription helpers are not stubbed as cmds" do
    assert {:error, {:unknown_function, {"Pebble.Companion.Battery", "onBattery", 1}}} =
             CoreIREvaluator.evaluate(
               qualified_call("Pebble.Companion.Battery.onBattery", [%{"ctor" => "GotBattery", "args" => []}]),
               %{},
               %{}
             )
  end

  test "GotBattery Ok record update preserves unrelated model fields" do
    env = %{
      "model" => %{
        "batteryPercent" => 0,
        "charging" => false,
        "locale" => "--"
      }
    }

    update = %{
      "op" => :record_update,
      "base" => %{"op" => :var, "name" => "model"},
      "fields" => [
        %{"name" => "batteryPercent", "expr" => %{"op" => "int_literal", "value" => 55}},
        %{"name" => "charging", "expr" => %{"op" => "bool_literal", "value" => true}}
      ]
    }

    assert {:ok, %{"batteryPercent" => 55, "charging" => true, "locale" => "--"}} =
             CoreIREvaluator.evaluate(update, env, %{})
  end
end
