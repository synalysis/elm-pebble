defmodule Elmc.WasmListIndexedReplaceFusionTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.Types.{FunctionPlan, Param}
  alias Elmc.Backend.Wasm.Lower
  alias Elmc.Backend.Wasm.Lower.FusionFunction

  test "list_indexed_replace WASM fusion emits list_replace_nth_int" do
    plan = %FunctionPlan{
      module: "Test",
      name: "replaceAt",
      params: [
        %Param{name: "index", type: nil, index: 0},
        %Param{name: "value", type: nil, index: 1},
        %Param{name: "list", type: nil, index: 2}
      ],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 3,
      lambdas: [],
      fusion_kind: :list_indexed_replace,
      fusion_data: %{}
    }

    assert FusionFunction.emittable?(plan)

    unit = FusionFunction.lower(plan)
    body = unit.body |> IO.iodata_to_binary()

    assert body =~ "list_replace_nth_int"
    refute body =~ "fusion_c"
    refute body =~ "static RC"

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)
    assert wat =~ "list_replace_nth_int"
  end

  test "setCell fusion stays WASM-emittable instead of fusion_only skip" do
    decl = set_cell_decl()
    decl_map = %{{"Main", "setCell"} => decl}

    assert {:ok, plan} = Plan.lower_function(decl, "Main", decl_map, rc_required: true)
    assert FusionFunction.emittable?(plan)
    assert plan.fusion_kind == :list_indexed_replace

    unit = FusionFunction.lower(plan)
    body = unit.body |> IO.iodata_to_binary()
    assert body =~ "list_replace_nth_int"
    refute body =~ "fusion_c"
    refute body =~ "static RC"
  end

  defp set_cell_decl do
    %{
      name: "setCell",
      args: ["index", "newValue", "cells"],
      type: "Int -> Int -> List Int -> List Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :qualified_call,
        target: "List.indexedMap",
        args: [
          %{
            op: :lambda,
            args: ["i", "value"],
            body: %{
              op: :if,
              cond: %{
                op: :compare,
                kind: :eq,
                left: %{op: :var, name: "i"},
                right: %{op: :var, name: "index"}
              },
              then_expr: %{op: :var, name: "newValue"},
              else_expr: %{op: :var, name: "value"}
            }
          },
          %{op: :var, name: "cells"}
        ]
      }
    }
  end
end
