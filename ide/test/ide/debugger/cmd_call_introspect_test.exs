defmodule Ide.Debugger.CmdCallIntrospectTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceRequest
  alias Ide.Debugger.CompileContract

  @time_cmd_elm """
  module CmdCalls exposing (..)

  import Pebble.Cmd as PebbleCmd

  type Msg
      = Tick
      | CurrentTime String

  init _ =
      ( {}, Cmd.none )

  update msg model =
      case msg of
          Tick ->
              ( model, PebbleCmd.getCurrentTimeString CurrentTime )

          CurrentTime _ ->
              ( model, Cmd.none )
  """

  @battery_cmd_elm """
  module BatteryCmd exposing (..)

  import Pebble.Cmd as PebbleCmd

  type Msg = GotBattery Int

  init _ =
      ( {}, PebbleCmd.getBatteryLevel GotBattery )
  """

  test "introspect update_cmd_calls rows map to device requests for time cmd" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@time_cmd_elm, "CmdCalls.elm")

    requests =
      ei["update_cmd_calls"]
      |> List.wrap()
      |> Enum.flat_map(&DeviceRequest.from_cmd_call/1)

    assert Enum.any?(requests, fn req ->
             req.kind == "current_time_string" and req.response_message == "CurrentTime"
           end)
  end

  test "introspect init_cmd_calls rows map to battery device request" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@battery_cmd_elm, "BatteryCmd.elm")

    requests =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> Enum.flat_map(&DeviceRequest.from_cmd_call/1)

    assert [%{kind: "battery_level", response_message: "GotBattery"}] = requests
  end
end
