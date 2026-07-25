defmodule ElmEx.IR.FnArgDesugarTest do
  use ExUnit.Case, async: true

  alias ElmEx.IR.FnArgDesugar

  test "leaves simple idents unchanged" do
    expr = %{op: :var, name: "x"}
    assert {["x", "y"], ^expr} = FnArgDesugar.desugar_args(["x", "y"], expr)
  end

  test "desugars Array constructor pattern into patternArg + case" do
    body = %{op: :var, name: "len"}
    {args, expr} = FnArgDesugar.desugar_args(["(Array_elm_builtin len _ _ _)"], body)

    assert args == ["patternArg"]
    assert expr.op == :case
    assert expr.subject == %{op: :var, name: "patternArg"}
    assert [%{pattern: pattern, expr: ^body}] = expr.branches
    assert pattern.kind == :constructor
    assert pattern.name in ["Array_elm_builtin", "Array.Array_elm_builtin"] or
             String.contains?(to_string(pattern.name), "Array_elm_builtin")
  end

  test "desugars as-pattern and keeps alias bind" do
    body = %{op: :var, name: "array"}

    {args, expr} =
      FnArgDesugar.desugar_args(
        ["((Array_elm_builtin len startShift tree tail) as array)"],
        body
      )

    assert args == ["patternArg"]
    assert expr.op == :case
    pattern = hd(expr.branches).pattern
    assert is_binary(Map.get(pattern, :bind)) or match?(%{kind: :alias}, pattern)
  end

  test "lower_project Array.isEmpty uses simple patternArg" do
    dir = Path.expand("tmp/fn_arg_desugar_array", __DIR__)
    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "src"))

    File.write!(Path.join(dir, "src/Main.elm"), """
    module Main exposing (main)
    import Array
    main = Array.isEmpty (Array.fromList [1])
    """)

    File.cp!(
      Path.expand("../../elmc/test/fixtures/simple_project/elm.json", Path.dirname(__DIR__)),
      Path.join(dir, "elm.json")
    )

    {:ok, project} = ElmEx.Frontend.Bridge.load_project(dir)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    mod = Enum.find(ir.modules, &(&1.name == "Array"))
    decl = Enum.find(mod.declarations, &(&1.name == "isEmpty"))

    assert decl.args == ["patternArg"]
    assert decl.expr.op == :case
    refute Enum.any?(decl.args, &String.contains?(&1, "Array_elm_builtin"))
  end
end
