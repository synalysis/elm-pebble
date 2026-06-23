defmodule Ide.Debugger.LaunchContextSettingsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces

  test "launch_context_for reads launch metadata from simulator settings" do
    settings = %{
      "launch_reason" => "LaunchQuickLaunch",
      "launch_button" => "Select",
      "quick_launch_action" => "QuickLaunchTap"
    }

    ctx = RuntimeSurfaces.launch_context_for("emery", "LaunchUser", settings)

    assert ctx["launch_reason"] == "LaunchQuickLaunch"
    assert ctx["launch_button"] == "Select"
    assert ctx["quick_launch_action"] == "QuickLaunchTap"
    assert ctx["has_speaker"] == true
    assert get_in(ctx, ["screen", "width"]) == 200
  end

  test "parse_launch_reason accepts quick launch and timeline action" do
    assert RuntimeSurfaces.parse_launch_reason("LaunchQuickLaunch") == "LaunchQuickLaunch"
    assert RuntimeSurfaces.parse_launch_reason("LaunchTimelineAction") == "LaunchTimelineAction"
  end
end
