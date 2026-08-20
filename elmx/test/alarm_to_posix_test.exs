defmodule Elmx.AlarmToPosixTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Alarm
  alias Elmx.Runtime.Pebble.Registry
  alias Elmx.Runtime.Pebble.SpecialValues

  test "Pebble.Alarm.toPosix rewrites to a runtime call" do
    utc = %{op: :int_literal, value: 1_700_000_000}

    assert {:ok, %{op: :runtime_call, function: "elmx_alarm_to_posix", args: [^utc]}} =
             SpecialValues.rewrite("Pebble.Alarm.toPosix", [utc])
  end

  test "Pebble.Alarm.toPosix with no args rewrites to a lambda" do
    assert {:ok,
            %{
              op: :lambda,
              body: %{op: :runtime_call, function: "elmx_alarm_to_posix"}
            }} = SpecialValues.rewrite("Pebble.Alarm.toPosix", [])
  end

  test "elmx_alarm_to_posix mirrors Elm Maybe Time.Posix semantics" do
    assert Alarm.to_posix(-1) == :Nothing
    assert Alarm.to_posix(0) == {:Just, 0}
    assert Alarm.to_posix(42) == {:Just, 42_000}
    assert Registry.apply("elmx_alarm_to_posix", [-1]) == :Nothing
    assert Registry.apply("elmx_alarm_to_posix", [100]) == {:Just, 100_000}
  end
end
