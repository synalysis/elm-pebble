defmodule ElmEx.Frontend.GeneratedParserMetadataTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedParser

  test "parse_source captures split-line module exposing lists" do
    source = """
    module SyntaxEdge exposing
        ( Model
        , backtickMod
        , pipelineSum
        )

    import List
    """

    assert {:ok, mod} = GeneratedParser.parse_source("SyntaxEdge.elm", source)
    assert mod.module_exposing == ["Model", "backtickMod", "pipelineSum"]
  end

  test "parse_source captures split-line port module exposing lists" do
    source = """
    port module HeaderVariants exposing
        ( Model
        , Msg(..)
        , init
        )

    import List as L exposing (foldl)
    """

    assert {:ok, mod} = GeneratedParser.parse_source("HeaderVariants.elm", source)
    assert mod.port_module
    assert mod.module_exposing == ["Model", "Msg(..)", "init"]
  end

  test "underscore-prefixed names stay a single function argument" do
    source = """
    module Main exposing (cellOp)

    cellOp : Int -> Int -> Int
    cellOp i _n =
        i
    """

    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)

    decl = Enum.find(mod.declarations, &(&1.kind == :function_definition and &1.name == "cellOp"))
    assert decl.args == ["i", "_n"]
  end
end
