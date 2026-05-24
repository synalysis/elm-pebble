defmodule Ide.Mcp.WeatherWatchfaceShowcaseTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Mcp.Tools
  alias Ide.Projects
  alias Ide.Resources.ResourceStore

  test "debugger render_tree includes vector draw ops for weather watchface runtime output" do
    slug = "weather-render-#{System.unique_integer([:positive])}"

    assert {:ok, _project} =
             Projects.create_project(%{
               "name" => "Weather Render",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-weather-animated"
             })

    assert {:ok, _state} = Debugger.start_session(slug)

    :ok =
      Agent.get_and_update(Debugger, fn store ->
        next =
          store
          |> Map.get(slug)
          |> put_in([:watch, :model, "runtime_view_output"], [
            %{"kind" => "clear", "color" => 255},
            %{
              "kind" => "vector_at",
              "vector_id" => 1,
              "x" => 48,
              "y" => 102,
              "source" => %{
                "call" => "Ui.drawVectorAt",
                "path" => "watch/src/Main.elm",
                "line" => 146
              }
            }
          ])

        {:ok, Map.put(store, slug, next)}
      end)

    assert {:ok, render_tree} =
             Tools.call(
               "debugger.render_tree",
               %{"slug" => slug, "target" => "watch", "include_tree" => true},
               [:read]
             )

    assert render_tree.target == "watch"
    assert render_tree.root_type == "windowStack"

    assert Enum.any?(render_tree.nodes, &(&1.type == "drawVectorAt"))

    vector_node = Enum.find(render_tree.nodes, &(&1.type == "drawVectorAt"))
    assert vector_node.path =~ "0."
    assert vector_node.source["call"] == "Ui.drawVectorAt"
    assert vector_node.source["path"] == "watch/src/Main.elm"
  end

  test "weather animated template accepts imported vector sequence and regenerates Resources module" do
    slug = "weather-showcase-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Weather Showcase",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-weather-animated"
             })

    frame_a =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><circle cx="10" cy="10" r="6" fill="chromeYellow"/></svg>)

    frame_b =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><circle cx="10" cy="10" r="4" fill="chromeYellow"/></svg>)

    assert {:ok, imported} =
             Tools.call(
               "resources.vectors.import_sequence",
               %{
                 "slug" => slug,
                 "frames" => [frame_a, frame_b],
                 "name" => "ClearToCloudy.pdc",
                 "frame_duration_ms" => 100
               },
               [:edit]
             )

    assert imported["entry"]["kind"] == "sequence"
    assert imported["entry"]["frames"] == 2

    assert {:ok, listed} = Tools.call("resources.vectors.list", %{"slug" => slug}, [:read])
    assert Enum.any?(listed["entries"], &(&1["kind"] == "sequence"))

    workspace = Projects.project_workspace_path(project)
    generated = Path.join(workspace, ResourceStore.generated_module_rel_path())
    source = File.read!(generated)
    assert String.contains?(source, "ClearToCloudy")
    assert String.contains?(source, "type VectorGraphic")
  end

  test "debugger weather watchface renders fog vector id from project manifest" do
    slug = "weather-fog-vector-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Weather Fog Vector",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-weather-animated"
             })

    workspace = Projects.project_workspace_path(project)
    watch_source = File.read!(Path.join(workspace, "watch/src/Main.elm"))
    phone_source = File.read!(Path.join(workspace, "phone/src/CompanionApp.elm"))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_source,
               source_root: "phone",
               reason: "weather_fog_vector_companion"
             })

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "weather_fog_vector_watch"
             })

    assert {:ok, _state} =
             Debugger.set_simulator_settings(slug, %{
               "weather" => %{"temperatureC" => 18, "condition" => "fog"}
             })

    assert {:ok, state} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "timer",
               message: "EnableWeatherTransitions"
             })

    view_output = get_in(state, [:watch, :model, "runtime_view_output"]) || []

    assert Enum.any?(view_output, fn row ->
             row["kind"] == "vector_at" and row["vector_id"] == 3
           end)
  end
end
