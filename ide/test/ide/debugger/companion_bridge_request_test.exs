defmodule Ide.Debugger.CompanionBridgeRequestTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{CompanionBridgeRequest, CompileContract}

  @storage_init_elm """
  module StorageInit exposing (..)

  import Pebble.Companion.Storage as Storage

  type Msg = GotStorage (Result Storage.Error Storage.Value)

  init _ =
      ( {}, Storage.get "theme" GotStorage )
  """

  @battery_init_elm """
  module BatteryInit exposing (..)

  import Pebble.Companion.Battery as Battery

  type Msg = GotBattery (Result String Battery.BatteryInfo)

  init _ =
      ( {}, Battery.current GotBattery )
  """

  test "init_cmd_calls map storage get to companion bridge request" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@storage_init_elm, "StorageInit.elm")

    [req] =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> CompanionBridgeRequest.from_cmd_calls()

    assert req.api == "storage"
    assert req.op == "get"
    assert req.key == "theme"
    assert req.callback == "GotStorage"
  end

  @timeline_init_elm """
  module TimelineInit exposing (..)

  import Pebble.Companion.Timeline as Timeline

  type Msg = GotToken (Result String String)

  init _ =
      ( {}, Timeline.getToken GotToken )
  """

  test "init_cmd_calls map timeline getToken to bridge request" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@timeline_init_elm, "TimelineInit.elm")

    [req] =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> CompanionBridgeRequest.from_cmd_calls()

    assert req.api == "timeline"
    assert req.op == "getToken"
    assert req.callback == "GotToken"
  end

  @send_bridge_elm """
  module SendBridge exposing (..)

  import Json.Encode as Encode
  import Pebble.Companion.Phone as Phone

  type Msg = Connected (Result String ())

  init _ =
      ( {},
        Phone.sendBridgeCommand
            { id = "webSocket-connect"
            , api = "webSocket"
            , op = "connect"
            , payload = Encode.object [ ( "url", Encode.string "wss://example.test" ) ]
            }
      )
  """

  test "init_cmd_calls map sendBridgeCommand envelope to webSocket connect request" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@send_bridge_elm, "SendBridge.elm")

    [req] =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> CompanionBridgeRequest.from_cmd_calls()

    assert req.api == "webSocket"
    assert req.op == "connect"
    assert req.callback == nil
  end

  test "init_cmd_calls map battery current to status bridge request" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@battery_init_elm, "BatteryInit.elm")

    [req] =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> CompanionBridgeRequest.from_cmd_calls()

    assert req.api == "battery"
    assert req.op == "status"
    assert req.callback == "GotBattery"
  end
end
