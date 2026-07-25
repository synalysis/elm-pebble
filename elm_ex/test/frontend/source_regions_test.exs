defmodule ElmEx.Frontend.SourceRegionsTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.SourceRegions

  test "extracts preamble, header, imports, and body start for block-comment module" do
    source = """
    {- AD -}


    module {- A -} Example exposing (a)

    {- J -}

    import Foo

    {- AF -}


    a =
        1
    """

    regions = SourceRegions.extract(source)

    assert regions.preamble == "{- AD -}\n\n\n"
    assert String.starts_with?(regions.header, "module {- A -} Example")
    assert regions.pre_import == "\n{- J -}\n\n"
    assert regions.imports == "import Foo\n"
    assert regions.pre_body == "\n{- AF -}\n\n\n"
    assert regions.body_line_start == 13
  end

  test "keeps module doc comments in pre_import before imports" do
    source = """
    module Comments exposing (fn)

    {-| Module docs

    -}

    -- before imports

    import Foo
    """

    regions = SourceRegions.extract(source)

    assert regions.pre_import =~ "{-| Module docs"
    assert regions.pre_import =~ "-- before imports"
    assert regions.imports == "import Foo\n"
    assert regions.body_line_start == 11
  end

  test "keeps module doc comments in pre_body before declarations" do
    source = """
    module Main exposing (x)

    import Foo

    {-|

    @docs x

    -}


    x =
        ()
    """

    regions = SourceRegions.extract(source)

    assert regions.pre_body =~ "{-|"
    assert regions.pre_body =~ "@docs x"
    assert regions.body_line_start == 12
  end

  test "preserves inline block comments in function headers" do
    source = """
    module Example exposing (unit)

    data (Foo {- Q -} x {- R -} y) =
        ()
    """

    {:ok, formatted} =
      ElmEx.Frontend.Pretty.format_module_source_preserve("Example.elm", source)

    assert formatted =~ "data (Foo {- Q -} x {- R -} y) ="
  end

  test "preserves multiline signatures with comments" do
    source = """
    module Example exposing (record)

    record :
        { {- N -} x {- O -} : {- P -} Int
        }
        -> ()
    record _ =
        ()
    """

    {:ok, formatted} =
      ElmEx.Frontend.Pretty.format_module_source_preserve("Example.elm", source)

    assert formatted =~ "{ {- N -} x {- O -} : {- P -} Int"
    assert formatted =~ "record _ ="
  end

  test "ignores example Elm code inside module doc comments when locating body start" do
    source = """
    module Main exposing (x)

    {-|

    ## Elm code block: expressions

        x == ()

    -}

    x =
        ()
    """

    regions = SourceRegions.extract(source)

    assert regions.pre_import =~ "## Elm code block: expressions"
    assert regions.body_line_start == 11
  end

  test "extracts effect module header with interleaved block comments" do
    source = """
    effect {- T -} module {- A -} Example {- B -} where {- C -} { command = MyCmd, subscription = MySub } {- L -} exposing (a)


    type MyCmd msg
        = MyCmd msg
    """

    regions = SourceRegions.extract(source)

    assert regions.preamble == ""
    assert String.starts_with?(regions.header, "effect {- T -} module")
    assert regions.pre_import == "\n\n"
    assert regions.body_line_start == 4
  end

  test "stitch combines preserved regions with formatted declarations" do
    regions = %{
      preamble: "{- AD -}\n\n",
      header: "module Example exposing (a)\n",
      pre_import: "\n",
      imports: "import Foo\n",
      pre_body: "\n\n",
      body_line_start: 1
    }

    assert SourceRegions.stitch(regions, "a =\n    1\n") ==
             "{- AD -}\n\nmodule Example exposing (a)\n\nimport Foo\n\n\na =\n    1\n"
  end
end
