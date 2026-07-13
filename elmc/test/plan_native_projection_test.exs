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

  test "angleFromMinute projection inlines elmc_angle_from_minute without boxed shim" do
    decl = %{
      name: "angleFromMinute",
      args: ["minute"],
      type: "Int -> Int",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :call,
        name: "modBy",
        args: [
          %{op: :int_literal, value: 65_536},
          %{
            op: :call,
            name: "__idiv__",
            args: [
              %{
                op: :call,
                name: "__mul__",
                args: [
                  %{
                    op: :call,
                    name: "__sub__",
                    args: [%{op: :var, name: "minute"}, %{op: :int_literal, value: 720}]
                  },
                  %{op: :int_literal, value: 65_536}
                ]
              },
              %{op: :int_literal, value: 1440}
            ]
          }
        ]
      }
    }

    c = PlanNativeProjection.emit(decl, "Yes.Render", %{})

    assert c =~ "elmc_angle_from_minute(minute)"
    refute c =~ "ElmcValue *boxed"
  end
end
