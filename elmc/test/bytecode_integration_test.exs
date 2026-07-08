defmodule Elmc.BytecodeIntegrationTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Program
  alias Elmc.Backend.Bytecode.Runtime
  alias Elmc.Backend.Plan.Builder

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "bytecode interpreter runs init-style int literal plan" do
    b = Builder.new("Main", "init", args: [])
    {reg, b1} = Builder.emit_const_int(b, 0)
    b2 = Builder.emit_ret(b1, reg)
    plan = Builder.to_function_plan(b2)

    assert {:ok, _} = Runtime.run_function(plan)
  end

  test "linked program runs advanced via nested helper plan" do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/bytecode_link_codegen", __DIR__),
        entry_module: "Main",
        strip_dead_code: false
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = decl_map_from_ir(result.ir)

    assert {:ok, program} = Program.link(decl_map, {"Main", "advanced"}, rc_required: false)
    assert Map.has_key?(program.plans, {"Main", "helper"})

    assert {:ok, 8} = Program.run(program, params: [5])
    assert {:ok, 11} = Program.run(program, params: [9])
  end

  test "linked program runs counterOf through record field access" do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/bytecode_counter_codegen", __DIR__),
        entry_module: "Main",
        strip_dead_code: true
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = decl_map_from_ir(result.ir)

    assert {:ok, program} = Program.link(decl_map, {"Main", "counterOf"}, rc_required: false)
    model = {:record, [42, nil]}
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
