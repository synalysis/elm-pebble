defmodule Elmc.HandheldTargetTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.SpecialValues.Dispatcher

  setup do
    previous = Process.get(:elmc_codegen_opts)
    Process.put(:elmc_codegen_opts, %{target: "flipper"})
    on_exit(fn -> Process.put(:elmc_codegen_opts, previous) end)
    :ok
  end

  test "handheld fill lowers to draw op 6 and pebble targets stay on the pebble handlers" do
    rect = %{
      op: :record_literal,
      fields: [
        %{name: "x", expr: %{op: :int_literal, value: 0}},
        %{name: "y", expr: %{op: :int_literal, value: 0}},
        %{name: "width", expr: %{op: :int_literal, value: 10}},
        %{name: "height", expr: %{op: :int_literal, value: 4}}
      ]
    }

    assert %{op: :pebble_cmd, kind: %{op: :c_int_expr, value: "6"}, params: params} =
             Dispatcher.special_value_from_target("Handheld.Ui.fill", [
               rect,
               %{op: :qualified_call, target: "Handheld.Color.white", args: []}
             ])

    assert Enum.any?(params, &match?(%{op: :field_access, field: "width"}, &1))
    assert List.last(params) == %{op: :int_literal, value: 65535}

    assert %{op: :int_literal, value: 63488} =
             Dispatcher.special_value_from_target("Handheld.Color.rgb", [
               %{op: :int_literal, value: 255},
               %{op: :int_literal, value: 0},
               %{op: :int_literal, value: 0}
             ])

    assert %{op: :pebble_cmd, kind: %{op: :c_int_expr, value: "67"}, params: [_, %{op: :int_literal, value: 1}]} =
             Dispatcher.special_value_from_target("Handheld.Gpio.write", [
               %{op: :int_literal, value: 1},
               %{op: :constructor_ref, target: "High"}
             ])

    assert %{op: :pebble_cmd, kind: %{op: :c_int_expr, value: "70"}, params: [%{op: :int_literal, value: 40}]} =
             Dispatcher.special_value_from_target("Handheld.Usb.tap", [
               %{op: :qualified_call, target: "Handheld.Usb.enter", args: []}
             ])

    assert %{op: :pebble_cmd, kind: %{op: :c_int_expr, value: "64"}} =
             Dispatcher.special_value_from_target("Pkg.app.Handheld.Nfc.scan", [])

    assert %{op: :pebble_cmd, kind: %{op: :c_int_expr, value: "14"}} =
             Dispatcher.special_value_from_target("Handheld.Vibes.shortPulse", [])

    assert %{
             op: :pebble_sub,
             mask: %{op: :c_int_expr, value: "134217728"},
             params: [%{op: :msg_tag_expr, name: "Pressed"}]
           } =
             Dispatcher.special_value_from_target("Handheld.Input.presses", [
               %{op: :partial_constructor, target: "Pressed", args: []}
             ])

    assert %{
             op: :pebble_sub,
             mask: %{op: :c_int_expr, value: "ELMC_SUBSCRIPTION_BUTTON_RAW"},
             params: [
               %{op: :int_literal, value: 7},
               %{op: :int_literal, value: 1},
               %{op: :msg_tag_expr, name: "Selected"}
             ]
           } =
             Dispatcher.special_value_from_target("Handheld.Input.onPress", [
               %{op: :constructor_ref, target: "Select"},
               %{op: :partial_constructor, target: "Selected", args: []}
             ])

    assert %{op: :int_literal, value: 0, keep_alive: [_config]} =
             Dispatcher.special_value_from_target("Handheld.Platform.application", [
               %{op: :record_literal, fields: []}
             ])

    Process.put(:elmc_codegen_opts, %{target: "flipper-zero"})

    assert %{op: :pebble_cmd, kind: %{op: :c_int_expr, value: "6"}} =
             Dispatcher.special_value_from_target("Handheld.Ui.fill", [
               rect,
               %{op: :int_literal, value: 1}
             ])

    Process.put(:elmc_codegen_opts, %{target: "basalt"})

    assert %{op: :cmd_none} = Dispatcher.special_value_from_target("Pebble.Cmd.none", [])
    assert Dispatcher.special_value_from_target("Handheld.Nfc.scan", []) == nil
  end
end
