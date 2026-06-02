defmodule Ide.Debugger.RuntimeEventPayloadTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "start_session and step append typed runtime event payloads" do
    slug = "runtime_event_payload_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} =
             Debugger.start_session(slug, %{
               "watch_profile_id" => "basalt",
               "launch_reason" => "LaunchUser"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               "rel_path" => "watch/src/Main.elm",
               "source" => File.read!("priv/project_templates/watch_demo_health/src/Main.elm"),
               "reason" => "runtime_event_payload_test"
             })

    assert {:ok, _} =
             Debugger.step(slug, %{"target" => "watch", "message" => "Tick", "count" => 1})

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 200)

    start_event = Enum.find(st.events, &(&1.type == "debugger.start"))
    update_event = Enum.find(st.events, &(&1.type == "debugger.update_in"))

    assert start_event.payload.launch_reason == "LaunchUser"
    assert start_event.payload.watch_profile_id == "basalt"

    assert update_event.payload.target == "watch"
    assert update_event.payload.message == "Tick"
  end

  test "reload and ingest_elmc_check produce expected event payload shapes" do
    slug = "runtime_event_reload_elmc_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :ok,
               checked_path: "/tmp/ws",
               error_count: 0,
               warning_count: 1
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    elmc_event = Enum.find(st.events, &(&1.type == "debugger.elmc_check"))

    assert elmc_event.payload.status == "ok"
    assert elmc_event.payload.checked_path == "/tmp/ws"
    assert elmc_event.payload.warning_count == 1
  end

  test "reload uses HotReloadEventPayload contract fields" do
    slug = "runtime_event_hot_reload_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.reload(slug, %{
               "rel_path" => "src/Main.elm",
               "source_root" => "watch",
               "source" => "module Main exposing (..)\ninit _ = ( {}, Cmd.none )\n",
               "reason" => "contract_test"
             })

    reload_event = Enum.find(state.events, &(&1.type == "debugger.reload"))
    assert reload_event.payload.reason == "contract_test"
    assert reload_event.payload.rel_path == "src/Main.elm"
  end
end
