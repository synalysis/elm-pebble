defmodule ElmEx.TreeSitterCorpusRegressionsTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{AstContract, GeneratedParser}

  test "parses Elm unicode surrogate pair escapes in string literals" do
  source = """
  module UnicodeSurrogate exposing (value)

  value : String
  value =
      "\\u{D835}\\u{DD04}"
  """

    assert {:ok, module} = GeneratedParser.parse_source("UnicodeSurrogate.elm", source)

    decl =
      Enum.find(module.declarations, &(&1.kind == :function_definition and &1.name == "value"))

    assert %{expr: %{op: :string_literal, value: value}} = decl
    assert String.length(value) == 1
    assert :ok = AstContract.validate_module(module)
  end

  test "validates nested field_call receiver expressions" do
    expr = %{
      op: :field_call,
      arg: %{
        op: :field_call,
        arg: "propertiesApi",
        field: "declarable",
        args: [%{op: :var, name: "decl"}]
      },
      field: "getOptionalEnumProperty",
      args: [%{op: :var, name: "jsonCodingEnum"}, %{op: :string_literal, value: "jsonCoding"}]
    }

    module = %ElmEx.Frontend.Module{
      name: "Main",
      path: "Main.elm",
      imports: [],
      declarations: [
        %{
          kind: :function_definition,
          name: "main",
          args: [],
          expr: expr,
          span: %{start_line: 1, end_line: 1}
        }
      ]
    }

    assert :ok = AstContract.validate_module(module)
  end

  test "parses import-first modules without an explicit module header" do
    source = """
    import Html exposing (Html, text)

    main =
        text "hi"
    """

    assert {:ok, module} = GeneratedParser.parse_source("examples/Hello.elm", source)
    assert module.name == "Hello"
    assert Enum.any?(module.declarations, &(&1.name == "main"))
    assert :ok = AstContract.validate_module(module)
  end

  test "infers module names from src directory paths" do
    assert GeneratedParser.infer_module_name_from_path(
             "vendor/pkg/src/Templates/App/AppWithTick.elm"
           ) == "Templates.App.AppWithTick"
  end

  test "parses real corpus fixtures for unicode refs and headerless templates" do
    if ElmEx.Test.TreeSitterCorpus.available?() do
      corpus = ElmEx.Test.TreeSitterCorpus.corpus_dir()

      for rel <- [
            "hecrj/html-parser/src/Html/Parser/NamedCharacterReferences.elm",
            "MacCASOutreach/graphicsvg/src/Templates/App/AppWithTick.elm",
            "the-sett/salix/src/Elm/Json/Coding.elm"
          ] do
        path = Path.join(corpus, rel)
        assert {:ok, _module} = GeneratedParser.parse_file(path), "expected parse ok for #{rel}"
      end
    else
      IO.puts("Skipping corpus fixture regressions")
    end
  end
end
