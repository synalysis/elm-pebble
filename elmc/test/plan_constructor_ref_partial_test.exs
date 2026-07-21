defmodule Elmc.PlanConstructorRefPartialTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr

  test "unary constructor_ref lowers to a partial lambda, not a nullary value" do
    Process.put(:elmc_constructor_tags, %{"Main.ModelIndex" => 14, "ModelIndex" => 14})
    Process.put(:elmc_union_constructor_payload_specs, %{{"Main", "ModelIndex"} => "{}"})

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_union_constructor_payload_specs)
    end)

    ctx = Context.new(module: "Main", function_name: "wrap", params: [], decl_map: %{})
    b = Builder.new("Main", "wrap", rc_required: false)

    assert {:ok, _reg, b_out} =
             Expr.compile(%{op: :constructor_ref, target: "ModelIndex"}, ctx, b)

    instrs =
      (b_out.blocks ++ [b_out.current_block])
      |> Enum.flat_map(& &1.instrs)

    # Partial ctor desugars to a lambda / make_closure — not a bare unit-tagged union.
    assert Enum.any?(instrs, fn
             %{op: :make_closure} -> true
             %{op: :call_runtime, args: %{builtin: builtin}} ->
               builtin in [:make_closure, :lambda]
             _ -> false
           end) or
             Enum.any?(instrs, fn instr -> inspect(instr) =~ "make_closure" end)
  end
end
