defmodule Ide.Debugger.DeviceDataInitRequestsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{CmdCall, CompileContract, DeviceData, DeviceDataResponses}

  @poke_dir Path.expand("../../../priv/project_templates/watchface_poke_battle", __DIR__)

  defp poke_introspect do
    {:ok, contract} = CompileContract.build_for_project_dir(@poke_dir)
    contract
  end

  test "init_cmd_calls are only scheduled when stepping init, not other device callbacks" do
    ei = poke_introspect()
    model = %{"launch_context" => %{"supports_health" => true}}

    opts = [
      message_constructor: & &1,
      update_cmd_calls_filter: &DeviceDataResponses.filter_update_cmd_calls/2,
      expand_cmd_calls: &CmdCall.expand_helpers/2
    ]

    init_requests =
      DeviceData.requests_for_message(ei, model, "init", opts)
      |> Enum.map(& &1.response_message)

    clock_requests =
      DeviceData.requests_for_message(ei, model, "ClockStyle24h", opts)
      |> Enum.map(& &1.response_message)

    assert "CurrentDateTime" in init_requests
    assert "ClockStyle24h" in init_requests
    assert clock_requests == []
  end

  test "device_kind_for_callback scans update_cmd_calls when init has no match" do
    ei = %{
      "init_cmd_calls" => [],
      "update_cmd_calls" => [
        %{
          "callback_constructor" => "CurrentDateTime",
          "target" => "Pebble.Time.currentDateTime",
          "kind" => "cmd"
        }
      ]
    }

    assert DeviceData.response_wire_for_callback(ei, %{}, "MissingCtor", nil) == nil
  end
end
