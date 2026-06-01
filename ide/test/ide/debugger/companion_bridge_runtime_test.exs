defmodule Ide.Debugger.CompanionBridgeRuntimeTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{CompanionBridgeContext, CompileContract, InitSurfaceEffects, RuntimeSurfaces}

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
        deliver_weather_to_watch: fn st -> st end,
        settings: fn st -> Map.get(st, :simulator_settings, %{}) end
      })

    init_ctx = %{
      append_event: fn st, _type, _payload -> st end,
      apply_step_once: Map.fetch!(bridge_ctx, :apply_step),
      apply_device_data_followups: fn st, _target, _msg, _model, _source -> st end,
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
end
