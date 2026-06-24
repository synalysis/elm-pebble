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

  describe "covered device followups" do
    test "apply_after_step skips only device responses covered by runtime followups" do
      steps = :ets.new(:device_steps, [:set, :private])

      state = %{
        watch: %{
          shell: %{
            "debugger_contract" => %{
              "update_cmd_calls" => [
                %{
                  "target" => "Pebble.Cmd.getCurrentDateTime",
                  "name" => "getCurrentDateTime",
                  "callback_constructor" => "CurrentDateTime",
                  "branch_constructor" => "MinuteChanged"
                },
                %{
                  "target" => "Pebble.Cmd.getBatteryLevel",
                  "name" => "getBatteryLevel",
                  "callback_constructor" => "GotBatteryLevel",
                  "branch_constructor" => "MinuteChanged"
                }
              ]
            }
          },
          model: %{"runtime_model" => %{}}
        }
      }

      ctx = %{
        append_event: fn st, _type, _payload -> st end,
        apply_step_once: fn st, target, message, _value, source, trigger ->
          :ets.insert(steps, {target, message, source, trigger})
          st
        end,
        source_root_for_target: fn :watch -> "watch" end
      }

      followups = [
        %{
          "source" => "device_command",
          "message" => "CurrentDateTime",
          "command" => %{"kind" => "cmd.device.current_date_time"}
        },
        %{"source" => "http_command", "message" => "HttpResponse", "command" => %{"kind" => "http"}}
      ]

      DeviceDataResponses.apply_after_step(
        state,
        :watch,
        "MinuteChanged",
        %{},
        "provided",
        ctx,
        nil,
        followups
      )

      assert Enum.any?(:ets.tab2list(steps), fn {_target, message, _source, _trigger} ->
               String.starts_with?(message, "GotBatteryLevel")
             end)

      refute Enum.any?(:ets.tab2list(steps), fn {_target, message, _source, _trigger} ->
               message == "CurrentDateTime"
             end)
    end
  end
end
