defmodule Ide.Debugger.CompanionBridgeRuntimeTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{
    CompanionBridgeContext,
    CompileContract,
    InitSurfaceEffects,
    RuntimeSurfaces
  }

  @timeline_init_elm """
  module TimelineInit exposing (..)

  import Pebble.Companion.Timeline as Timeline

  type Msg = GotToken (Result String String)

  init _ =
      ( {}, Timeline.getToken GotToken )
  """

  test "apply_companion_bridge_commands on phone applies GotToken from timeline getToken init" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@timeline_init_elm, "TimelineInit.elm")

    token = "init-bridge-token"

    state = %{
      simulator_settings: %{"companion_timeline_token" => token},
      phone:
        RuntimeSurfaces.default_phone()
        |> Map.put(:shell, %{"elm_introspect" => ei})
    }

    steps = :ets.new(:steps, [:set, :private])

    bridge_ctx =
      CompanionBridgeContext.build(%{
        introspect_for: fn st, target ->
          st |> Map.get(target, %{}) |> Map.get(:shell, %{}) |> Map.get("elm_introspect", %{})
        end,
        append_event: fn st, _type, _payload -> st end,
        apply_step_once: fn st, target, message, value, source, trigger ->
          :ets.insert(steps, {target, message, value, source, trigger})
          st
        end,
        settings: fn st -> Map.get(st, :simulator_settings, %{}) end
      })

    init_ctx = %{
      append_event: fn st, _type, _payload -> st end,
      apply_step_once: Map.fetch!(bridge_ctx, :apply_step),
      apply_subscription_ok_response: fn st, _target, _cb, _payload, _source, _trigger -> st end,
      protocol_events_ctx: fn -> %{} end,
      protocol_rx_ctx: fn -> %{} end,
      companion_bridge_ctx: fn -> bridge_ctx end,
      source_root_for_target: fn :phone -> "phone" end
    }

    _next = InitSurfaceEffects.apply_companion_bridge_commands(state, :phone, init_ctx)

    assert [{:phone, "GotToken", message_value, "init_companion_bridge", "init_companion_bridge"}] =
             :ets.tab2list(steps)

    assert %{
             "ctor" => "GotToken",
             "args" => [%{"ctor" => "Ok", "args" => [^token]}]
           } = message_value
  end

  test "apply_followup_rows applies elmx companion bridge followup and skips static init replay" do
    token = "runtime-bridge-token"

    state = %{
      simulator_settings: %{"companion_timeline_token" => token},
      phone: RuntimeSurfaces.default_phone()
    }

    steps = :ets.new(:runtime_bridge_steps, [:set, :private])

    bridge_ctx =
      CompanionBridgeContext.build(%{
        introspect_for: fn _st, _target -> %{} end,
        append_event: fn st, _type, _payload -> st end,
        apply_step_once: fn st, target, message, value, source, trigger ->
          :ets.insert(steps, {target, message, value, source, trigger})
          st
        end,
        settings: fn st -> Map.get(st, :simulator_settings, %{}) end
      })

    followup = %{
      "source" => "companion_bridge_command",
      "package" => "pebble/companion",
      "message" => "GotToken",
      "command" => %{
        "kind" => "cmd.companion.bridge",
        "api" => "timeline",
        "op" => "getToken",
        "callback_constructor" => "GotToken"
      }
    }

    next =
      Ide.Debugger.CompanionBridge.Runtime.apply_followup_rows(
        state,
        :phone,
        "init_companion_bridge",
        [followup],
        bridge_ctx
      )

    assert Ide.Debugger.CompanionBridge.Runtime.runtime_bridge_followups_applied?(
             next,
             :phone
           )

    assert [{:companion, "GotToken", message_value, "init_companion_bridge", "init_companion_bridge"}] =
             :ets.tab2list(steps)

    assert %{"ctor" => "GotToken", "args" => [%{"ctor" => "Ok", "args" => [^token]}]} =
             message_value

    init_ctx = %{
      append_event: fn st, _type, _payload -> st end,
      apply_step_once: Map.fetch!(bridge_ctx, :apply_step),
      apply_subscription_ok_response: fn st, _target, _cb, _payload, _source, _trigger -> st end,
      protocol_events_ctx: fn -> %{} end,
      protocol_rx_ctx: fn -> %{} end,
      companion_bridge_ctx: fn -> bridge_ctx end,
      source_root_for_target: fn :phone -> "phone" end
    }

    after_init =
      InitSurfaceEffects.apply_companion_bridge_commands(next, :phone, init_ctx)

    assert :ets.tab2list(steps) == [
             {:companion, "GotToken", message_value, "init_companion_bridge",
              "init_companion_bridge"}
           ]
    assert after_init == next
  end

  test "maybe_apply_command_responses skips only bridge requests covered by runtime followups" do
    token = "partial-dedup-token"

    state = %{
      simulator_settings: %{
        "companion_timeline_token" => token,
        "battery_level" => 80
      },
      phone: %{
        shell: %{
          "debugger_contract" => %{
            "update_cmd_calls" => [
              %{
                "target" => "Pebble.Companion.Timeline.getToken",
                "name" => "getToken",
                "callback_constructor" => "GotToken",
                "branch_constructor" => "Refresh"
              },
              %{
                "target" => "Pebble.Companion.Battery.status",
                "name" => "status",
                "callback_constructor" => "GotBattery",
                "branch_constructor" => "Refresh"
              }
            ]
          }
        }
      }
    }

    steps = :ets.new(:partial_bridge_steps, [:set, :private])

    bridge_ctx =
      CompanionBridgeContext.build(%{
        introspect_for: fn st, target ->
          st |> Map.get(target, %{}) |> Map.get(:shell, %{}) |> Map.get("debugger_contract", %{})
        end,
        append_event: fn st, _type, _payload -> st end,
        apply_step_once: fn st, target, message, _value, source, trigger ->
          :ets.insert(steps, {target, message, source, trigger})
          st
        end,
        settings: fn st -> Map.get(st, :simulator_settings, %{}) end
      })

    followups = [
      %{
        "source" => "companion_bridge_command",
        "package" => "pebble/companion",
        "message" => "GotToken",
        "command" => %{
          "kind" => "cmd.companion.bridge",
          "api" => "timeline",
          "op" => "getToken",
          "callback_constructor" => "GotToken"
        }
      }
    ]

    _next =
      Ide.Debugger.CompanionBridge.Runtime.maybe_apply_command_responses(
        state,
        :phone,
        "Refresh",
        %{},
        "provided",
        bridge_ctx,
        followups
      )
      |> Ide.Debugger.CompanionBridge.Runtime.flush_deferred_steps(bridge_ctx)

    messages = :ets.tab2list(steps) |> Enum.map(fn {_target, message, _source, _trigger} -> message end)

    refute "GotToken" in messages
    assert Enum.any?(messages, &String.contains?(&1, "FromPhone"))
  end
end
