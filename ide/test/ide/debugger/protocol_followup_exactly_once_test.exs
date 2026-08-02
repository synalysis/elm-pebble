defmodule Ide.Debugger.ProtocolFollowupExactlyOnceTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ProtocolContexts
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.StepDepth

  defp from_phone_introspect do
    %{
      "subscription_calls" => [
        %{
          "event_kind" => "on_phone_to_watch",
          "callback_constructor" => "FromPhone"
        }
      ]
    }
  end

  defp ready_watch_state(introspect \\ from_phone_introspect()) do
    %{
      watch: %{
        model: %{
          "debugger_init_complete" => true,
          "runtime_execution_mode" => "runtime_executed",
          "runtime_model" => %{}
        },
        shell: %{"debugger_contract" => introspect},
        view_tree: %{"type" => "windowStack"}
      }
    }
    |> ProtocolRx.mark_init_complete(:watch)
  end

  defp events_ctx do
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
  end

  defp build_rx_ctx(steps) do
    %{
      append_event: fn st, _type, _payload -> st end,
      append_debugger_event: fn st, type, target, msg, src, _value ->
        :ets.insert(steps, {type, target, msg, src})
        st
      end,
      append_runtime_exec_event_for_target: fn st, _target, _meta -> st end,
      source_root_for_target: fn :watch -> "watch" end,
      introspect_for: fn st, target ->
        st |> Map.get(target, %{}) |> RuntimeArtifacts.introspect()
      end,
      introspect_cmd_calls: fn ei, key -> Map.get(ei, key, []) end,
      apply_step_once: fn st, :watch, message, _value, source, trigger ->
        :ets.insert(steps, {"update", "watch", message, source, trigger})
        put_in(st, [:watch, :model, "runtime_model", "last_protocol_message"], message)
      end,
      refresh_runtime_fingerprints: fn model, _rm, _vt -> model end,
      protocol_events_ctx: fn -> events_ctx() end,
      runtime_ready_for_delivery?: &ProtocolRx.runtime_ready_for_delivery?/2
    }
  end

  defp followup_ctx(steps) do
    %{
      append_event: fn st, _type, _payload -> st end,
      append_debugger_event: fn st, _type, _target, _msg, _src, _value -> st end,
      apply_step_once: fn st, target, message, value, source, trigger ->
        :ets.insert(steps, {target, message, value, source, trigger})
        st
      end,
      track_http_command: fn st, _cmd -> st end,
      simulator_settings: fn _st -> %{} end,
      source_root_for_target: fn
        :watch -> "watch"
        :companion -> "phone"
        :phone -> "phone"
      end,
      protocol_rx_ctx: fn -> build_rx_ctx(steps) end
    }
  end

  defp protocol_followup_row(message, message_value) do
    %{
      "package" => "companion-protocol",
      "message" => message,
      "message_value" => message_value,
      "command" => %{
        "kind" => "protocol",
        "to" => "watch",
        "from" => "companion",
        "direction" => "phone_to_watch"
      }
    }
  end

  test "one companion-protocol followup enqueues exactly one inline delivery" do
    steps = :ets.new(:protocol_once_steps, [:bag, :private])
    ctx = followup_ctx(steps)
    state = ready_watch_state()

    row =
      protocol_followup_row(
        "ProvideTimezone",
        %{"ctor" => "ProvideTimezone", "args" => [60]}
      )

    queued =
      RuntimeFollowups.apply_after_step(state, :companion, "CurrentTime", "init", [row], ctx)

    assert :ets.tab2list(steps) == []
    assert length(ProtocolRx.inline_protocol_deliveries(queued)) == 1
  end

  test "flush applies exactly one watch update for phone_to_watch runtime followup" do
    steps = :ets.new(:protocol_once_flush, [:bag, :private])
    rx_ctx = build_rx_ctx(steps)
    ctx = followup_ctx(steps)
    state = ready_watch_state()

    row =
      protocol_followup_row(
        "ProvideTimezone",
        %{"ctor" => "ProvideTimezone", "args" => [60]}
      )

    queued =
      RuntimeFollowups.apply_after_step(state, :companion, "CurrentTime", "init", [row], ctx)

    refute get_in(queued, [:watch, :model, "runtime_model", "last_protocol_message"])

    flushed = ProtocolRx.flush_inline_protocol_deliveries(queued, rx_ctx)

  assert get_in(flushed, [:watch, :model, "runtime_model", "last_protocol_message"]) ==
           "FromPhone (ProvideTimezone 60)"

    updates =
      :ets.tab2list(steps)
      |> Enum.filter(fn
        {"update", "watch", _message, _source, _trigger} -> true
        _ -> false
      end)

    assert length(updates) == 1
  end

  test "async protocol drain delivers phone_to_watch followup exactly once" do
    previous = Application.get_env(:ide, :debugger_async_protocol_delivery)
    Application.put_env(:ide, :debugger_async_protocol_delivery, true)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ide, :debugger_async_protocol_delivery)
      else
        Application.put_env(:ide, :debugger_async_protocol_delivery, previous)
      end
    end)

    steps = :ets.new(:protocol_once_async, [:bag, :private])
    rx_ctx = build_rx_ctx(steps)
    ctx = followup_ctx(steps)
    state = ready_watch_state()

    row =
      protocol_followup_row(
        "ProvideTimezone",
        %{"ctor" => "ProvideTimezone", "args" => [60]}
      )

    queued =
      RuntimeFollowups.apply_after_step(state, :companion, "CurrentTime", "init", [row], ctx)

    # Async mode parks deliveries on the pending queue instead of applying inline.
    flushed = ProtocolRx.flush_inline_protocol_deliveries(queued, rx_ctx)

    pending = Ide.Debugger.PendingProtocolDelivery.pending(flushed)
    assert length(pending) == 1

    delivered =
      Enum.reduce(pending, flushed, fn item, acc ->
        payload = Map.fetch!(item, "payload")
        ProtocolRx.deliver_payload(acc, payload, rx_ctx)
      end)

    updates =
      :ets.tab2list(steps)
      |> Enum.filter(fn
        {"update", "watch", message, _source, _trigger} ->
          String.contains?(to_string(message), "ProvideTimezone")

        _ ->
          false
      end)

    assert length(updates) == 1
    assert get_in(delivered, [:watch, :model, "runtime_model", "last_protocol_message"]) ==
             "FromPhone (ProvideTimezone 60)"
  end

  test "second flush on empty queue does not duplicate watch updates" do
    steps = :ets.new(:protocol_once_double_flush, [:bag, :private])
    rx_ctx = build_rx_ctx(steps)
    ctx = followup_ctx(steps)
    state = ready_watch_state()

    row =
      protocol_followup_row(
        "ProvideWeather",
        %{
          "ctor" => "ProvideWeather",
          "args" => [
            %{"ctor" => "Celsius", "args" => [210]},
            %{"ctor" => "Clear", "args" => []},
            0,
            0,
            0
          ]
        }
      )

    queued =
      RuntimeFollowups.apply_after_step(state, :companion, "GotWeather", "init", [row], ctx)

    once = ProtocolRx.flush_inline_protocol_deliveries(queued, rx_ctx)
    twice = ProtocolRx.flush_inline_protocol_deliveries(once, rx_ctx)

    assert once == twice

    updates =
      :ets.tab2list(steps)
      |> Enum.filter(fn
        {"update", "watch", message, _source, _trigger} ->
          String.contains?(message, "ProvideWeather")

        _ ->
          false
      end)

    assert length(updates) == 1
  end

  test "nested step depth defers flush until outermost step completes" do
    steps = :ets.new(:protocol_once_nested, [:bag, :private])
    rx_ctx = build_rx_ctx(steps)

    payload = %{
      "from" => "companion",
      "to" => "watch",
      "message" => "ProvideTimezone",
      "message_value" => %{"ctor" => "ProvideTimezone", "args" => [120]},
      "trigger" => "runtime_followup",
      "message_source" => "runtime_followup"
    }

    state =
      ready_watch_state()
      |> ProtocolRx.enqueue_inline_protocol_delivery(payload)

    StepDepth.enter()
    StepDepth.enter()

    deferred = ProtocolRx.flush_inline_protocol_deliveries(state, rx_ctx)
    assert length(ProtocolRx.inline_protocol_deliveries(deferred)) == 1
    refute get_in(deferred, [:watch, :model, "runtime_model", "last_protocol_message"])

    flushed =
      deferred
      |> then(fn st ->
        _ = StepDepth.leave()
        ProtocolRx.flush_inline_protocol_deliveries(st, rx_ctx)
      end)

    assert get_in(flushed, [:watch, :model, "runtime_model", "last_protocol_message"]) ==
             "FromPhone (ProvideTimezone 120)"

    assert ProtocolRx.inline_protocol_deliveries(flushed) == []
  end
end
