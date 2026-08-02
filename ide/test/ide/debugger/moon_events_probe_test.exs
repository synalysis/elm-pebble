defmodule Ide.Debugger.MoonEventsProbeTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Projects

  @tag timeout: 300_000
  test "CurrentTime ProvideMoon carries computed rise/set for Munich" do
    previous = Application.get_env(:ide, :debugger_async_protocol_delivery)
    Application.put_env(:ide, :debugger_async_protocol_delivery, true)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ide, :debugger_async_protocol_delivery)
      else
        Application.put_env(:ide, :debugger_async_protocol_delivery, previous)
      end
    end)

    slug = "yes-moon-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "moon",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    root = Projects.project_workspace_path(project)
    watch = File.read!(Path.join([root, "watch", "src", "Main.elm"]))
    phone = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch,
               source_root: "watch",
               reason: "w"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone,
               source_root: "phone",
               reason: "p"
             })

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "latitude" => "48.137154",
               "longitude" => "11.576124",
               "accuracy" => "25.0"
             })

    assert :ok = RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, state} = Debugger.snapshot(slug, event_limit: 400)

    # Location-derived Provides use phaseE6 near the synodic formula (~0.61 today),
    # not the simulator environment stub (900/300/500000).
    location_moons =
      (state.debugger_timeline || [])
      |> Enum.filter(fn row ->
        row.type == "update" and row.target == "watch" and is_binary(row.message) and
          String.match?(row.message, ~r/FromPhone \(ProvideMoon \d+ \d+ \d+\)/) and
          not String.contains?(row.message, "ProvideMoon 900 300") and
          not String.contains?(row.message, "ProvideMoonPhase")
      end)
      |> Enum.map(& &1.message)

    moon_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    assert location_moons != [],
           "expected ProvideMoon from CurrentTime/location snapshot"

    assert Enum.all?(location_moons, fn msg ->
             not String.contains?(msg, "ProvideMoon 0 0")
           end),
           "moonEvents must compute rise/set (not 0 0 sentinel): #{inspect(location_moons)}"

    assert match?(%{"ctor" => "Just", "args" => [_]}, moon_model["moonriseMin"])
    assert match?(%{"ctor" => "Just", "args" => [_]}, moon_model["moonsetMin"])
    assert match?(%{"ctor" => "Just", "args" => [_]}, moon_model["moonPhaseE6"])

    _ = Projects.delete_project(project)
  end
end
