defmodule Ide.Debugger.PokeBattlePreviewStepsTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @minute_batch_source File.read!(
                         Path.join([
                           "priv",
                           "project_templates",
                           "watchface_poke_battle",
                           "src",
                           "Main.elm"
                         ])
                       )
                       |> String.replace(
                         "MinuteChanged _ ->\n            ( model, refreshSteps model )",
                         "MinuteChanged _ ->\n            ( model, Cmd.batch [ refreshSteps model, Time.currentDateTime CurrentDateTime ] )"
                       )

  test "watch preview stays drawable through init device followups and MinuteChanged" do
    slug = "poke-preview-steps-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Poke preview steps",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-poke-battle"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(project.slug)

    assert {:ok, _} =
             Debugger.reload(project.slug, %{
               rel_path: "src/Main.elm",
               source: @minute_batch_source,
               reason: "poke_preview_steps",
               source_root: "watch"
             })

    assert {:ok, state} = Debugger.snapshot(project.slug)

    execution_model =
      state.watch
      |> Map.get(:model, %{})
      |> Map.merge(Map.get(state.watch, :shell, %{}))

    assert Ide.Debugger.RuntimeArtifacts.versioned_core_ir?(execution_model),
           "reload must attach Core IR before init"

    model = get_in(state, [:watch, :model, "runtime_model"]) || %{}
    assert Map.has_key?(model, "player"), "init model missing player: #{inspect(Map.keys(model))}"
    assert Map.has_key?(model, "layout"), "init model missing layout"

    view_type = get_in(state, [:watch, :view_tree, "type"])
    refute view_type == "previewUnavailable", "init preview unavailable: #{inspect(state.watch.view_tree)}"

    for message <- [
          "CurrentDateTime {\"minute\":53,\"hour\":9,\"day\":31,\"month\":5,\"year\":2026,\"second\":52,\"utcOffsetMinutes\":120,\"dayOfWeek\":{\"ctor\":\"Sunday\",\"args\":[]}}",
          "ClockStyle24h True",
          "BatteryLevelChanged 88",
          "HealthSupported True",
          "MinuteChanged 54"
        ] do
      assert {:ok, state} = Debugger.step(project.slug, %{target: "watch", message: message, count: 1})

      model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

      assert Map.has_key?(model, "player"),
             "after #{message} model missing player: #{inspect(Map.keys(model))}"

      view_type = get_in(state, [:watch, :view_tree, "type"])

      refute view_type == "previewUnavailable",
             "after #{message} preview unavailable; view_output=#{inspect(get_in(state, [:watch, :model, "runtime_view_output"]))}"
    end

    rows =
      state
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(&(&1.target == "watch" and &1.type == "update"))

    assert Enum.any?(rows, &(String.contains?(&1.message || "", "CurrentDateTime")))
  end
end
