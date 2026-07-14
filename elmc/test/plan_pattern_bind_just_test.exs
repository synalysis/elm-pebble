defmodule Elmc.PlanPatternBindJustTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.PatternBind

  test "Just bind without arg_pattern unwraps payload via maybe_just_payload" do
    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    b = Builder.new("Main", "pattern_bind_test", rc_required: false)
    ctx = Context.new()
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{kind: :constructor, name: "Just", bind: "pageDataBytes"}

    assert {:ok, ctx1, b2} = PatternBind.bind(pattern, ctx, b1, subject_reg)

    payload_reg = Context.local_reg(ctx1, "pageDataBytes")
    assert payload_reg != subject_reg
    assert payload_reg != nil

    instrs =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)

    assert Enum.any?(instrs, fn instr ->
             match?(%{op: :call_runtime, args: %{builtin: :maybe_just_payload}}, instr) or
               match?(
                 %{op: :call_runtime, args: %{view_peel: :maybe_just_payload}},
                 instr
               )
           end)
  end

  test "Just bind with arg_pattern var still unwraps payload" do
    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    b = Builder.new("Main", "pattern_bind_test", rc_required: false)
    ctx = Context.new()
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{
      kind: :constructor,
      name: "Just",
      arg_pattern: %{kind: :var, name: "pageDataBytes"}
    }

    assert {:ok, ctx1, _b2} = PatternBind.bind(pattern, ctx, b1, subject_reg)
    assert Context.local_reg(ctx1, "pageDataBytes") != subject_reg
  end
end
