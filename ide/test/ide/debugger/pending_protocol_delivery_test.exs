defmodule Ide.Debugger.PendingProtocolDeliveryTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.PendingProtocolDelivery
  alias Ide.Debugger.ProtocolContexts
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.SessionDefaults

  test "enqueue stores payload for async drain" do
    state = %{
      companion: %{}
    }

    payload = %{"from" => "watch", "to" => "companion", "message" => "Ping"}

    next = PendingProtocolDelivery.enqueue(state, :companion, payload)

    assert [%{"recipient" => "companion", "payload" => ^payload}] =
             PendingProtocolDelivery.pending(next)
  end

  test "concurrent drains deliver each pending AppMessage exactly once" do
    previous = Application.get_env(:ide, :debugger_async_protocol_delivery)
    Application.put_env(:ide, :debugger_async_protocol_delivery, true)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ide, :debugger_async_protocol_delivery)
      else
        Application.put_env(:ide, :debugger_async_protocol_delivery, previous)
      end
    end)

    slug = "protocol-drain-race-#{System.unique_integer([:positive])}"
    steps = :ets.new(:protocol_drain_race_steps, [:bag, :public])

    payload = %{
      "from" => "companion",
      "to" => "watch",
      "message" => "ProvideTimezone",
      "message_value" => %{"ctor" => "ProvideTimezone", "args" => [60]},
      "trigger" => "runtime_cmd",
      "message_source" => "runtime_cmd"
    }

    state =
      slug
      |> SessionDefaults.default_state()
      |> put_in([:watch, :model], %{
        "debugger_init_complete" => true,
        "runtime_execution_mode" => "runtime_executed",
        "runtime_model" => %{}
      })
      |> put_in([:watch, :shell], %{
        "debugger_contract" => %{
          "subscription_calls" => [
            %{
              "event_kind" => "on_phone_to_watch",
              "callback_constructor" => "FromPhone"
            }
          ]
        }
      })
      |> put_in([:watch, :view_tree], %{"type" => "windowStack"})
      |> ProtocolRx.mark_init_complete(:watch)
      |> PendingProtocolDelivery.enqueue(:watch, payload)

    _ = AgentStore.put(slug, state)

    rx_ctx = %{
      append_event: fn st, _type, _payload -> st end,
      append_debugger_event: fn st, type, target, msg, src, _value ->
        :ets.insert(steps, {type, target, msg, src})
        st
      end,
      append_runtime_exec_event_for_target: fn st, _target, _meta -> st end,
      source_root_for_target: fn
        :watch -> "watch"
        :companion -> "phone"
        :phone -> "phone"
      end,
      introspect_for: fn st, target ->
        st |> Map.get(target, %{}) |> RuntimeArtifacts.introspect()
      end,
      introspect_cmd_calls: fn ei, key -> Map.get(ei, key, []) end,
      apply_step_once: fn st, :watch, message, _value, source, trigger ->
        :ets.insert(steps, {"update", "watch", message, source, trigger})
        put_in(st, [:watch, :model, "runtime_model", "last_protocol_message"], message)
      end,
      refresh_runtime_fingerprints: fn model, _rm, _vt -> model end,
      protocol_events_ctx: fn ->
        ProtocolContexts.events_ctx(%{
          introspect_for: fn st, target ->
            st |> Map.get(target, %{}) |> RuntimeArtifacts.introspect()
          end,
          simulator_settings_from_state: fn _st -> %{} end,
          session_key_from_state: fn _st -> slug end,
          surface_app_model: fn st, target ->
            st |> Map.get(target, %{}) |> Map.get(:model, %{})
          end
        })
      end,
      runtime_ready_for_delivery?: &ProtocolRx.runtime_ready_for_delivery?/2
    }

    # Reproduce the live bootstrap race: sync drain (LiveView) overlapping an
    # async-style second drain over the same pending queue.
    tasks =
      for _ <- 1..2 do
        Task.async(fn -> PendingProtocolDelivery.drain_pending_sync(slug, rx_ctx) end)
      end

    Enum.each(tasks, &Task.await(&1, 30_000))

    updates =
      :ets.tab2list(steps)
      |> Enum.filter(fn
        {"update", "watch", message, _source, _trigger} ->
          String.contains?(to_string(message), "ProvideTimezone")

        _ ->
          false
      end)

    assert length(updates) == 1,
           "concurrent drains must not double-deliver FromPhone: #{inspect(updates)}"

    assert PendingProtocolDelivery.pending(AgentStore.fetch(slug)) == []
  end
end
