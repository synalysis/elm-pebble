defmodule IdeWeb.WorkspaceLive.EmulatorFlowCaptureProgressTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.EmulatorFlow

  test "renders wait-for-app capture-all progress" do
    assert EmulatorFlow.render_capture_all_progress({:target, "basalt", :waiting_for_app}) =~
             "install screen"

    assert EmulatorFlow.render_capture_all_progress({:target, "chalk", :dismiss_overlay}) =~
             "Dismissing"

    assert EmulatorFlow.render_capture_all_progress({:target, "diorite", :open_from_launcher}) =~
             "launcher"
  end

  test "tracks wait-for-app target statuses" do
    statuses = %{"basalt" => "pending"}

    assert EmulatorFlow.update_capture_target_statuses(
             statuses,
             {:target, "basalt", :waiting_for_app}
           ) == %{"basalt" => "waiting for app"}

    assert EmulatorFlow.update_capture_target_statuses(
             statuses,
             {:target, "basalt", :dismiss_overlay}
           ) == %{"basalt" => "dismissing overlay"}
  end
end
