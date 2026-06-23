defmodule Ide.Debugger.InitLightEnableFollowupTest do
  use Ide.DataCase, async: false

  @moduletag :debugger_session

  alias Ide.Debugger
  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Mcp.DebuggerTemplateCorpus
  alias Ide.Projects

  setup do
    Corpus.ensure_compiled_elixir_backend!()
    :ok
  end

  @tag timeout: 180_000
  test "game-2048 init followups do not auto-fire UpPressed from Light.enable" do
    slug = "light-enable-followup-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{project: project}} =
             DebuggerTemplateCorpus.bootstrap_template("game-2048", slug: slug, cleanup: false)

    try do
      assert {:ok, state} = Debugger.snapshot(slug, event_limit: 200)

      update_messages =
        state.debugger_timeline
        |> Enum.filter(&(Map.get(&1, :type) == "update"))
        |> Enum.map(&Map.get(&1, :message))

      refute "UpPressed" in update_messages
      assert get_in(state, [:watch, :model, "runtime_model", "turn"]) == 0
    after
      _ = Projects.delete_project(project)
    end
  end
end
