defmodule Elmc.PlanAddVarsCafOperandTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "add_vars with zero-arg CAF operand does not target fn_out" do
    project = Path.expand("tmp/plan_add_vars_caf_project", __DIR__)
    File.rm_rf!(project)
    File.mkdir_p!(Path.join(project, "src"))

    File.write!(
      Path.join(project, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}},
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(project, "src/Main.elm"),
      """
      module Main exposing (main)

      g0 = 0

      add0 x =
          x + g0

      main =
          add0 1
      """
    )

    out = Path.join(project, "out")

    assert {:ok, result} =
             PrimaryCodegen.compile(project, %{
               out_dir: out,
               entry_module: "Main",
               plan_ir_mode: :primary,
               strip_dead_code: false
             })

    decl_map = IRQueries.function_decl_map(result.ir)
    decl = Map.fetch!(decl_map, {"Main", "add0"})
    rc? = RcRequired.rc_required?("Main", "add0")
    assert {:ok, plan} = Plan.lower_function(decl, "Main", decl_map, rc_required: rc?)

    instrs = Enum.flat_map(plan.blocks, & &1.instrs)

    call_fn = Enum.find(instrs, &(&1.op == :call_fn))
    arith = Enum.find(instrs, &(&1.op == :int_arith))

    if call_fn do
      assert call_fn.dest != :fn_out
      assert is_integer(call_fn.dest)
    end

    if arith do
      refute arith.args.rhs == :fn_out
      refute arith.args.lhs == :fn_out
    end

    generated = File.read!(Path.join(out, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_add0")
    refute body =~ "return elmc_fn_Main_g0();"
    refute body =~ "elmc_as_int(*out)"
  end
end
