defmodule Elmc.CompanionSendPayloadCmdTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.Lower.SpecialValues

  test "sendWatchToPhone carries the whole message value into the companion-send cmd" do
    msg = %{
      op: :constructor_call,
      target: "Companion.Types.SendColor",
      args: [%{op: :qualified_ref, target: "Companion.Types.Red"}]
    }

    expr = SpecialValues.special_value_from_target("Companion.Watch.sendWatchToPhone", [msg])

    assert %{op: :runtime_call, function: "elmc_cmd_companion_send_value", args: [^msg]} = expr
    refute match?(%{op: :tuple2}, expr)
  end

  test "sendWatchToPhone value cmd lowers to a boxed COMPANION_SEND runtime call" do
    decl = %{
      name: "sendMessage",
      args: ["message"],
      expr:
        SpecialValues.special_value_from_target("Companion.Watch.sendWatchToPhone", [
          %{op: :var, name: "message"}
        ])
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_cmd_companion_send_value"
    refute c =~ "Companion.Internal.watchToPhoneTag"
  end

  test "encoded companion-send tuple keeps kind as int constant, not nested cmd0" do
    kind = %{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_COMPANION_SEND"}

    expr =
      SpecialValues.encoded_cmd_as_tuple(kind, [
        %{op: :int_literal, value: 3},
        %{op: :int_literal, value: 1}
      ])

    decl = %{name: "sendColor", args: [], expr: expr}

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    refute c =~ "elmc_cmd0"
    assert c =~ "ELMC_PEBBLE_CMD_COMPANION_SEND"
    assert c =~ "elmc_tuple2"
    # Kind is a const c-expr / new_int, not a command object nested as tuple left.
    refute c =~ ~r/elmc_cmd0\([^;]*ELMC_PEBBLE_CMD_COMPANION_SEND/
  end

  test "zero-arity cmds still lower to elmc_cmd0" do
    decl = %{
      name: "stop",
      args: [],
      expr: SpecialValues.special_value_from_target("Pebble.Speaker.stop", [])
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_cmd0"
    assert c =~ "ELMC_PEBBLE_CMD_SPEAKER_STOP"
  end
end
