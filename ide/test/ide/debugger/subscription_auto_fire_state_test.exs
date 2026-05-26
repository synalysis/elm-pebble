defmodule Ide.Debugger.SubscriptionAutoFireStateTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SubscriptionAutoFireState

  test "update_disabled_subscription removes row when enabled" do
    rows = [%{"target" => "watch", "trigger" => "on_hour_change"}]

    assert SubscriptionAutoFireState.update_disabled_subscription(
             rows,
             :watch,
             "on_hour_change",
             true,
             fn :watch -> "watch" end
           ) == []
  end

  test "auto_tick_targets reads enabled surface targets" do
    state =
      RuntimeSurfaces.default_watch()
      |> Map.put(:auto_tick, %{targets: ["watch", "companion"]})

    assert SubscriptionAutoFireState.auto_tick_targets(state) == [:watch, :companion]
  end
end
