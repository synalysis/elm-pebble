defmodule Elmc.PlanZeroArityThunkApplyTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.PrimaryCodegen

  @moduletag :plan_surface

  test "applying an untyped partial CAF uses call_closure not bare call_fn" do
    project = Path.expand("tmp/plan_zero_arity_thunk_project", __DIR__)
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

      add a b =
          a + b

      addFive =
          add 5

      main =
          addFive 3
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
    decl = Map.fetch!(decl_map, {"Main", "main"})
    assert {:ok, plan} = Plan.lower_function(decl, "Main", decl_map, rc_required: false)

    ops = plan.blocks |> Enum.flat_map(& &1.instrs) |> Enum.map(& &1.op)
    assert :call_closure in ops

    call_fn =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(&1.op == :call_fn && &1.args[:name] == "addFive"))

    assert call_fn
    assert call_fn.args.args == []

    generated = File.read!(Path.join(out, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_main")
    assert body =~ "elmc_closure_call"
    refute body =~ ~r/return elmc_fn_Main_addFive\(\);\s*\n\s*\}/
  end
end
