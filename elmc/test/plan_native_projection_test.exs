defmodule Elmc.PlanNativeProjectionTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.PlanNativeProjection

  test "emit prints Int native projection wrapper" do
    decl = %{
      name: "cellAt",
      args: ["x", "y", "board"],
      type: "Int -> Int -> List Int -> Int",
      ownership: [:borrow_arg, :retain_result],
      expr: %{op: :int_literal, value: 0}
    }

    c = PlanNativeProjection.emit(decl, "Main", %{})

    assert c =~ "static RC elmc_fn_Main_cellAt_native(elmc_int_t *out"
    assert c =~ "elmc_as_int(boxed)"
    assert c =~ "elmc_fn_Main_cellAt(&boxed, x, y, board)"
  end

  test "emit prints Bool native projection wrapper for zero-arg helper" do
    decl = %{
      name: "hasPiece",
      args: ["model"],
      type: "Model -> Bool",
      ownership: [:borrow_arg, :retain_result],
      expr: %{op: :bool_literal, value: true}
    }

    c = PlanNativeProjection.emit(decl, "Main", %{})

    assert c =~ "elmc_fn_Main_hasPiece_native(bool *out"
    assert c =~ "elmc_as_bool(boxed)"
  end
end
