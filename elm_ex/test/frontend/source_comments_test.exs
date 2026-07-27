defmodule ElmEx.Frontend.SourceCommentsTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedParser, Pretty, SourceComments}

  test "extracts declaration doc comments" do
    source = """
    module Main exposing (value)

    {-| Docs
    -}
    value : Int
    value = 1
    """

    {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)
    comments = SourceComments.extract("Main.elm", source, mod)

    assert Enum.any?(comments, fn c -> c.kind == :doc and String.contains?(c.text, "Docs") end)
  end

  test "extracts doc comments with nested inner doc blocks" do
    source = """
    module Main exposing (y)

    {-| Top-level docs
        {-| Inner docs
        -}
        invisible : Style
    -}
    y = 1
    """

    {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)
    comments = SourceComments.extract("Main.elm", source, mod)

    assert [%{kind: :doc, after_name: "y"}] =
             Enum.filter(comments, fn c -> c.kind == :doc end)
  end

  test "format_module_source_preserve merges doc comments into declarations" do
    source = """
    module Main exposing (value)

    {-| Docs
    -}
    value : Int
    value = 1
    """

    assert {:ok, formatted} = Pretty.format_module_source_preserve("Main.elm", source, [])
    assert String.contains?(formatted, "{-| Docs")
    assert String.contains?(formatted, "value : Int")
  end

  test "format_module_source_preserve attaches doc comments before infix-named functions" do
    source = """
    module Main exposing (..)

    {-| As top-level declaration
    -}
    infix x =
        ()
    """

    assert {:ok, formatted} = Pretty.format_module_source_preserve("Main.elm", source, [])

    assert formatted =~ ~r/\{-\\| As top-level declaration\n-\}\ninfix x =\n    \(\)\n/u
  end
end
