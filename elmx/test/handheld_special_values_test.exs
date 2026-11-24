defmodule Elmx.HandheldSpecialValuesTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.ViewShape

  test "Handheld.Ui.clear rewrites to a debugger draw call" do
    color = %{op: :qualified_call, target: "Handheld.Color.black", args: []}

    assert {:ok, %{op: :int_literal, value: 0}} = SpecialValues.rewrite("Handheld.Color.black", [])

    assert {:ok, %{op: :runtime_call, function: "elmx_handheld_clear", args: [^color]}} =
             SpecialValues.rewrite("Handheld.Ui.clear", [color])
  end

  test "clear and fill become preview draw nodes" do
    clear = Pebble.runtime_dispatch("elmx_handheld_clear", [0])

    bar =
      Pebble.runtime_dispatch("elmx_handheld_fill", [
        %{"x" => 0, "y" => 28, "width" => 128, "height" => 8},
        1
      ])

    tree =
      ViewShape.normalize(%{
        "kind" => "batch",
        "commands" => [clear, bar]
      })

    assert tree["type"] in ["windowStack", "WindowStack"]
    assert inspect(tree) =~ "clear"
    assert inspect(tree) =~ "fillRect"
  end

  test "rgb packs a color pixel" do
    assert Pebble.runtime_dispatch("elmx_handheld_color_rgb", [255, 0, 0]) == 63488
  end

  test "presses registers one subscription per button" do
    rows = Pebble.runtime_dispatch("elmx_handheld_presses", [fn button -> {:Pressed, button} end])

    assert Enum.map(rows, & &1["event_kind"]) == [
             "A",
             "B",
             "Up",
             "Down",
             "Left",
             "Right",
             "Select",
             "Back"
           ]

    up = Enum.find(rows, &(&1["event_kind"] == "Up"))
    assert up["kind"] == "cmd.subscription.register"
    assert up["message"] == "Pressed"
  end

  test "battery level delivers a message" do
    cmd = Pebble.runtime_dispatch("elmx_handheld_battery_level", [fn level -> {:Level, level} end])

    assert cmd["kind"] == "cmd.task.immediate"
    assert cmd["message"] == "Level"
    assert cmd["message_value"]["args"] == [80]
  end
end
