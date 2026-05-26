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
end
