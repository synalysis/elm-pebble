defmodule Ide.Debugger.ProtocolDeliveryOrderTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.AppMessageQueue
  alias Ide.Debugger.ProtocolContexts
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeArtifacts

  test "runtime_ready_for_delivery? requires init to complete" do
    state = %{
      companion: %{
        model: %{
          "elm_introspect" => %{"module" => "CompanionApp"}
        },
        shell: %{"elm_introspect" => %{"module" => "CompanionApp"}}
      }
    }

    refute ProtocolRx.runtime_ready_for_delivery?(state, :companion)

    ready = ProtocolRx.mark_init_complete(state, :companion)
    assert ProtocolRx.runtime_ready_for_delivery?(ready, :companion)
  end

  test "inbound AppMessage is queued until recipient init completes" do
    state = %{
      companion: %{
        model: %{"elm_introspect" => %{}},
        shell: %{"elm_introspect" => %{}}
      },
      app_message_queues: AppMessageQueue.empty()
    }

    payload = %{
      "from" => "watch",
      "to" => "companion",
      "message" => "RequestFigure",
      "message_value" => %{"ctor" => "RequestFigure", "args" => []}
    }

    rx_ctx = %{
      append_event: fn st, _type, _payload -> st end,
      append_debugger_event: fn st, _type, _target, _msg, _src -> st end,
      append_runtime_exec_event_for_target: fn st, _target, _meta -> st end,
      source_root_for_target: fn :companion -> "phone" end,
      introspect_for: fn st, target ->
        st |> Map.get(target, %{}) |> RuntimeArtifacts.introspect()
      end,
      introspect_cmd_calls: fn _ei, _key -> [] end,
      apply_step_once: fn st, _t, _m, _v, _s, _tr -> st end,
      refresh_runtime_fingerprints: fn model, _rm, _vt -> model end,
      protocol_events_ctx: fn -> %{} end,
      runtime_ready_for_delivery?: &ProtocolRx.runtime_ready_for_delivery?/2
    }

    queued = ProtocolRx.apply_state_effects(state, [%{type: "debugger.protocol_rx", payload: payload}], rx_ctx)

    assert AppMessageQueue.pending?(queued, :companion)
    refute ProtocolRx.runtime_ready_for_delivery?(queued, :companion)
  end

  test "subscription-mapped AppMessage delivery records one debugger timeline row" do
    introspect = %{
      "subscription_calls" => [
        %{
          "event_kind" => "on_phone_to_watch",
          "callback_constructor" => "FromPhone"
        }
      ]
    }

    state =
      %{
        watch: %{
          model: %{"debugger_init_complete" => true},
          shell: %{"elm_introspect" => introspect},
          view_tree: %{"type" => "windowStack"}
        }
      }
      |> ProtocolRx.mark_init_complete(:watch)

    payload = %{
      "from" => "phone",
      "to" => "watch",
      "message" => "ProvideFigure 0",
      "message_value" => %{"ctor" => "ProvideFigure", "args" => [0]}
    }

    timeline_log = :ets.new(:"timeline_log_#{System.unique_integer([:positive])}", [:bag])

    events_ctx =
      ProtocolContexts.events_ctx(%{
        introspect_for: fn st, target ->
          st |> Map.get(target, %{}) |> RuntimeArtifacts.introspect()
        end,
        simulator_settings_from_state: fn _st -> %{} end,
        session_key_from_state: fn _st -> "test-project" end,
        surface_app_model: fn st, target ->
          st |> Map.get(target, %{}) |> Map.get(:model, %{})
        end
      })

    rx_ctx = %{
      append_event: fn st, _type, _payload -> st end,
      append_debugger_event: fn st, type, target, msg, src ->
        :ets.insert(timeline_log, {type, target, msg, src})
        st
      end,
      append_runtime_exec_event_for_target: fn st, _target, _meta -> st end,
      source_root_for_target: fn :watch -> "watch" end,
      introspect_for: fn st, target ->
        st |> Map.get(target, %{}) |> RuntimeArtifacts.introspect()
      end,
      introspect_cmd_calls: fn ei, key -> Map.get(ei, key, []) end,
      apply_step_once: fn st, _target, message, _value, _source, _trigger ->
        :ets.insert(timeline_log, {"update", "watch", message, "protocol_rx"})
        st
      end,
      refresh_runtime_fingerprints: fn model, _rm, _vt -> model end,
      protocol_events_ctx: fn -> events_ctx end,
      runtime_ready_for_delivery?: &ProtocolRx.runtime_ready_for_delivery?/2
    }

    _delivered = ProtocolRx.deliver_payload(state, payload, rx_ctx)

    rows = :ets.tab2list(timeline_log)
    assert rows == [{"update", "watch", "FromPhone (ProvideFigure 0)", "protocol_rx"}]
  end
end
