defmodule Ide.Debugger.AvailableTriggersAttrsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.TriggerDiscovery

  test "available_triggers accepts typed target filter attrs" do
    slug = "avail_triggers_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, rows} = Debugger.available_triggers(slug, %{"target" => "watch"})
    assert is_list(rows)
  end

  test "normalize_optional_target maps wire labels" do
    assert TriggerDiscovery.normalize_optional_target("watch") == :watch
    assert TriggerDiscovery.normalize_optional_target(nil) == nil
    assert TriggerDiscovery.normalize_optional_target("phone") == :companion
  end
end
