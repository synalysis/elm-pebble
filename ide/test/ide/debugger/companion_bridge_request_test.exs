defmodule Ide.Debugger.CompanionBridgeRequestTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{CompanionBridgeRequest, ElmIntrospect}

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
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@storage_init_elm, "StorageInit.elm")

    [req] =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> CompanionBridgeRequest.from_cmd_calls()

    assert req.api == "storage"
    assert req.op == "get"
    assert req.key == "theme"
    assert req.callback == "GotStorage"
  end

  test "init_cmd_calls map battery current to status bridge request" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@battery_init_elm, "BatteryInit.elm")

    [req] =
      ei["init_cmd_calls"]
      |> List.wrap()
      |> CompanionBridgeRequest.from_cmd_calls()

    assert req.api == "battery"
    assert req.op == "status"
    assert req.callback == "GotBattery"
  end
end
