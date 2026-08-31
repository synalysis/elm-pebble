defmodule Elmc.NativeIntParenTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.C.Lower.NativeIntFold
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.TestSupport.ElmJson
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  test "parenthesize_int_expr wraps call-prefixed sums used under subtraction" do
    inner = "elmc_int_idiv((panel - 24), 4) * 4 + 3 * 3"
    assert NativeIntFold.parenthesize_int_expr(inner) == "(#{inner})"
    assert NativeIntFold.parenthesize_int_expr("elmc_int_idiv(x, 4)") == "elmc_int_idiv(x, 4)"
    assert NativeIntFold.parenthesize_int_expr("plan_native_int_50") == "plan_native_int_50"
    assert NativeIntFold.parenthesize_int_expr("((a <= b) ? a : b)") == "((a <= b) ? a : b)"
    assert NativeIntFold.parenthesize_int_expr("(a <= b) ? a : b") == "((a <= b) ? a : b)"
    assert NativeIntFold.parenthesize_int_expr("(a) + (b)") == "((a) + (b))"
  end

  test "layout centering emits parenthesized boardWidth under subtraction" do
    source = """
    module Main exposing (main)

    layoutX : Int -> Int
    layoutX panel =
        let
            cell =
                (panel - 24 - 6 - 9) // 4

            gap =
                3
        in
        (panel - (cell * 4 + gap * 3)) // 2

    main =
        layoutX 144
    """

    c = emit_main_c!(source, "layoutX")

    refute c =~ ~r/panel\w* - elmc_int_idiv\([^)]+\) \* 4 \+ /
    assert c =~ ~r/- \(.*\* 4 \+ /
  end

  defp write_minimal_project!(project_dir, source) do
    ElmJson.write_probe_project!(project_dir, source)
  end

  defp emit_main_c!(source, fun_name) do
    project_dir = Path.expand("tmp/native_int_paren_#{fun_name}", __DIR__)
    write_minimal_project!(project_dir, source)
    {:ok, project} = Bridge.load_project(project_dir)
    {:ok, ir} = Lowerer.lower_project(project)
    decl_map = IRQueries.function_decl_map(ir)

    decl =
      case Map.get(decl_map, {"Main", fun_name}) do
        nil -> flunk("Main.#{fun_name} not found in lowered IR")
        found -> found
      end

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    CLowerFunction.emit(plan)
  end
end
