defmodule Ide.Debugger.RuntimeFollowupsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.AgentSession
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

  describe "async http enqueue" do
    test "appends http_pending row to debugger timeline" do
      previous_async_http = Application.get_env(:ide, :debugger_async_http_followups)

      Application.put_env(:ide, :debugger_async_http_followups, true)

      on_exit(fn ->
        if is_nil(previous_async_http) do
          Application.delete_env(:ide, :debugger_async_http_followups)
        else
          Application.put_env(:ide, :debugger_async_http_followups, previous_async_http)
        end
      end)

      state = RuntimeSurfaces.default_companion()

      ctx = %{
        append_event: fn st, _, _ -> st end,
        append_debugger_event: &AgentSession.append_debugger_event/6,
        apply_step_once: fn st, _, _, _, _, _ -> st end,
        source_root_for_target: fn :phone -> "phone" end,
        track_http_command: &RuntimeFollowups.track_http_command/2,
        simulator_settings: fn _ -> %{} end
      }

      followups = [
        %{
          "package" => "elm/http",
          "command" => %{"method" => "GET", "url" => "https://example.test/dense10.json"},
          "message" => "CatalogReceived"
        }
      ]

      updated =
        RuntimeFollowups.apply_after_step(state, :phone, "init", "init", followups, ctx)

      pending =
        Enum.find(updated.debugger_timeline, fn row ->
          row.message_source == "http_pending"
        end)

      assert pending
      assert pending.type == "http"
      assert pending.message =~ "GET https://example.test/dense10.json"
      assert pending.message =~ "CatalogReceived"
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
