defmodule Ide.Debugger.DeviceDataResponsesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.RuntimeSurfaces

  describe "filter_update_cmd_calls/2" do
    test "returns all rows when no branch_constructor is set" do
      calls = [%{"target" => "A"}, %{"target" => "B"}]
      assert DeviceDataResponses.filter_update_cmd_calls(calls, "Msg") == calls
    end

    test "filters to matching branch_constructor when branch-scoped" do
      calls = [
        %{"target" => "A", "branch_constructor" => "Tick"},
        %{"target" => "B", "branch_constructor" => "Other"}
      ]

      assert DeviceDataResponses.filter_update_cmd_calls(calls, "Tick") == [
               %{"target" => "A", "branch_constructor" => "Tick"}
             ]
    end
  end

  describe "apply_after_step/6" do
    test "skips configuration message source" do
      state = RuntimeSurfaces.default_watch()

      assert DeviceDataResponses.apply_after_step(
               state,
               :watch,
               "Tick",
               %{},
               "configuration",
               %{}
             ) == state
    end
  end
end
