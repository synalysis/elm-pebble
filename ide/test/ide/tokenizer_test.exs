defmodule Ide.TokenizerTest do
  use ExUnit.Case, async: true

  alias Ide.Tokenizer

  test "tokenizes keywords, identifiers and numbers" do
    source = "module Main exposing (main)\nvalue = 42"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.class == "keyword" and &1.text == "module"))
    assert Enum.any?(result.tokens, &(&1.class == "type_identifier" and &1.text == "Main"))
    assert Enum.any?(result.tokens, &(&1.class == "number" and &1.text == "42"))
    assert result.diagnostics == []
  end

  test "fast mode returns formatter parser payload for reuse" do
    source = "module Main exposing (main)\nimport Html\nmain = 42\n"
    result = Tokenizer.tokenize(source, mode: :fast)

    assert is_map(result.formatter_parser_payload)
    assert result.formatter_parser_payload.metadata.module == "Main"
    assert "Html" in result.formatter_parser_payload.metadata.imports
  end

  test "tokenizes hex and exponent numeric literals" do
    source = "a = 0xFF\nb = 1e-3\nc = 2.5E4\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "0xFF" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "1e-3" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "2.5E4" and &1.class == "number"))
  end

  test "tokenizes uppercase and mixed-case hex literals" do
    source = "a = 0XFF\nb = 0xAf09\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "0XFF" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "0xAf09" and &1.class == "number"))
  end

  test "keeps numeric boundary splitting for trailing dot, range, and invalid prefixes" do
    source = "a = 1.\nb = 1..2\nc = 0x\nd = 1e\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.line == 1 and &1.text == "1" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.line == 1 and &1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "1" and &1.class == "number"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ".." and &1.class == "operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "2" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.line == 3 and &1.text == "0" and &1.class == "number"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "x" and &1.class == "identifier")
           )

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == "1" and &1.class == "number"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "e" and &1.class == "identifier")
           )
  end

  test "marks record field labels distinctly in fast mode" do
    source = "{ value : Int, temperature : Maybe Int }"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "field_identifier"))

    assert Enum.any?(
             result.tokens,
             &(&1.text == "temperature" and &1.class == "field_identifier")
           )

    assert Enum.any?(result.tokens, &(&1.text == "Maybe" and &1.class == "type_identifier"))
  end

  test "reports uppercase record field labels in fast mode" do
    source = "type alias Abce =\n    { Abc : Int\n    }"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.diagnostics,
             &(&1.catalog_id == :unexpected_capital_letter and &1.line == 2 and &1.column == 7)
           )
  end

  test "reports unterminated string diagnostic" do
    source = "\"hello"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.class == "string"))
    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "ENDLESS STRING"))
  end

  test "stops regular string at newline and continues tokenizing next line" do
    source = "\"hello\nvalue = 1\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "string" and String.starts_with?(&1.text, "\"hello\n"))
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "ENDLESS STRING"))
  end

  test "stops regular string at CRLF and continues tokenizing next line" do
    source = "\"hello\r\nvalue = 1\r\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "string" and String.starts_with?(&1.text, "\"hello\r\n"))
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "ENDLESS STRING"))
  end

  test "tokenizes escaped double quotes inside strings" do
    source = "label = \"he\\\"llo\"\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "\"he\\\"llo\"" and &1.class == "string"))
    refute Enum.any?(result.diagnostics, &String.contains?(&1.message, "ENDLESS STRING"))
  end

  test "tokenizes multiline triple-quoted strings" do
    source = "view = \"\"\"line1\nline2\"\"\"\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "string" and String.starts_with?(&1.text, "\"\"\"line1"))
           )

    refute Enum.any?(result.diagnostics, &String.contains?(&1.message, "multiline string"))
  end

  test "reports unterminated multiline triple-quoted strings" do
    source = "view = \"\"\"line1\nline2\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "string" and String.starts_with?(&1.text, "\"\"\"line1"))
           )

    assert Enum.any?(
             result.diagnostics,
             &String.contains?(&1.message, "ENDLESS STRING")
           )
  end

  test "tokenizes Elm char literals including escapes" do
    source = "a = 'x'\nb = '\\n'\nc = '\\''\nd = '\\\\'\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "'x'" and &1.class == "string"))
    assert Enum.any?(result.tokens, &(&1.text == "'\\n'" and &1.class == "string"))
    assert Enum.any?(result.tokens, &(&1.text == "'\\''" and &1.class == "string"))
    assert Enum.any?(result.tokens, &(&1.text == "'\\\\'" and &1.class == "string"))
    refute Enum.any?(result.diagnostics, &String.contains?(&1.message, "MISSING SINGLE QUOTE"))
  end

  test "tokenizes Elm unicode escaped char literals" do
    source = "nbsp = '\\u{00A0}'\nmax = '\\u{10FFFF}'\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "'\\u{00A0}'" and &1.class == "string"))
    assert Enum.any?(result.tokens, &(&1.text == "'\\u{10FFFF}'" and &1.class == "string"))
    refute Enum.any?(result.diagnostics, &String.contains?(&1.message, "MISSING SINGLE QUOTE"))
  end

  test "reports invalid char literal diagnostics" do
    source = "bad = 'ab'\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.class == "string" and String.starts_with?(&1.text, "'")))

    assert Enum.any?(
             result.diagnostics,
             &(&1.catalog_id in [:missing_single_quote, :needs_double_quotes])
           )
  end

  test "reports invalid unicode escaped char literals" do
    source = "bad = '\\u{}'\ntooHigh = '\\u{110000}'\nsurrogate = '\\u{D800}'\n"
    result = Tokenizer.tokenize(source)

    assert Enum.count(
             result.tokens,
             &(&1.class == "string" and String.starts_with?(&1.text, "'"))
           ) >= 3

    assert Enum.count(
             result.diagnostics,
             &(&1.catalog_id in [:missing_single_quote, :bad_unicode_escape, :needs_double_quotes])
           ) >= 3
  end

  test "tokenizes nested block comments as a single comment token" do
    source = "{- outer {- inner -} done -}\nvalue = 1"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "comment" and String.starts_with?(&1.text, "{-"))
           )

    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "reports unterminated block comment diagnostic" do
    source = "{- comment\nvalue = 1"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.class == "comment"))

    assert Enum.any?(
             result.diagnostics,
             &String.contains?(&1.message, "ENDLESS COMMENT")
           )
  end

  test "reports delimiter diagnostics for mismatches" do
    source = "value = (1 + 2]"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.diagnostics,
             &String.contains?(&1.message, "STRAY CLOSING DELIMITER")
           )

    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "UNFINISHED PARENTHESES"))
  end

  test "tokenizes multi-character Elm operators as single operator tokens" do
    source =
      "step x = x |> f <| g\nsame = a == b && c /= d || e <= f >= g ++ h :: t\ncompose = f << g >> h\nbranch = if x > 0 then x else x -> y\n"

    result = Tokenizer.tokenize(source)

    for op <- ["|>", "<|", "==", "&&", "/=", "||", "<=", ">=", "++", "::", "<<", ">>", "->"] do
      assert Enum.any?(result.tokens, &(&1.text == op and &1.class == "operator"))
    end
  end

  test "tokenizes custom symbolic operators as single tokens" do
    source =
      "same = a <=> b\nuse = (<=>) a b\nmore = a <==> b\npipe = x ||> f\ntyped = a <:> b\ntag = a |: b\n"

    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "<=>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "(<=>)" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "<==>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "||>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "<:>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "|:" and &1.class == "operator"))
  end

  test "tokenizes backtick infix operators as single operator tokens" do
    source = "v = 10 `modBy` 3\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "`modBy`" and &1.class == "operator"))
  end

  test "tokenizes field accessor functions as field identifiers" do
    source = "getter = .value\nresult = List.map .temperature sensors\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))

    assert Enum.any?(
             result.tokens,
             &(&1.text == ".temperature" and &1.class == "field_identifier")
           )
  end

  test "marks dotted record field access as field identifiers" do
    source = "x = model.value\ny = model.user.name\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ".user" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ".name" and &1.class == "field_identifier")
           )
  end

  test "marks pipeline accessor with spacing as field identifier" do
    source = "x = model |> .value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor as field identifier" do
    source = "x = model|>.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor after qualified value token" do
    source = "x = List.map|>.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact reverse-pipeline accessor as field identifier" do
    source = "x = getModel<|.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "<|" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "does not report unfinished if for multiline let binding if expressions" do
    source = """
    view model =
        let
            batteryY =
                if model.isRound then
                    h // 8

                else
                    h // 28
        in
        batteryY
    """

    result = Tokenizer.tokenize(source)

    refute Enum.any?(result.diagnostics, &(&1.catalog_id == :unfinished_if))
    refute Enum.any?(result.diagnostics, &(&1.source == "tokenizer/expr_parser"))
  end

  test "marks compact reverse-pipeline accessor after qualified value token" do
    source = "x = List.map<|.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "<|" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact reverse-pipeline accessor with apostrophe field name" do
    source = "x = getModel<|.value'\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "<|" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value'" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor with apostrophe field name" do
    source = "x = model|>.value'\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value'" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor with underscore field name" do
    source = "x = model|>._value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "._value" and &1.class == "field_identifier"))
  end

  test "does not split compact pipeline accessor when field starts uppercase" do
    source = "x = model|>.Value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "Value" and &1.class == "type_identifier"))
  end

  test "does not split compact pipeline accessor when field starts with digit" do
    source = "x = model|>.1value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "|>." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "1" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not split unrelated custom operator ending in dot" do
    source = "x = model||>.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "||>." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not split compact pipeline accessor without adjacent left context" do
    source = "x = |> .value\ny = |>.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "|>" and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "|>." and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "does not split compact reverse-pipeline accessor without adjacent left context" do
    source = "x = <| .value\ny = <|.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "<|" and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "<|." and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "marks dotted access after closing delimiters as field identifiers" do
    source = "x = (model).value\ny = { model | value = 1 }.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ".value" and &1.class == "field_identifier")
           )
  end

  test "does not mark spaced dot operator usage as field access" do
    source = "x = a . b\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "b" and &1.class == "identifier"))
  end

  test "does not mark spaced type-like dot operator usage as field access" do
    source = "x = Type . value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark spaced type-like direct accessor usage as field access" do
    source = "x = Type .value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark numeric dot usage as field access" do
    source = "x = 1.x\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "x" and &1.class == "identifier"))
  end

  test "does not mark spaced numeric dot usage as field access" do
    source = "x = 1 .value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark string adjacency dot usage as field access" do
    source = "x = \"s\".value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark spaced string dot usage as field access" do
    source = "x = \"s\" .value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark hex or exponent numeric dot usage as field access" do
    source = "a = 0xFF.value\nb = 1e3.x\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.line == 1 and &1.text == "." and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "." and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "x" and &1.class == "identifier")
           )
  end

  test "tokenizes parenthesized field accessor functions as field identifiers" do
    source = "getter = (.value)\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(.value)" and &1.class == "field_identifier"))
  end

  test "tokenizes spaced parenthesized field accessor functions as field identifiers" do
    source = "getter = ( .value )\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "( .value )" and &1.class == "field_identifier"))
  end

  test "tokenizes multiline parenthesized field accessor functions as field identifiers" do
    source = "getter = (\n  .value\n  )\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "field_identifier" and String.starts_with?(&1.text, "(\n  .value"))
           )
  end

  test "tokenizes parenthesized operator sections as single operator tokens" do
    source = "inc = List.map (+) xs\npipe = (|>)\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(+)" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "(|>)" and &1.class == "operator"))
  end

  test "tokenizes spaced parenthesized operator sections as single operator tokens" do
    source = "inc = List.map ( + ) xs\npipe = ( |> )\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "( + )" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "( |> )" and &1.class == "operator"))
  end

  test "tokenizes multiline parenthesized operator sections as single operator tokens" do
    source = "pipe = (\n  |>\n)\npair = (\n  ,\n)\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "operator" and String.starts_with?(&1.text, "(\n  |>\n)"))
           )

    assert Enum.any?(
             result.tokens,
             &(&1.class == "operator" and String.starts_with?(&1.text, "(\n  ,\n)"))
           )
  end

  test "tokenizes tuple constructor operator sections as single operator tokens" do
    source = "pair = (,)\ntriple = (,,)\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(,)" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "(,,)" and &1.class == "operator"))
  end

  test "compiler mode applies elmc token classes" do
    source = "if flag then 1 else 0"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "if" and &1.class == "keyword"))
    assert Enum.any?(result.tokens, &(&1.text == "1" and &1.class == "number"))
  end

  test "compiler mode surfaces parser-aware diagnostics" do
    source = "value if = 1"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &String.starts_with?(&1.source, "tokenizer/"))
    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "BAD MODULE DECLARATION"))
  end

  test "parser diagnostics carry Elm-style catalog metadata" do
    source = "value if = 1"
    result = Tokenizer.tokenize(source, mode: :compiler)
    diagnostic = Enum.find(result.diagnostics, &String.starts_with?(&1.source, "tokenizer/"))

    assert is_map(diagnostic)
    assert diagnostic.catalog_id == :bad_module_declaration
    assert diagnostic.catalog_version == "elm-compiler-0.19.1-syntax-full-v1"
    assert diagnostic.elm_title == "BAD MODULE DECLARATION"
    assert is_binary(diagnostic.elm_hint)
  end

  test "fast tokenizer diagnostics carry canonical shape and spans" do
    source = "value = \"hello"
    result = Tokenizer.tokenize(source, mode: :fast)
    diagnostic = Enum.find(result.diagnostics, &(&1.source == "tokenizer"))

    assert is_map(diagnostic)
    assert diagnostic.catalog_id == :endless_string_single
    assert diagnostic.line == 1
    assert diagnostic.column == 9
    assert diagnostic.end_line == 1
    assert is_integer(diagnostic.end_column)
    assert String.contains?(diagnostic.message, "ENDLESS STRING")
  end

  test "compiler mode reports module parser diagnostic line" do
    source = """
    module Main exposing (main)
    import
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(&1.source == "tokenizer/module_parser" and
                 String.contains?(&1.message, "BAD MODULE DECLARATION") and
                 &1.line == 2)
           )
  end

  test "compiler mode reports invalid custom type header variables" do
    source = """
    module Main exposing (MyType)

    type MyType 19
        = FirstType
        | SecondType
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(&1.source == "tokenizer/decl_parser" and
                 String.contains?(&1.message, "Invalid type variable") and
                 &1.line == 3)
           )
  end

  test "compiler mode reports invalid type alias header variables" do
    source = """
    module Main exposing (Model)

    type alias Model 42 =
        { value : Int }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(&1.source == "tokenizer/decl_parser" and
                 String.contains?(&1.message, "Invalid type variable") and
                 &1.line == 3)
           )
  end

  test "compiler mode reports invalid custom type constructor heads" do
    source = """
    module Main exposing (Msg)

    type Msg
        = 19
        | Good
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(&1.source == "tokenizer/decl_parser" and
                 String.contains?(&1.message, "Invalid custom type constructor") and
                 &1.line == 4)
           )
  end

  test "compiler mode reports invalid port declaration headers" do
    source = """
    port module Main exposing (..)

    port send 19
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(&1.source == "tokenizer/decl_parser" and
                 String.contains?(&1.message, "Invalid port declaration header") and
                 &1.line == 3)
           )
  end

  test "compiler mode recovers after unterminated regular string newline" do
    source = "\"hello\nvalue = 1\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "ENDLESS STRING"))
  end

  test "compiler mode recovers after unterminated regular string CRLF newline" do
    source = "\"hello\r\nvalue = 1\r\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "ENDLESS STRING"))
  end

  test "compiler mode infers diagnostic columns for malformed input" do
    source = "value = @"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(String.starts_with?(&1.source, "tokenizer/") and
                 is_integer(&1.column) and
                 is_integer(&1[:end_column]) and
                 &1.column >= 1 and
                 &1.end_column >= &1.column)
           )
  end

  test "compiler mode keeps type annotation identifiers aligned" do
    source = """
    type alias Model =
        { value : Int, temperature : Maybe Int }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    maybe =
      Enum.find(result.tokens, fn t ->
        t.line == 2 and t.text == "Maybe"
      end)

    ints =
      result.tokens
      |> Enum.filter(fn t ->
        t.line == 2 and t.text == "Int"
      end)

    assert maybe
    assert maybe.class == "type_identifier"
    assert length(ints) == 2
    assert Enum.all?(ints, &(&1.class == "type_identifier"))
  end

  test "compiler mode marks record field labels distinctly" do
    source = """
    type alias Model =
        { value : Int, temperature : Maybe Int }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "field_identifier"))

    assert Enum.any?(
             result.tokens,
             &(&1.text == "temperature" and &1.class == "field_identifier")
           )
  end

  test "compiler mode marks module/type constructors as type identifiers" do
    source = "module Main exposing (main)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "Main" and &1.class == "type_identifier"))
  end

  test "marks arrows in type annotations as type operators" do
    source = """
    f : Int -> Maybe Int
    f x = x
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "->" and &1.class == "type_operator")
           )
  end

  test "marks operator function annotations as type operators in fast mode" do
    source = """
    (+) : Int -> Int -> Int
    (+) a b = a + b
    """

    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "=" and &1.class == "operator"))
  end

  test "marks operator function annotations as type operators in compiler mode" do
    source = """
    (+) : Int -> Int -> Int
    (+) a b = a + b
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "=" and &1.class == "operator"))
  end

  test "does not treat grouped expression lines with colon as annotations in fast mode" do
    source = """
    view model =
      let
        bad =
          (model) : value
      in
      bad
    """

    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == ":" and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "does not treat grouped expression lines with colon as annotations in compiler mode" do
    source = """
    view model =
      let
        bad =
          (model) : value
      in
      bad
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == ":" and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "fast mode does not treat case branch record literals as type annotations" do
    source = """
    view msg =
      case msg of
        Got x ->
          { value : x }
    """

    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == ":" and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "x" and &1.class == "identifier")
           )
  end

  test "keeps case arrows as normal operators" do
    source = """
    update msg model =
      case msg of
        Tick ->
          model
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "->" and &1.class == "operator")
           )
  end

  test "does not treat case branch record literals as type annotations" do
    source = """
    view msg =
      case msg of
        Got x ->
          { value : x }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == ":" and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "x" and &1.class == "identifier")
           )
  end

  test "does not treat lambda branch record literals as type annotations" do
    source = "f = \\x -> { value : x }\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "->" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ":" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "x" and &1.class == "identifier"))
  end

  test "marks wrapped arrows in multiline type annotations as type operators" do
    source = """
    f :
      Int
      -> Maybe Int
    f x = x
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "->" and &1.class == "type_operator")
           )
  end

  test "marks pipes in multiline custom type declarations as type operators" do
    source = """
    type Msg
      = Tick
      | Set Int
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "|" and &1.class == "type_operator")
           )
  end

  test "marks equals in custom type declarations as type operators" do
    source = "type Msg = Tick | Set Int\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "=" and &1.class == "type_operator"))
  end

  test "marks tuple/record/list punctuation in custom type declarations as type operators" do
    source = """
    type Msg a
      = Pair ( a, Int )
      | Wrap { value : a, items : List a }
      | Items [ a ]
    pair = ( 1, 2 )
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    for op <- ["(", ")", ",", "{", "}", ":", "[", "]"] do
      assert Enum.any?(
               result.tokens,
               &(&1.line in [2, 3, 4] and &1.text == op and &1.class == "type_operator")
             )
    end

    assert Enum.any?(result.tokens, &(&1.line == 5 and &1.text == "," and &1.class == "operator"))
  end

  test "marks lowercase identifiers in custom type declarations as type identifiers" do
    source = """
    type Msg msg
      = Tick
      | Set msg
      | Wrap (Maybe msg)
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "msg" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "msg" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "msg" and &1.class == "type_identifier")
           )
  end

  test "keeps record update pipe as normal operator" do
    source = "next = { model | value = 1 }\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|" and &1.class == "operator"))
  end

  test "keeps value-binding equals as normal operator" do
    source = "value = 1\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "=" and &1.class == "operator"))
  end

  test "keeps value-level identifiers outside type declarations unchanged" do
    source = "update msg model = model\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "msg" and &1.class == "identifier"))
    assert Enum.any?(result.tokens, &(&1.text == "model" and &1.class == "identifier"))
  end

  test "marks colons in type alias record fields as type operators" do
    source = """
    type alias Model =
      { value : Int
      , temperature : Maybe Int
      }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == ":" and &1.class == "type_operator")
           )
  end

  test "marks type variables in type alias heads as type identifiers" do
    source = """
    type alias Box a msg =
      { value : a
      , tag : msg
      }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "a" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "msg" and &1.class == "type_identifier")
           )
  end

  test "marks type identifiers inside type alias record bodies" do
    source = """
    type alias Box a msg =
      { value : a
      , nested : Maybe msg
      }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "a" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "msg" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "field_identifier")
           )
  end

  test "marks extensible record vars in type alias bodies as type identifiers" do
    source = """
    type alias Ext a =
      { a | value : Int }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "a" and &1.class == "type_identifier")
           )
  end

  test "marks extensible record operators in type alias bodies as type operators" do
    source = """
    type alias Ext a =
      { a | value : Int }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "|" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ":" and &1.class == "type_operator")
           )
  end

  test "marks annotation colon as type operator" do
    source = """
    value : Int
    value = 1
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "=" and &1.class == "operator"))
  end

  test "marks lowercase identifiers in type annotation context as type identifiers" do
    source = """
    toKey : comparable -> String
    id :
      a
      -> a
    id x = x
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "toKey" and &1.class == "identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "comparable" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "a" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "a" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "id" and &1.class == "identifier")
           )
  end

  test "marks constrained record extension vars in annotations as type identifiers" do
    source = "update : { a | value : Int } -> a -> a\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "a" and &1.class == "type_identifier"))
  end

  test "marks constrained record extension pipe in annotations as type operator" do
    source = "update : { a | value : Int } -> a -> a\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|" and &1.class == "type_operator"))
  end

  test "marks constrained record field colons in annotations as type operator" do
    source = "update : { a | value : Int, next : Maybe Int } -> a -> a\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    colon_tokens =
      result.tokens
      |> Enum.filter(&(&1.text == ":" and &1.class == "type_operator"))

    assert length(colon_tokens) >= 2
  end

  test "marks tuple and unit punctuation in annotations as type operators" do
    source = """
    pair : ( Int, Maybe a ) -> ()
    pair = ( 1, Just 2 )
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "(" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ")" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "," and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "," and &1.class == "operator"))
  end

  test "marks list and record delimiters in annotations as type operators" do
    source = """
    decode : List (List Int) -> { value : Int }
    decode = [ 1, 2 ]
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "{" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "}" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "[" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "]" and &1.class == "operator"))
  end

  test "marks multiline type alias head/body identifiers and punctuation" do
    source = """
    type alias Pair
      a
      b
      =
      ( a, Maybe b )
    pair = ( 1, 2 )
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "a" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "b" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "=" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 5 and &1.text == "(" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 5 and &1.text == "," and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 6 and &1.text == "," and &1.class == "operator"))
  end

  test "keeps multiline annotation typing across blank and comment lines" do
    source = """
    decode :
      -- decoder pipeline
      Int

      -> Maybe Int
    decode x = Just x
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 5 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 5 and &1.text == "Maybe" and &1.class == "type_identifier")
           )

    assert Enum.any?(result.tokens, &(&1.line == 6 and &1.text == "=" and &1.class == "operator"))
  end

  test "keeps type alias typing across blank and comment lines" do
    source = """
    type alias Box
      a

      -- body starts below
      =
      { value : a
      }
    box = { value = 1 }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "a" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 5 and &1.text == "=" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 6 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 8 and &1.text == "=" and &1.class == "operator"))
  end

  test "applies type context styling in port annotations" do
    source = """
    port module Main exposing (..)
    port send :
      { a | value : Int }
      -> Cmd msg
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "port" and &1.class == "keyword")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "send" and &1.class == "identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "|" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "msg" and &1.class == "type_identifier")
           )
  end

  test "keeps non-type punctuation in port module header as regular operator" do
    source = "port module Main exposing (..)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "(..)" and &1.class == "operator"))
  end

  test "keeps constructor and bound variables distinct in case patterns" do
    source = """
    update msg model =
      case msg of
        Set value ->
          { model | value = value }
        None ->
          model
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "Set" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 5 and &1.text == "None" and &1.class == "type_identifier")
           )
  end

  test "keeps nested pattern variables as identifiers" do
    source = """
    view msg =
      case msg of
        Wrap (Just value) ->
          value
        _ ->
          0
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "Wrap" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "Just" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "applies type styling to let-local annotations" do
    source = """
    view model =
      let
        helper : Int -> String
        helper n = String.fromInt n
      in
      helper model.value
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "Int" and &1.class == "type_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "String" and &1.class == "type_identifier")
           )

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == "=" and &1.class == "operator"))
  end

  test "keeps wrapped let-local annotation context across blank lines" do
    source = """
    update msg model =
      let
        step :
          Msg

          -> Model
          -> Model
        step incoming current = current
      in
      step msg model
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 6 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 7 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 8 and &1.text == "=" and &1.class == "operator"))
  end

  test "keeps nested let annotation styling scoped" do
    source = """
    view model =
      let
        outer : Int -> Int
        outer n =
          let
            inner : Int -> Int
            inner x = x
          in
          inner n
      in
      outer model.value
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 6 and &1.text == ":" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 6 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 7 and &1.text == "=" and &1.class == "operator"))
  end

  test "does not leak annotation styling into later case branches" do
    source = """
    update msg model =
      let
        decoder : Int -> Int
        decoder n = n
      in
      case msg of
        Set value ->
          decoder value
        None ->
          0
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "->" and &1.class == "type_operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 7 and &1.text == "->" and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 9 and &1.text == "->" and &1.class == "operator")
           )
  end

  test "tokenizes qualified upper identifiers as one token" do
    source = "import Json.Decode exposing (Decoder)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "Json.Decode" and &1.class == "type_identifier"))
    assert Enum.any?(result.tokens, &(&1.text == "Decoder" and &1.class == "type_identifier"))
  end

  test "classifies qualified value names as identifiers in fast mode" do
    source = "decode = Json.Decode.decodeString parser input\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.text == "Json.Decode.decodeString" and &1.class == "identifier")
           )
  end

  test "classifies qualified value names with apostrophe as identifiers in fast mode" do
    source = "decode = Json.Decode.decode' parser input\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(
             result.tokens,
             &(&1.text == "Json.Decode.decode'" and &1.class == "identifier")
           )
  end

  test "keeps qualified value names as identifiers in compiler mode" do
    source = "decode = Json.Decode.decodeString parser input\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.text == "Json.Decode.decodeString" and &1.class == "identifier")
           )
  end

  test "keeps qualified value names with apostrophe as identifiers in compiler mode" do
    source = "decode = Json.Decode.decode' parser input\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.text == "Json.Decode.decode'" and &1.class == "identifier")
           )
  end

  test "keeps hex and exponent numeric literals in compiler mode" do
    source = "a = 0xFF\nb = 1e-3\nc = 2.5E4\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "0xFF" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "1e-3" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "2.5E4" and &1.class == "number"))
  end

  test "keeps uppercase and mixed-case hex literals in compiler mode" do
    source = "a = 0XFF\nb = 0xAf09\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "0XFF" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "0xAf09" and &1.class == "number"))
  end

  test "keeps escaped apostrophe and backslash char literals in compiler mode" do
    source = "a = '\\''\nb = '\\\\'\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "'\\''" and &1.class == "string"))
    assert Enum.any?(result.tokens, &(&1.text == "'\\\\'" and &1.class == "string"))
    refute Enum.any?(result.diagnostics, &String.contains?(&1.message, "MISSING SINGLE QUOTE"))
  end

  test "keeps composition operators as single operators in compiler mode" do
    source = "compose = f << g >> h\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "<<" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ">>" and &1.class == "operator"))
  end

  test "keeps tuple constructor operator sections in compiler mode" do
    source = "pair = (,)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "(,)" and &1.class == "operator"))
  end

  test "keeps spaced parenthesized operator sections in compiler mode" do
    source = "inc = List.map ( + ) xs\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "( + )" and &1.class == "operator"))
  end

  test "keeps multiline parenthesized operator sections in compiler mode" do
    source = "pipe = (\n  |>\n)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "operator" and String.starts_with?(&1.text, "(\n  |>\n)"))
           )
  end

  test "malformed multiline operator section recovers without hanging" do
    source = "pipe = (\n  |>\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "UNFINISHED PARENTHESES"))
  end

  test "malformed multiline accessor section recovers without hanging" do
    source = "getter = (\n  .value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "UNFINISHED PARENTHESES"))
  end

  test "malformed multiline sections recover in compiler mode" do
    source = "pipe = (\n  |>\ngetter = (\n  .value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "(" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
    assert Enum.any?(result.diagnostics, &String.contains?(&1.message, "UNFINISHED PARENTHESES"))
  end

  test "keeps custom symbolic operators as single tokens in compiler mode" do
    source = "same = a <=> b\nmore = a <==> b\npipe = x ||> f\ntyped = a <:> b\ntag = a |: b\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "<=>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "<==>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "||>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "<:>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "|:" and &1.class == "operator"))
  end

  test "keeps numeric boundary splitting in compiler mode" do
    source = "a = 1.\nb = 1..2\nc = 0x\nd = 1e\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.line == 1 and &1.text == "1" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.line == 1 and &1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "1" and &1.class == "number"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ".." and &1.class == "operator")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "2" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.line == 3 and &1.text == "0" and &1.class == "number"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 3 and &1.text == "x" and &1.class == "identifier")
           )

    assert Enum.any?(result.tokens, &(&1.line == 4 and &1.text == "1" and &1.class == "number"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 4 and &1.text == "e" and &1.class == "identifier")
           )
  end

  test "keeps uppercase invalid hex boundary splitting in compiler mode" do
    source = "a = 0X\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "0" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "X" and &1.class == "type_identifier"))
  end

  test "keeps field accessors as field identifiers in compiler mode" do
    source = "result = List.map .value records\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks dotted record field access in compiler mode without changing qualified value calls" do
    source = "x = model.value\nd = Json.Decode.decodeString parser input\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "Json.Decode.decodeString" and &1.class == "identifier")
           )
  end

  test "marks pipeline accessor with spacing as field identifier in compiler mode" do
    source = "x = model |> .value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor as field identifier in compiler mode" do
    source = "x = model|>.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor after qualified value token in compiler mode" do
    source = "x = List.map|>.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact reverse-pipeline accessor as field identifier in compiler mode" do
    source = "x = getModel<|.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "<|" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact reverse-pipeline accessor after qualified value token in compiler mode" do
    source = "x = List.map<|.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "<|" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value" and &1.class == "field_identifier"))
  end

  test "marks compact reverse-pipeline accessor with apostrophe field name in compiler mode" do
    source = "x = getModel<|.value'\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "<|" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value'" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor with apostrophe field name in compiler mode" do
    source = "x = model|>.value'\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == ".value'" and &1.class == "field_identifier"))
  end

  test "marks compact pipeline accessor with underscore field name in compiler mode" do
    source = "x = model|>._value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "._value" and &1.class == "field_identifier"))
  end

  test "does not split compact pipeline accessor when field starts uppercase in compiler mode" do
    source = "x = model|>.Value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "Value" and &1.class == "type_identifier"))
  end

  test "does not split compact pipeline accessor when field starts with digit in compiler mode" do
    source = "x = model|>.1value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "|>." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "1" and &1.class == "number"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not split unrelated custom operator ending in dot in compiler mode" do
    source = "x = model||>.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "||>." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not split compact pipeline accessor without adjacent left context in compiler mode" do
    source = "x = |> .value\ny = |>.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "|>" and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "|>." and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "does not split compact reverse-pipeline accessor without adjacent left context in compiler mode" do
    source = "x = <| .value\ny = <|.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "<|" and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "<|." and &1.class == "operator")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "value" and &1.class == "identifier")
           )
  end

  test "marks dotted access after closing delimiters in compiler mode" do
    source = "x = (model).value\ny = { model | value = 1 }.value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == ".value" and &1.class == "field_identifier")
           )

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == ".value" and &1.class == "field_identifier")
           )
  end

  test "does not mark spaced dot operator usage as field access in compiler mode" do
    source = "x = a . b\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "b" and &1.class == "identifier"))
  end

  test "does not mark spaced type-like dot operator usage as field access in compiler mode" do
    source = "x = Type . value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark spaced type-like direct accessor usage as field access in compiler mode" do
    source = "x = Type .value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark numeric dot usage as field access in compiler mode" do
    source = "x = 1.x\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "x" and &1.class == "identifier"))
  end

  test "does not mark spaced numeric dot usage as field access in compiler mode" do
    source = "x = 1 .value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark string adjacency dot usage as field access in compiler mode" do
    source = "x = \"s\".value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark spaced string dot usage as field access in compiler mode" do
    source = "x = \"s\" .value\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "does not mark hex or exponent numeric dot usage as field access in compiler mode" do
    source = "a = 0xFF.value\nb = 1e3.x\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.line == 1 and &1.text == "." and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 1 and &1.text == "value" and &1.class == "identifier")
           )

    assert Enum.any?(result.tokens, &(&1.line == 2 and &1.text == "." and &1.class == "operator"))

    assert Enum.any?(
             result.tokens,
             &(&1.line == 2 and &1.text == "x" and &1.class == "identifier")
           )
  end

  test "keeps parenthesized field accessors as field identifiers in compiler mode" do
    source = "getter = (.value)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "(.value)" and &1.class == "field_identifier"))
  end

  test "keeps spaced parenthesized field accessors as field identifiers in compiler mode" do
    source = "getter = ( .value )\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "( .value )" and &1.class == "field_identifier"))
  end

  test "keeps multiline parenthesized field accessors as field identifiers in compiler mode" do
    source = "getter = (\n  .value\n  )\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.tokens,
             &(&1.class == "field_identifier" and String.starts_with?(&1.text, "(\n  .value"))
           )
  end

  test "keeps operator section dot distinct from parenthesized field accessor" do
    source = "compose = (.)\ngetter = (.value)\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(.)" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "(.value)" and &1.class == "field_identifier"))
  end

  test "keeps operator section dot distinct in compiler mode" do
    source = "compose = (.)\ngetter = (.value)\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "(.)" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "(.value)" and &1.class == "field_identifier"))
  end

  test "invalid parenthesized field accessor falls back without hanging" do
    source = "getter = (.value\n"
    result = Tokenizer.tokenize(source)

    assert Enum.any?(result.tokens, &(&1.text == "(" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
  end

  test "invalid parenthesized field accessor falls back in compiler mode" do
    source = "getter = (.value!\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.tokens, &(&1.text == "(" and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "." and &1.class == "operator"))
    assert Enum.any?(result.tokens, &(&1.text == "value" and &1.class == "identifier"))
    assert Enum.any?(result.tokens, &(&1.text == "!" and &1.class == "operator"))
  end

  test "compiler mode reports unknown string escapes" do
    source = "value = \"hello\\q\"\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :unknown_escape))
  end

  test "compiler mode reports bad unicode escapes in strings" do
    source = "value = \"\\u{1}\"\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :bad_unicode_escape))
  end

  test "compiler mode reports leading zeros and weird hexidecimal numbers" do
    source = "a = 012\nb = 0x\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :leading_zeros))
    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :weird_hexidecimal))
  end

  test "compiler mode reports unfinished list and record delimiters" do
    source = "list = [1, 2\nrecord = { value = 1\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :unfinished_list))
    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :unfinished_record))
  end

  test "compiler mode reports unfinished if expression via expr parser" do
    source = "value = if ok then 1\n"
    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :unfinished_if))
  end

  test "compiler mode reports expecting import alias for malformed import" do
    source = """
    module Main exposing (..)
    import Html as exposing (text)
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(result.diagnostics, &(&1.catalog_id == :expecting_import_alias))
  end

  test "compiler mode reports expecting type name for malformed type declaration" do
    source = """
    module Main exposing (..)
    type = A
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    assert Enum.any?(
             result.diagnostics,
             &(&1.catalog_id in [:expecting_type_name, :problem_in_custom_type])
           )
  end

  test "compiler mode does not flag valid multiline type alias as missing alias name" do
    source = """
    type alias Model =
        { hour : Int
        , minute : Int
        , screenW : Int
        , screenH : Int
        }
    """

    result = Tokenizer.tokenize(source, mode: :compiler)

    refute Enum.any?(result.diagnostics, &(&1.catalog_id == :expecting_type_alias_name))
  end

  test "compiler mode does not emit expr parser false positives for watchface templates" do
    template_files = [
      Path.expand("../../priv/project_templates/watchface_digital/src/Main.elm", __DIR__),
      Path.expand("../../priv/project_templates/watchface_analog/src/Main.elm", __DIR__)
    ]

    Enum.each(template_files, fn path ->
      source = File.read!(path)
      result = Tokenizer.tokenize(source, mode: :compiler)

      refute Enum.any?(result.diagnostics, fn diagnostic ->
               diagnostic.source == "tokenizer/expr_parser" and
                 diagnostic.catalog_id == :missing_expression
             end)
    end)
  end
end
