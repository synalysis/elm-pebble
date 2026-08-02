defmodule Elmc.PlanRetainsOperandRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.CCodegen.RetainOperandAlias
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  defp lower_plan!(decl, decl_map) do
    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    plan
  end

  defp find_call_runtime!(plan, builtin) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.find(&match?(%{op: :call_runtime, args: %{builtin: ^builtin}}, &1)) ||
      flunk("missing call_runtime #{inspect(builtin)}")
  end

  test "plan-primary Maybe.withDefault stamps result_aliases on call_runtime" do
    decl = %{
      name: "pickSun",
      args: ["defaultSun", "maybeSun"],
      type: "SunWindow -> Maybe SunWindow -> SunWindow",
      expr: %{
        op: :qualified_call,
        target: "Maybe.withDefault",
        args: [
          %{op: :var, name: "defaultSun"},
          %{op: :var, name: "maybeSun"}
        ]
      }
    }

    plan = lower_plan!(decl, %{{"Main", "pickSun"} => decl})
    call = find_call_runtime!(plan, :maybe_with_default)

    assert call.effects.result_aliases == [0]
    assert call.effects.borrows == [0, 1]
    assert call.effects.consumes == []
    assert call.dest == :fn_out

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_maybe_with_default("
    # Tail fn_out with borrow params: alias transfer is a no-op (no owned default slot).
  end

  test "RetainOperandAlias emit drops retain only inside owned alias if" do
    code =
      RetainOperandAlias.emit("owned[2]", ["owned[0]"], drop_result_retain?: true)

    assert code =~ ~r/if \(owned\[2\] == owned\[0\]\) \{\s*elmc_release\(owned\[2\]\);/
    refute code =~ ~r/elmc_release\(owned\[2\]\);\s*\n\s*if \(owned\[2\] == owned\[0\]\)/
  end
end
