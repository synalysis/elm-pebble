defmodule Ide.Debugger.AutoTickTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "default session auto_tick is disabled" do
    slug = "auto_tick_types_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, state} = Debugger.start_session(slug)
    tick = state.auto_tick

    assert tick.enabled == false
    assert tick.worker_pid == nil
    assert is_list(tick.targets)
  end
end
