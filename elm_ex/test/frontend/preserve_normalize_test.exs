defmodule ElmEx.Frontend.Pretty.PreserveNormalizeTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedParser, Module, Pretty.PreserveNormalize, SourceRegions}

  test "collapses full constructor exposing lists to (..) while preserving comments" do
    source = """
    module Example exposing (a)

    import {- M -} Maybe {- N -} exposing {- O -} ({- S -} Maybe {- W -} ({- X -} Just {- Y -}, {- Z -} Nothing {- AA -}) {- T -}, {- U -} map {- V -})
    """

    {:ok, mod} = GeneratedParser.parse_source("Example.elm", source)
    regions = SourceRegions.extract(source)

    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.imports =~
             "import {- M -} Maybe {- N -} exposing {- O -} ({- S -} Maybe(..) {- W -} {- T -}, {- U -} map {- V -})"
  end

  test "leaves simple exposing imports unchanged" do
    source = """
    module Example exposing (unit)

    import Dict exposing (Dict)
    """

    {:ok, mod} = GeneratedParser.parse_source("Example.elm", source)
    regions = SourceRegions.extract(source)

    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.imports == "import Dict exposing (Dict)\n"
  end

  test "normalizes multiline module exposing layout in preserved headers" do
    regions = %{
      preamble: "",
      header:
        "module\n    --A\n    Example\n    exposing\n    (  --C\n       a\n       --D\n\n    ,  --E\n       b\n    )\n",
      pre_import: "",
      imports: "",
      pre_body: "",
      body_line_start: 1
    }

    mod = %Module{
      name: "Example",
      path: "Example.elm",
      imports: [],
      declarations: []
    }

    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.header =~ "( --C\n      a\n      --D\n    , --E\n      b\n    )"
    refute normalized.header =~ "(  --C"
  end

  test "collapses multiline Maybe exposing in preserved imports" do
    source = """
    module Example exposing (a)

    import
        --M
        Maybe
            --N
            exposing
                --O
                ( --S
                  Maybe
                  --W
                    ( --X
                      Just
                    , Nothing
                    )
                  --T
                , map
                )
    """

    {:ok, mod} = GeneratedParser.parse_source("Example.elm", source)
    regions = SourceRegions.extract(source)
    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.imports =~ "Maybe(..)"
    assert normalized.imports =~ "--W"
    assert normalized.imports =~ "--T"
  end

  test "collapses compact multi-constructor import exposing" do
    source = """
    module Example exposing (a)

    import Maybe exposing (Maybe(Just, Nothing), map)
    """

    {:ok, mod} = GeneratedParser.parse_source("Example.elm", source)
    regions = SourceRegions.extract(source)
    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.imports =~ "Maybe(..)"
    refute normalized.imports =~ "Maybe(Just, Nothing)"
  end

  test "collapses compact multi-constructor exposing in module headers" do
    regions = %{
      preamble: "",
      header: "module Example exposing (Data(A, B, C))\n",
      pre_import: "",
      imports: "",
      pre_body: "",
      body_line_start: 1
    }

    mod = %Module{
      name: "Example",
      path: "Example.elm",
      imports: [],
      declarations: []
    }

    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.header =~ "Data(..)"
    refute normalized.header =~ "Data(A, B, C)"
  end

  test "collapses single-constructor exposing in module headers" do
    regions = %{
      preamble: "",
      header: "module Example exposing (CustomType(TagA))\n",
      pre_import: "",
      imports: "",
      pre_body: "",
      body_line_start: 1
    }

    mod = %Module{
      name: "Example",
      path: "Example.elm",
      imports: [],
      declarations: []
    }

    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.header =~ "CustomType(..)"
    refute normalized.header =~ "CustomType(TagA)"
  end

  test "normalizes Elm 0.16 module headers to exposing syntax" do
    regions = %{
      preamble: "",
      header: "module Main (..) where\n",
      pre_import: "",
      imports: "",
      pre_body: "",
      body_line_start: 1
    }

    mod = %Module{
      name: "Main",
      path: "Main.elm",
      imports: [],
      declarations: []
    }

    normalized = PreserveNormalize.normalize_regions(regions, mod)

    assert normalized.header == "module Main exposing (..)\n"
  end
end
