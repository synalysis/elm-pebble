defmodule Ide.Debugger.RuntimeHubTaskFollowupTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Projects
  alias Ide.Test.DebuggerTimelineAssertions, as: TimelineAssertions

  @tag timeout: 300_000
  test "hub wiring delivers CurrentTime once after companion bridge geolocation chain" do
    previous_async_protocol = Application.get_env(:ide, :debugger_async_protocol_delivery)
    Application.put_env(:ide, :debugger_async_protocol_delivery, true)

    on_exit(fn ->
      if is_nil(previous_async_protocol) do
        Application.delete_env(:ide, :debugger_async_protocol_delivery)
      else
        Application.put_env(:ide, :debugger_async_protocol_delivery, previous_async_protocol)
      end
    end)

    slug = "hub-task-followup-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES Hub Task",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    root = Projects.project_workspace_path(project)
    watch_source = File.read!(Path.join([root, "watch", "src", "Main.elm"]))
    phone_source = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "hub_task_watch"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "hub_task_phone"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "latitude" => "48.0",
               "longitude" => "10.0",
               "accuracy" => "25.0"
             })

    assert :ok = RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 400)

    timeline = state.debugger_timeline || []

    current_time_rows =
      Enum.filter(timeline, fn row ->
        row.target in ["phone", "companion"] and
          row.type == "update" and
          is_binary(row.message) and String.starts_with?(row.message, "CurrentTime")
      end)

    assert current_time_rows != [],
           "expected CurrentTime on companion after geolocation bridge chain"

    bridge_current_time =
      Enum.filter(current_time_rows, fn row ->
        row.message_source in ["companion_bridge_command", "runtime_followup"]
      end)

    assert bridge_current_time != [],
           "CurrentTime must arrive via bridge/runtime followup, not only simulator settings: #{inspect(current_time_rows, limit: 5)}"

    TimelineAssertions.refute_consecutive_duplicate_updates(timeline)

    _ = Projects.delete_project(project)
  end
end
