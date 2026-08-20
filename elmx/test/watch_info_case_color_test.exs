defmodule Elmx.WatchInfoCaseColorTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Registry
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Pebble.WatchInfo

  test "Pebble.WatchInfo.caseColor rewrites to a runtime call" do
    color = %{op: :var, name: "color"}

    assert {:ok, %{op: :runtime_call, function: "elmx_watch_info_case_color", args: [^color]}} =
             SpecialValues.rewrite("Pebble.WatchInfo.caseColor", [color])
  end

  test "Pebble.WatchInfo.caseColor with no args rewrites to a lambda" do
    assert {:ok,
            %{
              op: :lambda,
              args: ["__color"],
              body: %{op: :runtime_call, function: "elmx_watch_info_case_color"}
            }} = SpecialValues.rewrite("Pebble.WatchInfo.caseColor", [])
  end

  test "caseColor maps distinct watch cases to distinct palette codes" do
    # TimeWhite -> white 0xFF, TimeRed -> red 0xF0
    assert WatchInfo.case_color(:TimeWhite) == 0xFF
    assert WatchInfo.case_color(%{"ctor" => "TimeRed", "args" => []}) == 0xF0
    # TimeSteelGold -> brass 0xE9, Pebble2HrLime -> springBud 0xEC
    assert WatchInfo.case_color("TimeSteelGold") == 0xE9
    assert WatchInfo.case_color(:Pebble2HrLime) == 0xEC
    assert WatchInfo.case_color(:UnknownColor) == 0xC0
    assert WatchInfo.case_color(:Black) == 0xC0
    assert WatchInfo.case_color(:CoreDevicesP2DWhite) == 0xFF
    assert WatchInfo.case_color(:CoreDevicesP2DBlack) == 0xC0
  end

  test "registry applies caseColor for debugger/device stubs" do
    assert Registry.apply("elmx_watch_info_case_color", [:Black]) == 0xC0
    assert Registry.apply("elmx_watch_info_case_color", [%{"ctor" => "TimeWhite", "args" => []}]) ==
             0xFF
  end
end
