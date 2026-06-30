defmodule Ide.Debugger.RuntimeFollowupsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.RuntimeSurfaces

  describe "apply_after_step/6" do
    test "skips configuration and non-protocol runtime_followup sources" do
      state = RuntimeSurfaces.default_watch()
      ctx = %{}

      assert RuntimeFollowups.apply_after_step(state, :watch, "Tick", "configuration", [], ctx) ==
               state

      assert RuntimeFollowups.apply_after_step(state, :watch, "Tick", "runtime_followup", [], ctx) ==
               state
    end

    test "delivers companion-protocol followups from runtime_followup steps" do
      state = RuntimeSurfaces.default_phone()

      ctx = %{
        append_event: fn st, _, _ -> st end,
        apply_step_once: fn st, _target, _message, _message_value, _source, _trigger ->
          flunk("phone_to_watch protocol followups should queue inline delivery")
          st
        end,
        source_root_for_target: fn
          :watch -> "watch"
          :phone -> "phone"
        end
      }

      followups = [
        %{
          "package" => "companion-protocol",
          "message" => "ProvideTimezone",
          "message_value" => %{"ctor" => "ProvideTimezone", "args" => [120]},
          "command" => %{"to" => "watch", "direction" => "phone_to_watch"}
        }
      ]

      updated =
        RuntimeFollowups.apply_after_step(
          state,
          :phone,
          "CurrentTime",
          "runtime_followup",
          followups,
          ctx
        )

      assert [%{"message" => "ProvideTimezone", "to" => "watch"}] =
               ProtocolRx.inline_protocol_deliveries(updated)
    end

    test "queues watch_to_phone companion-protocol followups for inline protocol delivery" do
      state = RuntimeSurfaces.default_companion()

      ctx = %{
        append_event: fn st, _, _ -> st end,
        append_debugger_event: fn st, _, _, _, _, _ -> st end,
        apply_step_once: fn st, _target, _message, _message_value, _source, _trigger ->
          flunk("watch_to_phone protocol followups should queue inline delivery")
          st
        end,
        source_root_for_target: fn
          :watch -> "watch"
          :companion -> "companion"
        end,
        track_http_command: fn st, _cmd -> st end,
        simulator_settings: fn _st -> %{} end
      }

      followups = [
        %{
          "package" => "companion-protocol",
          "message" => "RequestWeather CurrentLocation",
          "message_value" => %{
            "ctor" => "RequestWeather",
            "args" => [%{"ctor" => "CurrentLocation", "args" => []}]
          },
          "command" => %{"to" => "companion", "direction" => "watch_to_phone", "from" => "watch"}
        }
      ]

      updated =
        RuntimeFollowups.apply_after_step(state, :watch, "init", "init", followups, ctx)

      assert [%{"message" => "RequestWeather CurrentLocation", "to" => "companion", "from" => "watch"}] =
               ProtocolRx.inline_protocol_deliveries(updated)
    end
  end

  describe "async http enqueue" do
    test "tracks http command without debugger timeline row" do
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

      refute Enum.any?(Map.get(updated, :debugger_timeline, []), fn row ->
               row.type == "http" or row.message_source in ["http", "http_pending"]
             end)

      assert [%{"followup_message" => "CatalogReceived"}] =
               Map.get(updated, :pending_http_followups) ||
                 Map.get(updated, "pending_http_followups")
    end
  end

  describe "apply_http_executor_result/8" do
    test "CatalogReceived Ok chains SvgReceived into async http pending" do
      previous_async_http = Application.get_env(:ide, :debugger_async_http_followups)
      Application.put_env(:ide, :debugger_async_http_followups, true)

      on_exit(fn ->
        if is_nil(previous_async_http) do
          Application.delete_env(:ide, :debugger_async_http_followups)
        else
          Application.put_env(:ide, :debugger_async_http_followups, previous_async_http)
        end
      end)

      state = %{
        phone: RuntimeSurfaces.default_phone(),
        companion: RuntimeSurfaces.default_companion(),
        watch: RuntimeSurfaces.default_watch()
      }

      inner_ctx = %{
        append_event: fn s, _, _ -> s end,
        append_debugger_event: &AgentSession.append_debugger_event/6,
        apply_step_once: fn s, _, _, _, _, _ -> s end,
        source_root_for_target: fn :phone -> "phone" end,
        track_http_command: &RuntimeFollowups.track_http_command/2,
        simulator_settings: fn _ -> %{} end
      }

      ctx = %{
        append_event: fn st, _, _ -> st end,
        append_debugger_event: &AgentSession.append_debugger_event/6,
        apply_step_once: fn st, target, message, message_value, source, _trigger ->
          st
          |> AgentSession.append_debugger_event("update", target, message, source, message_value)
          |> then(fn next ->
            RuntimeFollowups.apply_after_step(
              next,
              target,
              message,
              source,
              catalog_followups_for_message(message),
              inner_ctx
            )
          end)
        end,
        source_root_for_target: fn :phone -> "phone" end,
        track_http_command: &RuntimeFollowups.track_http_command/2,
        simulator_settings: fn _ -> %{} end
      }

      catalog_cmd = %{
        "method" => "GET",
        "url" => "https://raw.githubusercontent.com/lil-lab/kilogram/main/dataset/dense10.json"
      }

      result = {
        :ok,
        %{
          "message_value" => %{"ctor" => "Ok", "args" => [~s({"page1-0": {}})]},
          "response" => %{"status" => 200, "body" => ~s({"page1-0": {}})}
        }
      }

      updated =
        RuntimeFollowups.apply_http_executor_result(
          state,
          :phone,
          "phone",
          "elm/http",
          catalog_cmd,
          "CatalogReceived",
          result,
          ctx
        )

      assert Enum.any?(updated.debugger_timeline || [], fn row ->
               row.type == "update" and
                 String.contains?(to_string(row.message || ""), "CatalogReceived")
             end)

      assert [%{"followup_message" => "SvgReceived"}] = PendingHttpFollowups.pending(updated)
    end
  end

  defp catalog_followups_for_message("CatalogReceived") do
    [
      %{
        "package" => "elm/http",
        "message" => "SvgReceived",
        "command" => %{
          "method" => "GET",
          "url" =>
            "https://raw.githubusercontent.com/lil-lab/kilogram/main/dataset/tangrams-svg/page1%2D0.svg"
        }
      }
    ]
  end

  defp catalog_followups_for_message(_), do: []

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
