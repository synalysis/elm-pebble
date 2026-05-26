defmodule Ide.Debugger.ProtocolContextsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ProtocolContexts

  test "cmd_calls_for_message filters update cmd calls by constructor" do
    introspect = %{
      "update_cmd_calls" => [
        %{"name" => "sendWatchToPhone", "branch_constructor" => "Tick"},
        %{"name" => "sendWatchToPhone", "branch_constructor" => "Other"}
      ]
    }

    introspect_for = fn _state, _target -> introspect end

    assert [%{"branch_constructor" => "Tick"}] =
             ProtocolContexts.cmd_calls_for_message(%{}, :watch, "Tick", introspect_for)
  end

  test "events_ctx exposes cmd_calls_for_message callback" do
    ctx =
      ProtocolContexts.events_ctx(%{
        introspect_for: fn _, _ -> %{} end,
        simulator_settings_from_state: fn _ -> %{} end,
        session_key_from_state: fn _ -> nil end,
        surface_app_model: fn _, _ -> %{} end
      })

    assert is_function(ctx.cmd_calls_for_message, 3)
    assert ctx.cmd_calls_for_message.(%{}, :watch, "Tick") == []
  end
end
