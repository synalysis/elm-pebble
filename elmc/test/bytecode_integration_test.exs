defmodule Elmc.BytecodeIntegrationTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Program
  alias Elmc.Backend.Bytecode.Runtime
  alias Elmc.Backend.Plan.Builder

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "bytecode interpreter runs test_string_literal" do
    b = Builder.new("Main", "probe", args: ["s"])
    {subj, b1} = Builder.get_or_load_param(b, 0, "s")
    {cond, b2} = Builder.fresh_reg(b1)

    {_, b3} = Builder.emit(b2, :test_string_literal, %{
        dest: cond,
        args: %{subject: subj, literal: "elm"},
        effects: %{
          produces: {:owned, cond},
          consumes: [],
          borrows: [subj],
          fallible: false
        }
      })

    b4 = Builder.emit_ret(b3, cond)
    plan = Builder.to_function_plan(b4)

    assert {:ok, 1} = Runtime.run_function(plan, params: ["elm"])
    assert {:ok, 0} = Runtime.run_function(plan, params: ["other"])
  end

  test "linked program runs init-style int literal plan" do
    b = Builder.new("Main", "init", args: [])
    {reg, b1} = Builder.emit_const_int(b, 0)
    b2 = Builder.emit_ret(b1, reg)
    plan = Builder.to_function_plan(b2)

    assert {:ok, _} = Runtime.run_function(plan)
  end

  test "linked program runs probeAdvanced via nested helper plan" do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/bytecode_link_codegen", __DIR__),
        entry_module: "Main",
        strip_dead_code: false
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))
    Process.put(:elmc_record_alias_shapes, Elmc.Backend.CCodegen.IRQueries.record_alias_shape_map(result.ir))

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_record_alias_shapes)
    end)

    decl_map = decl_map_from_ir(result.ir)

    assert {:ok, program} = Program.link(decl_map, {"Main", "probeAdvanced"}, rc_required: false)
    assert Map.has_key?(program.plans, {"Main", "probeHelper"})

    assert {:ok, 8} = Program.run(program, params: [5])
    assert {:ok, 11} = Program.run(program, params: [9])
  end

  test "linked program runs probeScoreOf through record field access" do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/bytecode_counter_codegen", __DIR__),
        entry_module: "Main",
        strip_dead_code: false
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))
    Process.put(:elmc_record_alias_shapes, Elmc.Backend.CCodegen.IRQueries.record_alias_shape_map(result.ir))

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_record_alias_shapes)
    end)

    decl_map = decl_map_from_ir(result.ir)

    assert {:ok, program} = Program.link(decl_map, {"Main", "probeScoreOf"}, rc_required: false)
    empty_cells = List.duplicate(0, 16)
    model = {:record, [empty_cells, 42, 0, 0, 0, 0, 0, 0, :round]}
    assert {:ok, 42} = Program.run(program, params: [model])
  end

  defp decl_map_from_ir(ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
    end)
    |> Map.new()
  end
end
