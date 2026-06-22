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

    test "matches nested update branch patterns against stepped message" do
      calls = [
        %{"target" => "Weather.current", "branch_constructor" => "FromWatch Ok RequestWeather _"},
        %{"target" => "Cmd.none", "branch_constructor" => "GotWeather Ok Weather.Current info"}
      ]

      assert DeviceDataResponses.filter_update_cmd_calls(
               calls,
               "FromWatch (Ok (RequestWeather CurrentLocation))"
             ) == [
               %{
                 "target" => "Weather.current",
                 "branch_constructor" => "FromWatch Ok RequestWeather _"
               }
             ]
    end
  end

  describe "apply_after_step/7" do
    test "skips configuration message source" do
      state = RuntimeSurfaces.default_watch()

      assert DeviceDataResponses.apply_after_step(
               state,
               :watch,
               "Tick",
               %{},
               "configuration",
               %{},
               nil
             ) == state
    end
  end
end
