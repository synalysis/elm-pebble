defmodule Ide.Debugger.PackageFollowupReliabilityTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Followups
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeFollowups

  defp step_log do
    :ets.new(:package_followup_steps, [:bag, :private])
  end

  defp base_ctx(steps) do
  %{
      append_event: fn st, _type, _payload -> st end,
      append_debugger_event: fn st, _type, _target, _msg, _src, _value -> st end,
      apply_step_once: fn st, target, message, value, source, trigger ->
        :ets.insert(steps, {target, message, value, source, trigger})
        st
      end,
      track_http_command: fn st, _cmd -> st end,
      simulator_settings: fn _st -> %{} end,
      source_root_for_target: fn
        :watch -> "watch"
        :phone -> "phone"
        :companion -> "phone"
      end
    }
  end

  defp watch_state do
    %{
      watch: %{
        model: %{
          "runtime_model" => %{},
          "debugger_init_complete" => true,
          "runtime_execution_mode" => "runtime_executed"
        }
      }
    }
  end

  defp apply_followup!(state, target, parent_message, followup_row, ctx) do
    RuntimeFollowups.apply_after_step(
      state,
      target,
      parent_message,
      "init",
      [followup_row],
      ctx
    )
  end

  defp step_calls(steps), do: :ets.tab2list(steps)

  describe "elm/core task followups" do
    test "cmd.task.immediate perform applies exactly one runtime_followup step" do
      steps = step_log()
      ctx = base_ctx(steps)

      cmd = Task.perform(fn n -> {:Tick, n} end, {:Ok, 9})
      [row] = Followups.from_commands(cmd, source_root: "phone")

      apply_followup!(watch_state(), :companion, "init", row, ctx)

      assert [{:companion, "Tick", %{"ctor" => "Tick", "args" => [9]}, "runtime_followup", "runtime_followup"}] =
               step_calls(steps)
    end

    test "cmd.task.immediate attempt applies exactly one runtime_followup step for Err" do
      steps = step_log()
      ctx = base_ctx(steps)

      cmd = Task.attempt(fn result -> {:Got, result} end, {:Err, :missing})

      [row] = Followups.from_commands(cmd, source_root: "phone")

      apply_followup!(watch_state(), :companion, "init", row, ctx)

      assert [{:companion, "Got", value, "runtime_followup", "runtime_followup"}] = step_calls(steps)
      assert is_map(value)
    end
  end

  describe "timer followups" do
    test "cmd.timer.after applies exactly one runtime_followup step" do
      steps = step_log()
      ctx = base_ctx(steps)

      row = %{
        "source" => "timer_command",
        "message" => "TimerFired",
        "message_value" => nil,
        "package" => "pebble/cmd",
        "command" => %{
          "kind" => "cmd.timer.after",
          "interval_ms" => 1000,
          "message" => "TimerFired"
        }
      }

      apply_followup!(watch_state(), :watch, "init", row, ctx)

      assert [{:watch, "TimerFired", nil, "runtime_followup", "runtime_followup"}] =
               step_calls(steps)
    end
  end

  describe "device followups" do
    test "cmd.device.current_date_time applies exactly one runtime_followup step" do
      steps = step_log()
      ctx = base_ctx(steps)

      payload = %{
        "year" => 2026,
        "month" => 8,
        "day" => 1,
        "dayOfWeek" => %{"ctor" => "Saturday", "args" => []},
        "hour" => 17,
        "minute" => 57,
        "second" => 0,
        "utcOffsetMinutes" => 120
      }

      row = %{
        "source" => "device_command",
        "message" => "CurrentDateTime",
        "message_value" => %{"ctor" => "CurrentDateTime", "args" => [payload]},
        "package" => "elm-pebble/elm-watch",
        "command" => %{
          "kind" => "cmd.device.current_date_time",
          "message" => "CurrentDateTime",
          "message_value" => %{"ctor" => "CurrentDateTime", "args" => [payload]}
        }
      }

      apply_followup!(watch_state(), :watch, "init", row, ctx)

      assert [{:watch, "CurrentDateTime", value, "runtime_followup", "runtime_followup"}] =
               step_calls(steps)

      assert get_in(value, ["ctor"]) == "CurrentDateTime"
      assert is_list(get_in(value, ["args"]))
    end
  end

  describe "storage followups" do
    test "cmd.storage.read_int applies exactly one runtime_followup step" do
      steps = step_log()
      ctx = base_ctx(steps)

      row = %{
        "source" => "storage_command",
        "message" => "StorageScore",
        "message_value" => %{"ctor" => "StorageScore", "args" => [42]},
        "package" => "elm-pebble/elm-watch",
        "command" => %{
          "kind" => "cmd.storage.read_int",
          "key" => "score",
          "message" => "StorageScore",
          "default" => 0
        }
      }

      state =
        watch_state()
        |> put_in([:watch, :model, "storage"], %{"score" => 42})
        |> put_in([:watch_profile_id], "emery")

      apply_followup!(state, :watch, "init", row, ctx)

      assert [{:watch, "StorageScore", _value, "runtime_followup", "runtime_followup"}] =
               step_calls(steps)
    end
  end

  describe "companion-protocol followups" do
    test "phone_to_watch protocol row enqueues exactly one inline delivery" do
      steps = step_log()
      ctx = base_ctx(steps)

      row = %{
        "package" => "companion-protocol",
        "message" => "ProvideTimezone",
        "message_value" => %{"ctor" => "ProvideTimezone", "args" => [60]},
        "command" => %{
          "kind" => "protocol",
          "to" => "watch",
          "from" => "companion",
          "direction" => "phone_to_watch"
        }
      }

      state = apply_followup!(watch_state(), :companion, "CurrentTime", row, ctx)

      assert step_calls(steps) == []
      assert length(ProtocolRx.inline_protocol_deliveries(state)) == 1
    end
  end
end
