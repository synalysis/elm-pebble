defmodule Ide.Debugger.LaunchContextTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "start_session attaches typed launch_context on state" do
    slug = "launch_ctx_test_#{System.unique_integer([:positive])}"

    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, state} = Debugger.start_session(slug)
    ctx = state.launch_context

    assert is_binary(ctx["launch_reason"])
    assert is_binary(ctx["watch_profile_id"])
    assert %{"width" => w, "height" => h} = ctx["screen"]
    assert is_integer(w) and is_integer(h)
  end
end
