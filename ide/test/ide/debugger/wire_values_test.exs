defmodule Ide.Debugger.WireValuesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.WireValues

  describe "coalesce/1" do
    test "returns first non-nil value including 0 and false" do
      assert WireValues.coalesce([nil, 0, 88]) == 0
      assert WireValues.coalesce([nil, false, true]) == false
      assert WireValues.coalesce([nil, nil, "ok"]) == "ok"
      assert WireValues.coalesce([nil, nil]) == nil
    end
  end

  describe "map_get_first_present/2" do
    test "returns first present key value without treating 0 or false as missing" do
      record = %{"latitudeE6" => 0, "battery_percent" => 88}

      assert WireValues.map_get_first_present(record, ["latitudeE6", "battery_percent"]) == 0

      assert WireValues.map_get_first_present(%{"online" => false}, ["online", "charging"]) == false

      assert WireValues.map_get_first_present(%{}, ["missing"]) == nil
    end
  end
end
