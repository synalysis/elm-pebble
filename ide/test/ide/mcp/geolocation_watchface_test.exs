defmodule Ide.Mcp.GeolocationWatchfaceTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Projects

  test "geolocation template delivers simulator coordinates to watch runtime model" do
    slug = "geolocation-coords-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Geolocation Coords",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "companion-demo-geolocation"
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
               reason: "geolocation_coords_phone"
             })

    assert {:ok, _st} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               source_root: "watch",
               reason: "geolocation_coords_watch"
             })

    assert {:ok, st} =
             Debugger.set_simulator_settings(slug, %{
               "latitude" => 48.137154,
               "longitude" => 11.576124,
               "accuracy" => 25.0
             })

    watch_runtime_model = get_in(st, [:watch, :model, "runtime_model"]) || %{}

    assert watch_runtime_model["latitudeE6"] == 48_137_154
    assert watch_runtime_model["longitudeE6"] == 11_576_124
    assert watch_runtime_model["accuracyM"] == 25

    refute Enum.any?(st.debugger_timeline, fn row ->
             row.target == "watch" and row.message =~ "ProvidePosition 88 88 88"
           end)
  end
end
