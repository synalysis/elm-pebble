defmodule Elmx.HealthKernelRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.{Cmd, Followups, Pebble}

  test "health value kernel emits cmd.device followup" do
    callback = %{"ctor" => "GotSteps", "args" => []}

    cmd =
      Pebble.runtime_dispatch("elmx_kernel_pebble_watch_health_value", [
        0,
        callback
      ])

    assert cmd["kind"] == "cmd.device.health_value"
    assert cmd["message"] == "GotSteps"

    assert [%{"source" => "device_command", "message" => "GotSteps"}] =
             Followups.from_commands(cmd)
  end

  test "health supported kernel emits cmd.device followup" do
    callback = %{"ctor" => "GotHealthSupported", "args" => []}

    cmd = Pebble.runtime_dispatch("elmx_kernel_pebble_watch_health_supported", [callback])

    assert cmd["kind"] == "cmd.device.health_supported"
    refute match?(%{"kind" => "none"}, cmd)
  end

  test "health sum today kernel emits device command not cmd none" do
    callback = %{"ctor" => "GotSumToday", "args" => []}

    cmd =
      Pebble.runtime_dispatch("elmx_kernel_pebble_watch_health_sum_today", [
        1,
        callback
      ])

    assert cmd["kind"] == "cmd.device.health_sum_today"
    refute Cmd.none() == cmd
  end
end
