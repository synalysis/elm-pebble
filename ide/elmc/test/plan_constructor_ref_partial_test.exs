defmodule Elmc.PlanConstructorRefPartialTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Pebble.Util

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

  test "binary constructor_ref lowers to an arity-2 partial (Scene3d OpaqueMeshNode)" do
    Process.put(:elmc_constructor_tags, %{
      "Scene3d.Entity.OpaqueMeshNode" => 2,
      "OpaqueMeshNode" => 2
    })

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Scene3d.Entity", "OpaqueMeshNode"} =>
        "Bounds (DrawFunction units coordinates lights a)"
    })

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_union_constructor_payload_specs)
    end)

    ctx =
      Context.new(
        module: "Scene3d.Entity",
        function_name: "meshNode",
        params: [],
        decl_map: %{}
      )

    b = Builder.new("Scene3d.Entity", "meshNode", rc_required: false)

    assert {:ok, _reg, b_out} =
             Expr.compile(%{op: :constructor_ref, target: "OpaqueMeshNode"}, ctx, b)

    instrs =
      (b_out.blocks ++ [b_out.current_block])
      |> Enum.flat_map(& &1.instrs)

    assert Enum.any?(instrs, fn
             %{op: :make_closure, args: %{arity: 2}} -> true
             _ -> false
           end)
  end

  test "multi-arg constructor_call packs payload as nested tuple2, not a list" do
    Process.put(:elmc_constructor_tags, %{"Main.Pair" => 1, "Pair" => 1})
    Process.put(:elmc_union_constructor_payload_specs, %{{"Main", "Pair"} => "Int Int"})

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_union_constructor_payload_specs)
    end)

    ctx = Context.new(module: "Main", function_name: "makePair", params: [], decl_map: %{})
    b = Builder.new("Main", "makePair", rc_required: false)

    assert {:ok, _reg, b_out} =
             Expr.compile(
               %{
                 op: :constructor_call,
                 target: "Pair",
                 args: [
                   %{op: :int_literal, value: 1},
                   %{op: :int_literal, value: 2}
                 ]
               },
               ctx,
               b
             )

    instrs =
      (b_out.blocks ++ [b_out.current_block])
      |> Enum.flat_map(& &1.instrs)

    assert Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :tuple2}} -> true
             _ -> false
           end)

    refute Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :list_from_values}} -> true
             _ -> false
           end)
  end

  test "payload_arity_for_spec matches Elm multi-arg and function-like payloads" do
    assert Util.payload_arity_for_spec(nil) == 0
    assert Util.payload_arity_for_spec("") == 0
    assert Util.payload_arity_for_spec("Int") == 1
    assert Util.payload_arity_for_spec("Int Int") == 2

    assert Util.payload_arity_for_spec("Bounds (DrawFunction units coordinates lights a)") == 2

    assert Util.payload_arity_for_spec("a -> b") == 1
    assert Util.payload_arity_for_spec("(a -> b)") == 1
  end

  test "ambiguous Group resolves via module affinity, not an unrelated package tag" do
    alias Elmc.Backend.CCodegen.IRQueries
    alias Elmc.Backend.Plan.Lower.Constructor
    alias Elmc.Backend.Plan.Lower.UnionCtor

    tags = %{
      "Benchmark.Benchmark.Group" => 3,
      "Benchmark.Reporting.Group" => 3,
      "Internal.Compiler.Group" => 5,
      "Scene3d.Types.Group" => 6,
      "Scene3d.Types.TransparentMeshNode" => 3,
      "TransparentMeshNode" => 3
    }

    assert IRQueries.lookup_tag(tags, "Scene3d.Entity.Group") == 6
    assert IRQueries.lookup_tag(tags, "Types.Group") == 6
    assert IRQueries.lookup_tag(tags, "Benchmark.Benchmark.Group") == 3
    # Bare ambiguous short name with no module context must not guess.
    assert IRQueries.lookup_tag(tags, "Group") == nil

    Process.put(:elmc_constructor_tags, tags)
    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Scene3d.Entity", "Group"} => "List Node",
      {"Scene3d.Types", "Group"} => "List Node"
    })

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_union_constructor_payload_specs)
    end)

    ctx =
      Context.new(
        module: "Scene3d.Entity",
        function_name: "group",
        params: ["nodes"],
        decl_map: %{}
      )

    b = Builder.new("Scene3d.Entity", "group", rc_required: false)
    assert UnionCtor.qualify("Group", ctx) == "Scene3d.Entity.Group"

    assert {:ok, _reg, b_out} =
             Constructor.compile(
               %{op: :constructor_call, target: "Group", args: [%{op: :var, name: "nodes"}]},
               ctx,
               b
             )

    instrs =
      (b_out.blocks ++ [b_out.current_block])
      |> Enum.flat_map(& &1.instrs)

    # Tag must be Scene3d.Types.Group (6), never Benchmark.Group / TransparentMeshNode (3).
    assert Enum.any?(instrs, fn
             %{op: :const_int, args: %{value: 6}} -> true
             _ -> false
           end)

    refute Enum.any?(instrs, fn
             %{op: :const_int, args: %{value: 3}} -> true
             _ -> false
           end)
  end
end
