defmodule ElmEx.Frontend.LetLayoutEquivalenceTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedExpressionParser, LetLayout, Pretty}
  alias ElmEx.Test.LayoutTestSources

  @let_layout_path Path.expand("let_layout_test.exs", __DIR__)

  test "default parse matches layout lexer for let_layout multiline fixtures" do
    sources =
      @let_layout_path
      |> LayoutTestSources.extract_heredocs()
      |> Enum.filter(&layout_eligible?/1)
      |> Enum.filter(&parseable?/1)

    assert length(sources) >= 25,
           "expected most let_layout heredocs to be layout-eligible and parseable"

    Enum.each(sources, fn source ->
      assert {:ok, default_ast} = GeneratedExpressionParser.parse(source),
             "default parse failed for:\n#{preview(source)}"

      assert {:ok, layout_ast} = GeneratedExpressionParser.parse_with_layout_lexer(source),
             "layout lexer parse failed for:\n#{preview(source)}"

      assert default_ast == layout_ast, "AST mismatch for:\n#{preview(source)}"
    end)
  end

  @tag :layout_round_trip
  test "pretty round-trips layout-eligible let_layout heredocs" do
    sources =
      @let_layout_path
      |> LayoutTestSources.extract_heredocs()
      |> Enum.filter(&layout_eligible?/1)
      |> Enum.filter(&parseable?/1)

    failures =
      Enum.filter(sources, fn source ->
        not Pretty.round_trip?(source)
      end)

    assert failures == [],
           "round-trip failed for #{length(failures)} let_layout fixture(s):\n#{Enum.map_join(failures, "\n---\n", &preview/1)}"
  end

  @tag :layout_round_trip_ast
  test "pretty round-trip AST matches for layout-eligible let_layout heredocs" do
    sources =
      @let_layout_path
      |> LayoutTestSources.extract_heredocs()
      |> Enum.filter(&layout_eligible?/1)
      |> Enum.filter(&parseable?/1)

    failures =
      Enum.filter(sources, fn source ->
        Pretty.round_trip?(source) and not Pretty.round_trip_ast?(source)
      end)

    assert failures == [],
           "AST round-trip failed for #{length(failures)} let_layout fixture(s):\n#{Enum.map_join(failures, "\n---\n", &preview/1)}"
  end

  defp layout_eligible?(source) do
    String.contains?(source, "\n") and not String.contains?(source, ";;") and
      LetLayout.validate(source) == :ok
  end

  defp parseable?(source) do
    match?({:ok, _}, GeneratedExpressionParser.parse(source))
  end

  defp preview(source) do
    source
    |> String.split("\n")
    |> Enum.take(8)
    |> Enum.join("\n")
  end
end
