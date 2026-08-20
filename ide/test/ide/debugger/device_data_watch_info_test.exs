defmodule Ide.Debugger.DeviceDataWatchInfoTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.WatchInfo
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.RuntimeSurfaces

  test "flint getColor reply is CoreDevicesP2DWhite and caseColor is white" do
    launch = RuntimeSurfaces.launch_context_for("flint", "LaunchUser")

    wire =
      DeviceData.response_wire_value(%{
        response_message: "GotWatchColor",
        kind: "watch_color",
        preview: launch
      })

    assert wire == %{
             "ctor" => "GotWatchColor",
             "args" => [%{"ctor" => "CoreDevicesP2DWhite", "args" => []}]
           }

    assert WatchInfo.case_color(hd(wire["args"])) == 0xFF
  end

  test "basalt getColor reply stays TimeBlack and caseColor is black" do
    launch = RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

    wire =
      DeviceData.response_wire_value(%{
        response_message: "GotWatchColor",
        kind: "watch_color",
        preview: launch
      })

    assert hd(wire["args"])["ctor"] == "TimeBlack"
    assert WatchInfo.case_color(hd(wire["args"])) == 0xC0
  end

  test "WatchBody resolution follows the getColor constructor" do
    white = WatchInfo.case_color(%{"ctor" => "CoreDevicesP2DWhite", "args" => []})
    black = WatchInfo.case_color(%{"ctor" => "CoreDevicesP2DBlack", "args" => []})

    assert white == 0xFF
    assert black == 0xC0
    refute white == black
  end
end
