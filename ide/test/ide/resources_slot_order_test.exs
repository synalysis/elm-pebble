defmodule Ide.Resources.SlotOrderTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.SlotOrder

  test "vector slot order puts static ctors before animated and sorts by name within kind" do
    entries = [
      %{"ctor" => "VectorAnimatedSpark"},
      %{"ctor" => "VectorStaticMountain"},
      %{"ctor" => "VectorStaticBattery"}
    ]

    assert Enum.map(SlotOrder.sort_wire_entries(entries, :vector), & &1["ctor"]) == [
             "VectorStaticBattery",
             "VectorStaticMountain",
             "VectorAnimatedSpark"
           ]
  end
end
