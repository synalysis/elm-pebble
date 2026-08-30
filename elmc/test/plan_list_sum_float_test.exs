defmodule Elmc.PlanListSumFloatTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  test "List.sum of a List Float param uses list_sum_float outside a Float tail" do
    decl = %{
      name: "label",
      args: ["xs"],
      type: "List Float -> String",
      expr: %{
        op: :qualified_call,
        target: "List.sum",
        args: [%{op: :var, name: "xs"}]
      }
    }

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "label"} => decl}, rc_required: true)

    builtins = plan_builtins(plan)
    assert :list_sum_float in builtins
    refute :list_sum in builtins
  end

  test "List.product of a List Float param uses list_product_float outside a Float tail" do
    decl = %{
      name: "label",
      args: ["xs"],
      type: "List Float -> String",
      expr: %{
        op: :qualified_call,
        target: "List.product",
        args: [%{op: :var, name: "xs"}]
      }
    }

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "label"} => decl}, rc_required: true)

    builtins = plan_builtins(plan)
    assert :list_product_float in builtins
    refute :list_product in builtins
  end

  test "List.sum of a List Int param stays list_sum" do
    decl = %{
      name: "label",
      args: ["xs"],
      type: "List Int -> String",
      expr: %{
        op: :qualified_call,
        target: "List.sum",
        args: [%{op: :var, name: "xs"}]
      }
    }

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "label"} => decl}, rc_required: true)

    builtins = plan_builtins(plan)
    assert :list_sum in builtins
    refute :list_sum_float in builtins
  end

  test "List.sum [] in a Float-returning function uses list_sum_float" do
    decl = %{
      name: "emptySum",
      args: [],
      type: "Float",
      expr: %{
        op: :qualified_call,
        target: "List.sum",
        args: [%{op: :list_literal, items: []}]
      }
    }

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "emptySum"} => decl}, rc_required: true)

    builtins = plan_builtins(plan)
    assert :list_sum_float in builtins
    refute :list_sum in builtins
  end

  defp plan_builtins(plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :call_runtime, args: %{builtin: id}} when is_atom(id) -> [id]
      _ -> []
    end)
  end
end
