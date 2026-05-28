defmodule Ide.Debugger.RuntimeStatusEventsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeStatusEvents

  test "status_message reports fallback reason" do
    runtime = %{
      "execution_backend" => "fallback_default",
      "external_fallback_reason" => "missing executor"
    }

    assert RuntimeStatusEvents.status_message(runtime) ==
             "runtime fallback fallback_default: missing executor"
  end

  test "meaningful_init_cmd_count ignores Cmd.none" do
    introspect = %{
      "init_cmd_calls" => [
        %{"name" => "send", "target" => "Companion"},
        %{"name" => "none", "target" => "Cmd.none"}
      ]
    }

    assert RuntimeStatusEvents.meaningful_init_cmd_count(introspect) == 1
  end

  test "status_message is nil when init cmd has a planned device-data followup" do
    introspect = %{
      "init_cmd_calls" => [
        %{"name" => "getCurrentTimeString", "target" => "Pebble.Cmd", "callback_constructor" => "CurrentTimeString"}
      ]
    }

    runtime = %{
      "operation_source" => "init_model",
      "runtime_model_source" => "init_model",
      "init_cmd_count" => 1,
      "followup_message_count" => 0,
      "planned_init_followup_count" => RuntimeStatusEvents.planned_init_followup_count(%{}, introspect)
    }

    assert RuntimeStatusEvents.status_message(runtime) == nil
  end

  test "status_message reports when init cmd has no planned followups" do
    runtime = %{
      "operation_source" => "init_model",
      "runtime_model_source" => "init_model",
      "init_cmd_count" => 1,
      "followup_message_count" => 0,
      "planned_init_followup_count" => 0
    }

    assert RuntimeStatusEvents.status_message(runtime) ==
             "runtime no followups for 1 init cmd(s)"
  end
end
