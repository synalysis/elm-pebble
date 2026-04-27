defmodule Elmc.FrontendParserConstructsTest do
  use ExUnit.Case

  alias ElmEx.Frontend.GeneratedParser

  test "generated parser supports core construct coverage on main fixture" do
    fixture = Path.expand("fixtures/simple_project/src/Main.elm", __DIR__)
    assert {:ok, module} = GeneratedParser.parse_file(fixture)

    defs =
      module.declarations
      |> Enum.filter(&(&1.kind == :function_definition))
      |> Map.new(&{&1.name, &1})

    assert defs["advanced"].expr.op == :let_in
    assert defs["advanced"].expr.in_expr.op == :if
    assert defs["requestWeather"].expr.op == :qualified_call
    assert defs["init"].expr.op == :let_in
    assert defs["view"].expr.op == :qualified_call
    assert defs["statusDraw"].expr.op == :let_in
    assert defs["statusDraw"].expr.in_expr.op == :case
    assert defs["main"].expr.op == :qualified_call
  end

  test "no unsupported nodes in simple project fixtures" do
    fixture_root = Path.expand("fixtures/simple_project/src", __DIR__)
    module_paths = Path.wildcard(Path.join(fixture_root, "**/*.elm"))
    assert module_paths != []

    Enum.each(module_paths, fn path ->
      assert {:ok, module} = GeneratedParser.parse_file(path)

      module.declarations
      |> Enum.filter(&(&1.kind == :function_definition))
      |> Enum.each(fn decl ->
        assert [] == collect_unsupported(decl.expr), "unsupported nodes in #{path}##{decl.name}"
      end)
    end)
  end

  defp collect_unsupported(%{op: :unsupported} = expr), do: [expr]

  defp collect_unsupported(expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn value ->
      cond do
        is_map(value) ->
          collect_unsupported(value)

        is_list(value) ->
          value
          |> Enum.flat_map(fn item ->
            if is_map(item), do: collect_unsupported(item), else: []
          end)

        true ->
          []
      end
    end)
  end

  defp collect_unsupported(_), do: []
end
