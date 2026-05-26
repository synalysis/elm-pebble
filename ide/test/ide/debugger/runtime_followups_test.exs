defmodule Ide.Debugger.RuntimeFollowupsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.RuntimeSurfaces

  describe "apply_after_step/6" do
    test "skips configuration and runtime_followup sources" do
      state = RuntimeSurfaces.default_watch()
      ctx = %{}

      assert RuntimeFollowups.apply_after_step(state, :watch, "Tick", "configuration", [], ctx) ==
               state

      assert RuntimeFollowups.apply_after_step(state, :watch, "Tick", "runtime_followup", [], ctx) ==
               state
    end
  end

  describe "track_http_command/2" do
    test "dedupes by method and url and caps list length" do
      state = RuntimeSurfaces.default_companion()
      cmd = %{"kind" => "http", "method" => "GET", "url" => "https://example.test"}

      once = RuntimeFollowups.track_http_command(state, cmd)
      updated = Map.put(cmd, "package", "elm/http")
      twice = RuntimeFollowups.track_http_command(once, updated)

      tracked = RuntimeFollowups.tracked_http_commands(twice)
      assert length(tracked) == 1
      assert hd(tracked)["method"] == "GET"
      assert hd(tracked)["url"] == "https://example.test"
      assert hd(tracked)["package"] == "elm/http"
    end
  end
end
