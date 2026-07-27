defmodule Elmc.PlanPatternBindJustTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.PatternBind

  test "nullary constructor pattern without bind key is a no-op bind" do
    b = Builder.new("Main", "nullary_ctor", rc_required: false)
    ctx = Context.new()
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{kind: :constructor, name: "Tick", tag: 1, arg_pattern: nil}

    assert {:ok, ^ctx, ^b1} = PatternBind.bind(pattern, ctx, b1, subject_reg)
  end

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

  test "union ctor bind shorthand with explicit nil arg_pattern unwraps payload" do
    Process.put(:elmc_union_constructor_payload_specs, %{{"Main", "BestLoaded"} => "String"})

    on_exit(fn -> Process.delete(:elmc_union_constructor_payload_specs) end)

    b = Builder.new("Main", "pattern_bind_test", rc_required: false)
    ctx = Context.new()
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{
      kind: :constructor,
      name: "BestLoaded",
      bind: "value",
      arg_pattern: nil
    }

    assert {:ok, ctx1, _b2} = PatternBind.bind(pattern, ctx, b1, subject_reg)
    assert Context.local_reg(ctx1, "value") != subject_reg
  end

  test "Color.toRgba-style record pattern uses alphabetical field indices" do
    # Source order { red, green, blue, alpha }; Elm stores alpha, blue, green, red
    # when no named alias shape is registered for this anonymous field set.
    b = Builder.new("Main", "color_to_linear_rgb", rc_required: false)
    ctx = Context.new()
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{
      kind: :record,
      fields: ["red", "green", "blue", "alpha"],
      bind: nil
    }

    assert {:ok, _ctx1, b2} = PatternBind.bind(pattern, ctx, b1, subject_reg)

    gets =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))
      |> Map.new(fn instr -> {instr.args[:field], instr.args[:field_index]} end)

    assert gets["alpha"] =~ "0"
    assert gets["blue"] =~ "1"
    assert gets["green"] =~ "2"
    assert gets["red"] =~ "3"
  end

  test "View-style alias shape keeps declaration-order pattern indices" do
    Process.put(:elmc_record_alias_shapes, %{
      {"View", "View"} => ["title", "body"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    b = Builder.new("Main", "view_pattern", rc_required: false)
    ctx = Context.new()
    {subject_reg, b1} = Builder.fresh_reg(b)

    pattern = %{kind: :record, fields: ["title", "body"], bind: nil}

    assert {:ok, _ctx1, b2} = PatternBind.bind(pattern, ctx, b1, subject_reg)

    gets =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))
      |> Map.new(fn instr -> {instr.args[:field], instr.args[:field_index]} end)

    assert gets["title"] =~ "0"
    assert gets["body"] =~ "1"
  end
end
