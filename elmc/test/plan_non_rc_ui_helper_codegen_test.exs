defmodule Elmc.PlanNonRcUiHelperCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  @canvas_layer_expr %{
    op: :record_literal,
    fields: [
      %{name: "tag", expr: %{op: :int_literal, value: 1, union_ctor: "Pebble.Ui.CanvasLayer"}},
      %{
        name: "payload",
        expr: %{
          op: :record_literal,
          fields: [
            %{name: "id", expr: %{op: :var, name: "id"}},
            %{name: "ops", expr: %{op: :var, name: "ops"}}
          ]
        }
      }
    ]
  }

  test "non-RC direct-ABI plan helpers avoid nested catch and clear borrow args before lifo" do
    decl = %{
      name: "canvasLayer",
      kind: :function,
      args: ["id", "ops"],
      ownership: [:borrow_arg, :retain_result],
      expr: @canvas_layer_expr
    }

    decl_map = %{{"Pebble.Ui", "canvasLayer"} => decl}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, [pebble_int32: true, plan_ir_mode: :primary])

    on_exit(fn ->
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_codegen_opts)
    end)

    assert {:ok, plan} = PlanLower.lower(decl, "Pebble.Ui", decl_map, rc_required: false)
    body = CLowerFunction.emit(plan)

    refute body =~ "CATCH_BEGIN"
    assert body =~ "owned[1] = NULL"
    assert body =~ "elmc_release_array_lifo(owned, 4)"
    refute body =~ "return __ret;\n  }\n  owned["
  end
end
