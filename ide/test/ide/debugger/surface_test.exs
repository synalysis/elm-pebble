defmodule Ide.Debugger.SurfaceTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface

  describe "from_map/1 and to_map/1" do
    test "round-trips shell migration" do
      surface =
        Surface.from_map(%{
          model: %{
            "count" => 1,
            "elm_introspect" => %{"module" => "Main"}
          },
          view_tree: %{"type" => "root"},
          last_message: "Tick"
        })

      assert surface.model == %{"count" => 1}
      assert surface.shell["debugger_contract"] == %{"module" => "Main"}
      assert surface.view_tree == %{"type" => "root"}
      assert surface.last_message == "Tick"

      round_trip = surface |> Surface.to_map() |> Surface.from_map()
      assert round_trip.model == surface.model
      assert round_trip.shell == surface.shell
    end
  end

  describe "from_state/2 and put_in_state/3" do
    test "reads and writes typed surfaces on session state" do
      state = %{
        watch: Surface.to_map(Surface.from_map(%{model: %{"status" => "idle"}, shell: %{}})),
        companion: Surface.to_map(Surface.from_map(%{model: %{}, shell: %{}})),
        phone: Surface.to_map(Surface.from_map(%{model: %{}, shell: %{}}))
      }

      assert Surface.app_model(Surface.from_state(state, :watch)) == %{"status" => "idle"}

      updated =
        state
        |> Surface.put_in_state(
          :watch,
          Surface.put_app_model(Surface.from_state(state, :watch), %{"status" => "ready"})
        )

      assert Surface.app_model(Surface.from_state(updated, :watch)) == %{"status" => "ready"}
    end
  end

  describe "execution_model/1" do
    test "merges shell artifacts for introspect lookups" do
      surface = %Surface{
        model: %{"runtime_model" => %{"latitudeE6" => 0}},
        shell: %{"debugger_contract" => %{"module" => "Geo"}}
      }

      execution = Surface.execution_model(surface)

      assert RuntimeArtifacts.introspect(execution)["module"] == "Geo"
      assert execution["runtime_model"] == %{"latitudeE6" => 0}
    end
  end
end
