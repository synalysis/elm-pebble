defmodule Ide.Debugger.RuntimeSurfaceMergeTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaceMerge
  alias Ide.Debugger.Types.ElmcSurfaceFields

  test "merge_fields partitions elmc fields into model and shell" do
    surface = %{
      model: %{"runtime_model" => %{"n" => 1}},
      shell: %{"elm_introspect" => %{"module" => "Main"}}
    }

    merged =
      RuntimeSurfaceMerge.merge_fields(surface, %{
        "elmc_check_status" => "ok",
        "elm_executor_metadata" => %{"engine" => "v1"}
      })

    assert merged.model["elmc_check_status"] == "ok"
    assert merged.model["runtime_model"]["n"] == 1
    assert merged.shell["elm_executor_metadata"]["engine"] == "v1"
    assert merged.shell["elm_introspect"]["module"] == "Main"
  end

  test "merge_into_state updates watch surface on runtime state" do
    state = %{
      running: true,
      watch: %{model: %{}, shell: %{}},
      companion: %{model: %{}, shell: %{}},
      phone: %{model: %{}, shell: %{}}
    }

    next =
      RuntimeSurfaceMerge.merge_into_state(
        state,
        :watch,
        ElmcSurfaceFields.check_fields(%{status: :ok, checked_path: "/tmp"})
      )

    assert get_in(next, [:watch, :model, "elmc_check_status"]) == "ok"
  end
end
