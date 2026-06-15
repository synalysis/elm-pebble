defmodule Ide.Debugger.RuntimeSurfacesScreenFieldsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces

  test "launch_context_screen_fields maps gabbro round 260 screen contract" do
    launch_context = RuntimeSurfaces.launch_context_for("gabbro", "LaunchUser")

    assert launch_context_screen_fields(launch_context) == %{
             "screenW" => 260,
             "screenH" => 260,
             "displayShape" => %{"ctor" => "Round", "args" => []}
           }
  end

  test "stored launch_context stays round after elmx normalize round-trip" do
    launch_context =
      "gabbro"
      |> RuntimeSurfaces.launch_context_for("LaunchUser")
      |> then(fn lc ->
        model = RuntimeSurfaces.merge_launch_context_model(%{"runtime_model" => %{}}, lc)
        Map.get(model, "launch_context")
      end)
      |> Elmx.Runtime.LaunchContext.normalize()

    assert get_in(launch_context, ["screen", "shape"]) == %{"ctor" => "Round", "args" => []}
    assert get_in(launch_context, ["screen", "is_round"]) == true
    assert get_in(launch_context, ["screen", "width"]) == 260
  end

  test "merge_launch_context_model patches nested runtime_model screen fields" do
    launch_context = RuntimeSurfaces.launch_context_for("gabbro", "LaunchUser")

    model = %{
      "runtime_model" => %{
        "cells" => [0, 0, 0, 0],
        "score" => 0,
        "screenW" => 144,
        "screenH" => 168,
        "displayShape" => %{"ctor" => "Rectangular", "args" => []}
      }
    }

    merged = RuntimeSurfaces.merge_launch_context_model(model, launch_context)

    assert get_in(merged, ["runtime_model", "screenW"]) == 260
    assert get_in(merged, ["runtime_model", "screenH"]) == 260

    assert get_in(merged, ["runtime_model", "displayShape"]) ==
             %{"ctor" => "Round", "args" => []}
  end

  defp launch_context_screen_fields(launch_context) do
    RuntimeSurfaces.launch_context_screen_fields(launch_context)
  end
end
