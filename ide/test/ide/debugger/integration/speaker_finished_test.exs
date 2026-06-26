defmodule Ide.Debugger.SpeakerFinishedIntegrationTest do
  use Ide.DataCase, async: false

  @moduletag :integration
  @moduletag :slow

  alias Ide.Debugger
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.ContractTestSupport
  alias Ide.Debugger.WatchSubscriptionContracts
  alias Ide.Projects

  setup tags do
    :ok = AgentStore.ensure_started(Ide.Debugger)
    Ide.TestSupport.DebuggerSessionLock.setup(timeout: tags[:timeout] || 120_000)
    :ok
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "speaker_finished_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  @tag timeout: 120_000
  test "speaker finished subscription applies platform payload from parsed contract" do
    slug = "speaker-finished-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "SpeakerFinished",
               "slug" => slug,
               "template" => "watch-demo-speaker"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    {:ok, main_elm} = Projects.read_source_file(project, "watch", "src/Main.elm")
    {:ok, resources_elm} = Projects.read_source_file(project, "watch", "src/Pebble/Speaker/Resources.elm")

    assert {:ok, _} = Debugger.start_session(slug)

    for {rel_path, source} <- [
          {"src/Pebble/Speaker/Resources.elm", resources_elm},
          {"src/Main.elm", main_elm}
        ] do
      assert {:ok, _} =
               Debugger.reload(slug, %{
                 rel_path: rel_path,
                 source: source,
                 reason: "speaker_finished_test",
                 source_root: "watch"
               })
    end

    assert {:ok, state} = Debugger.snapshot(slug)

    contract =
      get_in(state, [:watch, :shell, "debugger_contract"]) ||
        ContractTestSupport.analyze_contract!(main_elm, "Main.elm")

    trigger =
      WatchSubscriptionContracts.trigger_for_contract(
        contract,
        WatchSubscriptionContracts.speaker_finished()
      )

    message =
      WatchSubscriptionContracts.message_for_contract(
        contract,
        WatchSubscriptionContracts.speaker_finished()
      )

    assert trigger
    assert message == "SpeakerFinished"

    assert {:ok, after_finished} =
             Debugger.inject_trigger(slug, %{
               trigger: trigger,
               target: "watch",
               message: message
             })

    assert Enum.any?(after_finished.debugger_timeline || [], fn row ->
             String.contains?(row.message || "", "SpeakerFinished")
           end)

    view_text = Jason.encode!(get_in(after_finished, [:watch, :view_tree]) || %{})
    assert String.contains?(view_text, "Done")
    refute String.contains?(view_text, "Waiting")
  end
end
