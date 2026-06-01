defmodule Ide.Debugger.MinuteChangedDateTimeBatchTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.{CompileContract, DeviceData, DeviceDataResponses, CmdCall}
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @poke_main File.read!(
               Path.join([
                 "priv",
                 "project_templates",
                 "watchface_poke_battle",
                 "src",
                 "Main.elm"
               ])
             )

  @minute_batch_source String.replace(
                         @poke_main,
                         "MinuteChanged _ ->\n            ( model, refreshSteps model )",
                         "MinuteChanged _ ->\n            ( model, Cmd.batch [ refreshSteps model, Time.currentDateTime CurrentDateTime ] )"
                       )

  test "debugger contract and step apply CurrentDateTime after MinuteChanged batch" do
    assert {:ok, %{"debugger_contract" => ei}} =
             CompileContract.analyze_source(@minute_batch_source, "Main.elm")

    requests =
      DeviceData.requests_for_message(
        ei,
        %{"healthSupported" => true},
        "MinuteChanged 54",
        message_constructor: fn message ->
          message |> String.split(~r/\s+/, parts: 2) |> List.first()
        end,
        update_cmd_calls_filter: &DeviceDataResponses.filter_update_cmd_calls/2,
        expand_cmd_calls: &CmdCall.expand_helpers/2
      )

    assert Enum.any?(requests, fn req ->
             req.kind == "current_date_time" and req.response_message == "CurrentDateTime"
           end)

    slug = "minute-batch-datetime-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "MinuteBatchDateTime",
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
               reason: "minute_batch_datetime",
               source_root: "watch"
             })

    assert {:ok, state} =
             Debugger.step(project.slug, %{
               target: "watch",
               message: "MinuteChanged 54",
               count: 1
             })

    rows =
      state
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(&(&1.target == "watch" and &1.type == "update"))

    assert Enum.any?(rows, &(String.contains?(&1.message || "", "MinuteChanged")))
    assert Enum.any?(rows, &(String.contains?(&1.message || "", "CurrentDateTime")))
  end
end
