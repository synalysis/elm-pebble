defmodule Elmc.BytecodeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.{FnTable, Lower, Runtime}
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "lowers simple init plan to elmcbc section" do
    b = Builder.new("Main", "init", args: [])
    {reg, b1} = Builder.emit_const_int(b, 0)
    b2 = Builder.emit_ret(b1, reg)
    plan = Builder.to_function_plan(b2)

    section = Lower.lower(plan)
    assert section.magic == "ELMC"
    assert section.version == 3
    assert section.fn_table == []
    assert byte_size(section.code) > 0

    encoded = Lower.encode_section(section)
    assert <<_::binary-size(4), _::binary>> = encoded
    assert Lower.decode_section(encoded) == section
  end

  test "interpreter runs simple init plan" do
    b = Builder.new("Main", "init", args: [])
    {reg, b1} = Builder.emit_const_int(b, 42)
    b2 = Builder.emit_ret(b1, reg)
    plan = Builder.to_function_plan(b2)

    assert {:ok, 42} = Runtime.run_function(plan)
  end

  test "interpreter runs int_arith add_const plan" do
    b = Builder.new("Main", "inc", args: ["n"])
    {n_reg, b1} = Builder.get_or_load_param(b, 0, "n")
    {dest, b2} = Builder.fresh_reg(b1)

    {_, b3} =
      Builder.emit(b2, :int_arith, %{
        dest: dest,
        args: %{kind: :add_const, lhs: n_reg, value: 1},
        effects: %{produces: {:owned, dest}, consumes: [], borrows: [n_reg], fallible: false}
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b3, dest))

    assert {:ok, 6} = Runtime.run_function(plan, params: [5])
  end

  test "encodes and runs simple_project init plan" do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/bytecode_init_codegen", __DIR__),
        entry_module: "Main",
        strip_dead_code: true
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "init"})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    section = Lower.lower(plan)
    assert byte_size(section.code) > 0
    assert {:ok, _} = Runtime.run_function(plan, params: [0])
  end

  test "interpreter dispatches call_fn through fn_registry" do
    b = Builder.new("Main", "caller", args: ["n"])
    {n_reg, b1} = Builder.get_or_load_param(b, 0, "n")
    {dest, b2} = Builder.fresh_reg(b1)

    {_, b3} =
      Builder.emit(b2, :call_fn, %{
        dest: dest,
        args: %{module: "Main", name: "double", args: [n_reg]},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [n_reg],
          fallible: false
        }
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b3, dest))
    section = Lower.lower(plan)
    assert section.fn_table == [{"Main", "double"}]

    fn_registry = %{
      {"Main", "double"} => fn [n] -> n * 2 end
    }

    assert {:ok, 10} = Runtime.run_section(section, params: [5], fn_registry: fn_registry)
  end

  test "call_fn preserves linked plans map for nested callees" do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/bytecode_call_fn_plans", __DIR__),
        entry_module: "Main",
        strip_dead_code: false
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    {:ok, advanced} = PlanLower.lower(Map.fetch!(decl_map, {"Main", "advanced"}), "Main", decl_map, rc_required: false)
    {:ok, helper} = PlanLower.lower(Map.fetch!(decl_map, {"Main", "helper"}), "Main", decl_map, rc_required: false)

    plans = %{{"Main", "advanced"} => advanced, {"Main", "helper"} => helper}

    assert {:ok, 8} = Runtime.run_function(advanced, params: [5], plans: plans)
    assert {:ok, 11} = Runtime.run_function(advanced, params: [9], plans: plans)
  end

  test "load_param reads immutable params snapshot when dest overwrites low locals" do
    b = Builder.new("Main", "pair", args: ["board", "seed"])
    {seed_reg, b1} = Builder.emit_load_param(b, 1)
    {board_reg, b2} = Builder.emit_load_param(b1, 0)
    {dest, b3} = Builder.fresh_reg(b2)

    {_, b4} =
      Builder.emit(b3, :call_runtime, %{
        dest: dest,
        args: %{builtin: :tuple2, args: [board_reg, seed_reg]},
        effects: %{
          produces: {:owned, dest},
          consumes: [seed_reg],
          borrows: [board_reg],
          fallible: false
        }
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b4, dest))
    board = [1, 2, 3]

    assert {:ok, {:tuple2, ^board, 99}} = Runtime.run_function(plan, params: [board, 99])
  end

  test "FnTable.collect_section includes nested lambda call_fn targets" do
    parent = %{
      fn_table: [{"Main", "pieceOffsets"}],
      lambdas: [
        %{fn_table: [{"Main", "offsetFits"}], lambdas: []}
      ]
    }

    assert [{"Main", "pieceOffsets"}, {"Main", "offsetFits"}] ==
             FnTable.collect_section(parent)
  end

  test "interpreter skips release args and applies record_update by field index" do
    b = Builder.new("Main", "bump", args: ["model"])
    {model_reg, b1} = Builder.get_or_load_param(b, 0, "model")
    {value_reg, b2} = Builder.emit_const_int(b1, 1)
    {dest, b3} = Builder.fresh_reg(b2)

    {_, b4} =
      Builder.emit(b3, :record_update, %{
        dest: dest,
        args: %{base: model_reg, value: value_reg, field: "count", field_index: "1"},
        effects: %{
          produces: {:owned, dest},
          consumes: [value_reg],
          borrows: [model_reg],
          fallible: false
        }
      })

    {_, b5} =
      Builder.emit(b4, :release, %{
        dest: nil,
        args: %{reg: value_reg},
        effects: %{produces: nil, consumes: [value_reg], borrows: [], fallible: false}
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b5, dest))
    model = {:record, [0, 0]}

    assert {:ok, {:record, [0, 1]}} = Runtime.run_function(plan, params: [model])
  end

  test "list_concat treats scalar zero as empty list" do
    b = Builder.new("Main", "cat", args: [])
    {zero, b1} = Builder.emit_const_int(b, 0)
    {dest, b2} = Builder.fresh_reg(b1)

    {_, b3} =
      Builder.emit(b2, :call_runtime, %{
        dest: dest,
        args: %{builtin: :list_concat, args: [zero]},
        effects: %{produces: {:owned, dest}, consumes: [zero], borrows: [], fallible: false}
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b3, dest))
    assert {:ok, []} = Runtime.run_function(plan)
  end
end
