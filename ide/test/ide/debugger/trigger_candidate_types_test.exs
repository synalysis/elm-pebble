defmodule Ide.Debugger.TriggerCandidateTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.TriggerCandidates

  test "for_surface keeps distinct messages for the same subscription trigger" do
    ei = %{
      "msg_constructors" => ["SelectPressed", "UpPressed", "DownPressed"],
      "subscription_calls" => [
        %{
          "target" => "Button.onRelease",
          "name" => "onRelease",
          "event_kind" => "on_release",
          "callback_constructor" => "SelectPressed",
          "label" => "onRelease(Select, SelectPressed)"
        },
        %{
          "target" => "Button.onRelease",
          "name" => "onRelease",
          "event_kind" => "on_release",
          "callback_constructor" => "UpPressed",
          "label" => "onRelease(Up, UpPressed)"
        },
        %{
          "target" => "Button.onRelease",
          "name" => "onRelease",
          "event_kind" => "on_release",
          "callback_constructor" => "DownPressed",
          "label" => "onRelease(Down, DownPressed)"
        }
      ]
    }

    rows = TriggerCandidates.for_surface(ei, "watch")

    assert Enum.count(rows, &(&1.source == "subscription" and &1.trigger == "on_release")) == 3

    assert Enum.any?(rows, &(&1.message == "SelectPressed"))
    assert Enum.any?(rows, &(&1.message == "UpPressed"))
    assert Enum.any?(rows, &(&1.message == "DownPressed"))
  end

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
