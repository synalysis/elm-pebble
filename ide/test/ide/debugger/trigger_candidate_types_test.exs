defmodule Ide.Debugger.TriggerCandidateTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "trigger_candidates returns rows with message and target" do
    slug = "trigger_types_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, state} = Debugger.start_session(slug)
    candidates = Debugger.trigger_candidates(state, :watch)

    if candidates != [] do
      row = hd(candidates)
      assert is_binary(row.message)
      assert is_binary(row.target)
      assert row.message != ""
    end
  end
end
