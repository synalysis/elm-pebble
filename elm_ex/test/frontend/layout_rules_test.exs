defmodule ElmEx.Frontend.LayoutRulesTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.LayoutRules

  test "let_binding_start? recognizes plain and destructuring bindings" do
    assert LayoutRules.let_binding_start?("counter =")
    assert LayoutRules.let_binding_start?("flag b =")
    assert LayoutRules.let_binding_start?("  ( x, y ) =")
    assert LayoutRules.let_binding_start?("{ x | field } =")
    assert LayoutRules.let_binding_start?("{ totalMass, totalVolume } =")
    refute LayoutRules.let_binding_start?("{ inArrows = []")
    assert LayoutRules.let_binding_start?("{ x | field } =")
    refute LayoutRules.let_binding_start?("in")
    refute LayoutRules.let_binding_start?("else")
    # Parenthesized lambda / record-update lines must not look like `(pattern) =`
    refute LayoutRules.let_binding_start?("(\\mat -> { mat | density = 0 })")
    refute LayoutRules.let_binding_start?("( \\( shape, mat, sign ) -> ( shape, { mat | density = 0 }, sign ))")
  end

  test "case_arm_start? recognizes wildcard and constructor arms" do
    assert LayoutRules.case_arm_start?("_ ->")
    assert LayoutRules.case_arm_start?("Just x ->")
    assert LayoutRules.case_arm_start?("( A, B ) ->")
    assert LayoutRules.case_arm_start?("[ \"packages\", author ] ->")
    refute LayoutRules.case_arm_start?("in")
    refute LayoutRules.case_arm_start?("else if x then")
    refute LayoutRules.case_arm_start?("if x then")
    refute LayoutRules.case_arm_start?("contents")
    refute LayoutRules.case_arm_start?("(\\bytes ->")
    refute LayoutRules.case_arm_start?("case pieces of")
  end

  test "application_continuation? recognizes bracket and paren argument lines" do
    assert LayoutRules.application_continuation?("    [ a, b ]")
    assert LayoutRules.application_continuation?("( x, y )")
    assert LayoutRules.application_continuation?("{ inArrows = []")
    assert LayoutRules.application_continuation?(", wrapping = Nothing")
    assert LayoutRules.application_continuation?("Nothing")
    assert LayoutRules.application_continuation?("url")
    assert LayoutRules.application_continuation?("Cmd.batch")
    refute LayoutRules.application_continuation?("let foo =")
    refute LayoutRules.application_continuation?("( _, paths ) = msg")
    refute LayoutRules.application_continuation?("( Just x, Nothing ) ->")
    refute LayoutRules.application_continuation?("UrlChanged url ->")
  end

  test "pipe_continuation? recognizes pipe lines" do
    assert LayoutRules.pipe_continuation?("    |> f x")
    refute LayoutRules.pipe_continuation?("a = 1")
  end

  test "cons and append continuation helpers" do
    assert LayoutRules.cons_continuation?("    :: (case x of")
    assert LayoutRules.append_continuation?("    ++ rest")
    assert LayoutRules.value_line_continuation?("    |> f")
    assert LayoutRules.value_line_continuation?("    :: tail")
    assert LayoutRules.infix_rhs_line_start?("    Svg.rect attrs []")
    refute LayoutRules.cons_continuation?("case x of")
  end
end
