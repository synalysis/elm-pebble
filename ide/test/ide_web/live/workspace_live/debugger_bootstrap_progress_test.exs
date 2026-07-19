defmodule IdeWeb.WorkspaceLive.DebuggerBootstrapProgressTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.DebuggerBootstrapFlow
  alias IdeWeb.WorkspaceLive.DebuggerPage.SessionState

  test "bootstrap step count matches segmented progress bar" do
    assert SessionState.bootstrap_step_count() == DebuggerBootstrapFlow.bootstrap_step_count()
    assert DebuggerBootstrapFlow.bootstrap_step_count() == 5
  end

  test "bootstrap step segments reflect current phase" do
    total = SessionState.bootstrap_step_count()

    assert [
             %{index: 1, status: :done},
             %{index: 2, status: :done},
             %{index: 3, status: :active},
             %{index: 4, status: :pending},
             %{index: 5, status: :pending}
           ] = SessionState.bootstrap_step_segments(3, total)

    assert SessionState.bootstrap_step_segments(nil, total) == []
  end
end
