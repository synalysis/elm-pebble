defmodule Ide.Debugger.WatchProfileTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.WatchModels

  test "watch_profiles returns typed list items for two catalog entries" do
    profiles = Debugger.watch_profiles()
    assert length(profiles) == length(WatchModels.ordered_ids())

    basalt = Enum.find(profiles, &(&1["id"] == "basalt"))
    chalk = Enum.find(profiles, &(&1["id"] == "chalk"))

    assert basalt["label"] =~ "Basalt"
    assert basalt["supports_health"] == true
    assert get_in(basalt, ["screen", "width"]) == 144

    assert chalk["shape"] == "round"
    assert chalk["color_mode"] == "Color"
  end

  test "start_session with chalk profile applies round screen launch context" do
    slug = "watch_profile_chalk_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, state} =
             Debugger.start_session(slug, %{"watch_profile_id" => "chalk", "launch_reason" => "LaunchUser"})

    ctx = state.launch_context

    assert ctx["watch_profile_id"] == "chalk"
    assert ctx["screen"]["width"] == 180
    assert ctx["screen"]["height"] == 180
    assert ctx["shape"] == "round"
    assert ctx["screen"]["shape"] == "Round"
  end
end
