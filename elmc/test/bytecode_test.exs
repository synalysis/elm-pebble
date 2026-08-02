defmodule Elmc.BytecodeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.{FnTable, Lower, Runtime}
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.{Lowerer, PipeChain}

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

  test "encodes and runs simple_project probeHelper plan" do
    decl_map = simple_project_decl_map!()

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = Map.fetch!(decl_map, {"Main", "probeHelper"})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: false)

    section = Lower.lower(plan)
    assert byte_size(section.code) > 0
    assert {:ok, 7} = Runtime.run_function(plan, params: [5])
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
    decl_map = simple_project_decl_map!()

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    {:ok, advanced} =
      PlanLower.lower(Map.fetch!(decl_map, {"Main", "probeAdvanced"}), "Main", decl_map,
        rc_required: false
      )

    {:ok, helper} =
      PlanLower.lower(Map.fetch!(decl_map, {"Main", "probeHelper"}), "Main", decl_map,
        rc_required: false
      )

    plans = %{{"Main", "probeAdvanced"} => advanced, {"Main", "probeHelper"} => helper}

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

  test "const_int preserves negative values through encode/decode" do
    b = Builder.new("Main", "neg", args: [])
    {reg, b1} = Builder.emit_const_int(b, -6)
    plan = Builder.to_function_plan(Builder.emit_ret(b1, reg))
    section = Lower.lower(plan)
    roundtrip = Lower.decode_section(Lower.encode_section(section))

    assert {:ok, -6} = Runtime.run_section(roundtrip)
  end

  test "basics math builtins match elm/core angles and Order tags" do
    b = Builder.new("Main", "trig", args: [])
    {deg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: deg,
        args: %{builtin: :new_float, args: [], literal: 180.0},
        effects: %{produces: {:owned, deg}, consumes: [], borrows: [], fallible: false}
      })

    {rad, b3} = Builder.fresh_reg(b2)

    {_, b4} =
      Builder.emit(b3, :call_runtime, %{
        dest: rad,
        args: %{builtin: :basics_degrees, args: [deg]},
        effects: %{produces: {:owned, rad}, consumes: [deg], borrows: [], fallible: false}
      })

    {milli, b5} = Builder.fresh_reg(b4)

    {_, b6} =
      Builder.emit(b5, :call_runtime, %{
        dest: milli,
        args: %{builtin: :new_float, args: [], literal: 1000.0},
        effects: %{produces: {:owned, milli}, consumes: [], borrows: [], fallible: false}
      })

    {scaled, b7} = Builder.fresh_reg(b6)

    {_, b8} =
      Builder.emit(b7, :boxed_binop, %{
        dest: scaled,
        args: %{op: :mul, lhs: rad, rhs: milli},
        effects: %{
          produces: {:owned, scaled},
          consumes: [rad, milli],
          borrows: [],
          fallible: false
        }
      })

    {out, b9} = Builder.fresh_reg(b8)

    {_, b10} =
      Builder.emit(b9, :call_runtime, %{
        dest: out,
        args: %{builtin: :basics_truncate, args: [scaled]},
        effects: %{produces: {:owned, out}, consumes: [scaled], borrows: [], fallible: false}
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b10, out))
    assert {:ok, 3141} = Runtime.run_function(plan)

    abs_b = Builder.new("Main", "absNeg", args: [])
    {neg, abs_b1} = Builder.emit_const_int(abs_b, -6)
    {abs_out, abs_b2} = Builder.fresh_reg(abs_b1)

    {_, abs_b3} =
      Builder.emit(abs_b2, :call_runtime, %{
        dest: abs_out,
        args: %{builtin: :basics_abs, args: [neg]},
        effects: %{produces: {:owned, abs_out}, consumes: [neg], borrows: [], fallible: false}
      })

    abs_plan = Builder.to_function_plan(Builder.emit_ret(abs_b3, abs_out))
    assert {:ok, 6} = Runtime.run_function(abs_plan)

    cmp_b = Builder.new("Main", "cmp", args: [])
    {one, cmp_b1} = Builder.emit_const_int(cmp_b, 1)
    {two, cmp_b2} = Builder.emit_const_int(cmp_b1, 2)
    {order, cmp_b3} = Builder.fresh_reg(cmp_b2)

    {_, cmp_b4} =
      Builder.emit(cmp_b3, :call_runtime, %{
        dest: order,
        args: %{builtin: :basics_compare, args: [one, two]},
        effects: %{
          produces: {:owned, order},
          consumes: [one, two],
          borrows: [],
          fallible: false
        }
      })

    # Basics.Order constructor tags: LT=1, EQ=2, GT=3
    cmp_plan = Builder.to_function_plan(Builder.emit_ret(cmp_b4, order))
    assert {:ok, 1} = Runtime.run_function(cmp_plan)
  end

  defp simple_project_decl_map! do
    {:ok, project} = Bridge.load_project(@fixture)
    {:ok, ir} = Lowerer.lower_project(project)
    ir = PipeChain.desugar_project(ir)
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))

    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
    end)
    |> Map.new()
  end
end
