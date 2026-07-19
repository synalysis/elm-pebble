defmodule ElmEx.Frontend.Pretty.AstNormalizeTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedExpressionParser, Pretty}
  alias ElmEx.Frontend.Pretty.AstNormalize

  test "equivalent? ignores let_bindings layout metadata" do
    {:ok, with_layout} = GeneratedExpressionParser.parse("let a = 1\nin a")
    without_layout = Map.delete(with_layout, :layout)

    assert AstNormalize.equivalent?(with_layout, without_layout)
  end

  test "equivalent? treats add_vars and __add__ call as the same" do
    left = %{op: :add_vars, left: "a", right: "b"}

    right = %{
      op: :call,
      name: "__add__",
      args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
    }

    assert AstNormalize.equivalent?(left, right)
  end

  test "round_trip_ast? accepts precedence parentheses and preserved bool ops" do
    assert Pretty.round_trip_ast?("(a + b) * c")
    assert Pretty.round_trip_ast?("crossed && above")
    assert Pretty.round_trip_ast?("""
           let
               a = 1
           in
               a
           """)
  end

  test "round_trip_ast? preserves nested constructor case patterns" do
    assert Pretty.round_trip_ast?("""
           case msg of
               CatalogReceived (Ok json) ->
                   1
           """)
  end

  test "round_trip_ast? preserves constructor call grouping" do
    assert Pretty.round_trip_ast?("Just (encodeFormData fields.fields)")
    assert Pretty.round_trip_ast?("List.map f (g x)")

    assert Pretty.round_trip_ast?("""
           Just
               (Packages__Author___Name___Version___ModuleName_
                   { author = author, name = name, version = version, moduleName = moduleName }
               )
           """)
  end

  test "format_expr uses tight parentheses" do
    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("CatalogReceived (Ok json)"), 1)
           ) =~ "CatalogReceived (Ok json)"

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("Just (encodeFormData x)"), 1)
           ) == "Just (encodeFormData x)"

    assert Pretty.format_expr(elem(GeneratedExpressionParser.parse("a + (b * c)"), 1)) == "a + b * c"
    assert Pretty.format_expr(elem(GeneratedExpressionParser.parse("(a + b) * c"), 1)) == "(a + b) * c"
  end

  test "equivalent? treats module builtin expr sugar and qualified calls the same" do
    assert AstNormalize.equivalent?(
             %{op: :tuple_first_expr, arg: %{op: :var, name: "x"}},
             %{op: :qualified_call, target: "Tuple.first", args: [%{op: :var, name: "x"}]}
           )

    assert Pretty.format_expr(%{op: :tuple_first_expr, arg: %{op: :var, name: "tupleValue"}}) ==
             "Tuple.first tupleValue"
  end
end
