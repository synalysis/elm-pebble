defmodule Elmc.PlanShadowIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :plan_shadow

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)

  test "simple_project compiles with plan_ir_mode shadow" do
    project_dir = Path.expand("tmp/plan_shadow_project", __DIR__)
    out_dir = Path.expand("tmp/plan_shadow_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(@source_fixture, project_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow
             })

    assert File.exists?(Path.join(out_dir, "c/elmc_generated.c"))
  end

  test "shadow verify passes for int literal leaf function" do
    decl = %{name: "zero", args: [], expr: %{op: :int_literal, value: 0}}

    assert :ok =
             Elmc.Backend.Plan.shadow_verify(decl, "Main", %{},
               plan_ir_mode: :shadow,
               plan_ir_raise: true,
               rc_required: false
             )
  end

  test "shadow verify passes for counterOf from simple_project IR" do
    project_dir = Path.expand("tmp/plan_shadow_ir_project", __DIR__)
    out_dir = Path.expand("tmp/plan_shadow_ir_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(@source_fixture, project_dir)

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow,
               plan_ir_raise: true
             })

    ir = result.ir
    decl_map = decl_map_from_ir(ir)

    counter_decl = Map.fetch!(decl_map, {"Main", "counterOf"})

    assert :ok =
             Elmc.Backend.Plan.shadow_verify(counter_decl, "Main", decl_map,
               plan_ir_mode: :shadow,
               rc_required: false
             )
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
