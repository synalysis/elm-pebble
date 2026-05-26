defmodule Ide.Debugger.ReplaySessionTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ReplaySession
  alias Ide.Debugger.SurfaceTargets

  defp normalize_target(value), do: SurfaceTargets.normalize(value)

  test "parse_mode" do
    assert ReplaySession.parse_mode("live") == "live"
    assert ReplaySession.parse_mode("frozen") == "frozen"
    assert ReplaySession.parse_mode("other") == "unknown"
  end

  test "normalize_rows_input maps wire rows" do
    rows = [%{"seq" => 2, "target" => "phone", "message" => "Msg"}]

    assert [%{seq: 2, target: :companion, message: "Msg"}] =
             ReplaySession.normalize_rows_input(rows, &normalize_target/1)
  end

  test "recent_update_messages collects update_in events" do
    state = %{
      events: [
        %{seq: 1, type: "debugger.tick", payload: %{}},
        %{
          seq: 2,
          type: "debugger.update_in",
          payload: %{"target" => "watch", "message" => "TickWatch"}
        },
        %{
          seq: 3,
          type: "debugger.update_in",
          payload: %{"target" => "phone", "message" => "TickPhone"}
        }
      ]
    }

    assert [%{seq: 3, target: :companion, message: "TickPhone"}] =
             ReplaySession.recent_update_messages(state, :companion, 1, nil, &normalize_target/1)

    assert [
             %{seq: 3, target: :companion, message: "TickPhone"},
             %{seq: 2, target: :watch, message: "TickWatch"}
           ] =
             ReplaySession.recent_update_messages(state, nil, 2, nil, &normalize_target/1)
  end
end
