defmodule Elmc.FrontendGeneratedArtifactsTest do
  use ExUnit.Case

  test "leex tokenizes module/import/port header metadata tokens" do
    source = """
    port module Main exposing (main, Msg(..))

    import List
    import Pebble.Platform as PebblePlatform exposing (worker)
    port toJs : String -> Cmd msg
    """

    assert {:ok, tokens, _} = :elm_ex_elm_lexer.string(String.to_charlist(source))

    assert tokens == [
             {:port_kw, 1},
             {:module_kw, 1},
             {:upper_id, 1, "Main"},
             {:exposing_kw, 1},
             {:lparen, 1},
             {:lower_id, 1, "main"},
             {:comma, 1},
             {:upper_id, 1, "Msg"},
             {:lparen, 1},
             {:dotdot, 1},
             {:rparen, 1},
             {:rparen, 1},
             {:newline, 1},
             {:import_kw, 3},
             {:upper_id, 3, "List"},
             {:newline, 3},
             {:import_kw, 4},
             {:upper_id, 4, "Pebble.Platform"},
             {:as_kw, 4},
             {:upper_id, 4, "PebblePlatform"},
             {:exposing_kw, 4},
             {:lparen, 4},
             {:lower_id, 4, "worker"},
             {:rparen, 4},
             {:newline, 4},
             {:port_kw, 5},
             {:lower_id, 5, "toJs"},
             {:colon, 5},
             {:upper_id, 5, "String"},
             {:upper_id, 5, "Cmd"},
             {:lower_id, 5, "msg"},
             {:newline, 5}
           ]
  end

  test "yecc parses module/import metadata from expanded header subset" do
    source = """
    port module Main exposing (main, Msg(..))
    import List
    import Maybe as M exposing (..)
    import Json.Decode as Decode exposing (Decoder)
    port toJs : String -> Cmd msg
    """

    assert {:ok, tokens, _} = :elm_ex_elm_lexer.string(String.to_charlist(source))
    parser_tokens = ElmEx.Frontend.GeneratedParser.metadata_subset_tokens(tokens)
    assert {:ok, metadata} = :elm_ex_elm_parser.parse(parser_tokens)

    assert metadata == [
             {:module, "Main", ["main", "Msg(..)"]},
             {:import, "List", %{as: nil, exposing: nil}},
             {:import, "Maybe", %{as: "M", exposing: ".."}},
             {:import, "Json.Decode", %{as: "Decode", exposing: ["Decoder"]}}
           ]
  end

  test "yecc parses effect module header metadata" do
    source = """
    effect module Task where { command = MyCmd } exposing (Task)
    import List
    """

    assert {:ok, tokens, _} = :elm_ex_elm_lexer.string(String.to_charlist(source))
    parser_tokens = ElmEx.Frontend.GeneratedParser.metadata_subset_tokens(tokens)
    assert {:ok, metadata} = :elm_ex_elm_parser.parse(parser_tokens)

    assert metadata == [
             {:module, "Task", ["Task"]},
             {:import, "List", %{as: nil, exposing: nil}}
           ]
  end

  test "generated parser derives extended header metadata from lexer tokens" do
    source = """
    port module Main exposing (main, Msg(..))

    import List
    import Maybe as M exposing (..)
    import Json.Decode as Decode exposing (Decoder)

    port toJs : String -> Cmd msg
    port fromJs
      : (String -> msg) -> Sub msg

    type Msg = X
    main = Main
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_header_meta_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    assert mod.module_exposing == ["main", "Msg(..)"]
    assert mod.port_module == true
    assert mod.ports == ["toJs", "fromJs"]

    assert mod.import_entries == [
             %{"module" => "List", "as" => nil, "exposing" => nil},
             %{"module" => "Maybe", "as" => "M", "exposing" => ".."},
             %{"module" => "Json.Decode", "as" => "Decode", "exposing" => ["Decoder"]}
           ]
  end

  test "generated expression parser handles arithmetic and calls" do
    assert {:ok, tokens, _} = :elm_ex_expr_lexer.string(String.to_charlist("value + 2"))
    assert {:ok, expr} = :elm_ex_expr_parser.parse(tokens)
    assert expr[:op] == :add_const
    assert expr[:var] == "value"
    assert expr[:value] == 2

    assert {:ok, tokens2, _} =
             :elm_ex_expr_lexer.string(String.to_charlist("Pebble.Draw.clear 0"))

    assert {:ok, expr2} = :elm_ex_expr_parser.parse(tokens2)
    assert expr2[:op] == :qualified_call
    assert expr2[:target] == "Pebble.Draw.clear"
    assert is_list(expr2[:args])

    assert {:ok, tokens3, _} =
             :elm_ex_expr_lexer.string(String.to_charlist("\\tag -> config.init tag"))

    assert {:ok, expr3} = :elm_ex_expr_parser.parse(tokens3)
    assert expr3[:op] == :lambda
    assert expr3[:args] == ["tag"]
    assert expr3[:body][:op] == :field_call

    assert {:ok, tokens4, _} =
             :elm_ex_expr_lexer.string(String.to_charlist("let base = helper n in base + 1"))

    assert {:ok, expr4} = :elm_ex_expr_parser.parse(tokens4)
    assert expr4[:op] == :let_in
    assert expr4[:name] == "base"
    assert expr4[:in_expr][:op] == :add_const

    assert {:ok, tokens5, _} =
             :elm_ex_expr_lexer.string(String.to_charlist("if base > 10 then base else base + 1"))

    assert {:ok, expr5} = :elm_ex_expr_parser.parse(tokens5)
    assert expr5[:op] == :if
    assert expr5[:cond][:op] == :compare

    assert {:ok, expr6} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case msg of\nTick -> Cmd.none\n_ -> Cmd.none"
             )

    assert expr6[:op] == :case
    assert expr6[:subject] == "msg"
    assert length(expr6[:branches]) == 2
    assert Enum.at(expr6[:branches], 1)[:pattern][:kind] == :wildcard

    assert {:ok, expr6c} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case location of\nBerlin ->\nPebble.Internal.Companion.companionSend 2 1\nZurich ->\nPebble.Internal.Companion.companionSend 2 2"
             )

    assert expr6c[:op] == :case
    assert length(expr6c[:branches]) == 2
    assert Enum.at(expr6c[:branches], 0)[:expr][:op] == :qualified_call

    assert {:ok, expr6b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case pair of\n( left, right ) -> Cmd.none\n_ -> Cmd.none"
             )

    assert expr6b[:op] == :case
    assert length(expr6b[:branches]) == 2
    assert Enum.at(expr6b[:branches], 0)[:pattern][:kind] == :tuple
    assert Enum.at(expr6b[:branches], 0)[:pattern][:elements] |> length() == 2

    assert {:ok, expr6d} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "let maybeTemp = temperatureOf model in case maybeTemp of\nJust temperature -> Pebble.Draw.textInt 0 28 temperature\nNothing -> Pebble.Draw.textLabel 0 28 Pebble.Draw.WaitingForCompanion"
             )

    assert expr6d[:op] == :let_in
    assert expr6d[:in_expr][:op] == :case
    assert length(expr6d[:in_expr][:branches]) == 2

    assert {:ok, expr6e} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "let\nx = a + 1\ny = b + 2\nin\nx + y"
             )

    assert expr6e[:op] == :let_in
    assert expr6e[:name] == "x"
    assert expr6e[:in_expr][:op] == :let_in
    assert expr6e[:in_expr][:name] == "y"

    assert {:ok, expr6f} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("let\nf n = n + 1\nin\nf 2")

    assert expr6f[:op] == :let_in
    assert expr6f[:name] == "f"
    assert expr6f[:value_expr][:op] == :lambda

    assert {:ok, expr6g} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("let\n(a, b, c) = tuple\nin\na")

    assert expr6g[:op] == :let_in
    assert expr6g[:name] == "__tupleBind_a_b_c"

    assert {:ok, tokens7, _} =
             :elm_ex_expr_lexer.string(
               String.to_charlist("{ value = counter + 1, temperature = Just temperature }")
             )

    assert {:ok, expr7} = :elm_ex_expr_parser.parse(tokens7)
    assert expr7[:op] == :record_literal
    assert length(expr7[:fields]) == 2
    assert Enum.at(expr7[:fields], 0)[:name] == "value"

    assert {:ok, tokens8, _} = :elm_ex_expr_lexer.string(String.to_charlist("(+)"))
    assert {:ok, expr8} = :elm_ex_expr_parser.parse(tokens8)
    assert expr8[:op] == :var
    assert expr8[:name] == "__add__"

    assert {:ok, tokens9, _} = :elm_ex_expr_lexer.string(String.to_charlist("((+) 1)"))
    assert {:ok, expr9} = :elm_ex_expr_parser.parse(tokens9)
    assert expr9[:op] == :call
    assert expr9[:name] == "__add__"
    assert length(expr9[:args]) == 1

    assert {:ok, expr10} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "values |> List.map ((+) 1) |> List.foldl (+) 0"
             )

    assert expr10[:op] == :qualified_call
    assert expr10[:target] == "List.foldl"

    assert {:ok, expr10b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("succeed identity |. spaces |= term")

    assert expr10b[:op] == :call
    assert expr10b[:name] == "|="
    assert Enum.at(expr10b[:args], 0)[:op] == :call
    assert Enum.at(expr10b[:args], 0)[:name] == "|."

    assert {:ok, expr10c} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("(|=)")

    assert expr10c[:op] == :var
    assert expr10c[:name] == "|="

    assert {:ok, expr10d} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("(*)")

    assert expr10d[:op] == :var
    assert expr10d[:name] == "__mul__"

    assert {:ok, expr10e} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("(<|)")

    assert expr10e[:op] == :var
    assert expr10e[:name] == "<|"

    assert {:ok, expr11} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "{ model | value = model.value + 1, values = model.values }"
             )

    assert expr11[:op] == :record_update
    assert expr11[:base] == %{op: :var, name: "model"}
    assert Enum.map(expr11[:fields], & &1[:name]) == ["value", "values"]

    assert {:ok, expr12} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("fn <| value")

    assert expr12[:op] == :call
    assert expr12[:name] == "fn"
    assert length(expr12[:args]) == 1

    assert {:ok, expr12b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "resolve <| \\bytes -> Result.fromMaybe \"unexpected bytes\" bytes"
             )

    assert expr12b[:op] == :call
    assert expr12b[:name] == "resolve"
    assert Enum.at(expr12b[:args], 0)[:op] == :lambda

    assert {:ok, expr13} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("(f << g) value")

    assert expr13[:op] == :call
    assert expr13[:name] == "f"

    assert {:ok, expr14} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("(f >> g) value")

    assert expr14[:op] == :call
    assert expr14[:name] == "g"

    assert {:ok, expr14b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "Elm.Kernel.Json.wrap >> Elm.Kernel.Debugger.unsafeCoerce"
             )

    assert expr14b[:op] == :compose_right

    assert {:ok, expr15} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1 :: values")

    assert expr15[:op] == :qualified_call
    assert expr15[:target] == "List.cons"

    assert {:ok, expr16} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\x y -> x + y")

    assert expr16[:op] == :lambda
    assert expr16[:args] == ["x"]
    assert expr16[:body][:op] == :lambda
    assert expr16[:body][:args] == ["y"]

    assert {:ok, expr17} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\_ -> 1")

    assert expr17[:op] == :lambda
    assert expr17[:args] == ["ignoredArg"]
    assert expr17[:body][:op] == :int_literal

    assert {:ok, expr17c} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\() -> 1")

    assert expr17c[:op] == :lambda
    assert expr17c[:args] == ["unitArg"]

    assert {:ok, expr17b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\(left, right) -> left")

    assert expr17b[:op] == :lambda
    assert expr17b[:args] == ["tupleArg"]
    assert expr17b[:body][:op] == :let_in

    assert {:ok, expr17d} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\(a, b, c) -> a")

    assert expr17d[:op] == :lambda
    assert expr17d[:args] == ["tupleArg"]
    assert expr17d[:body][:op] == :let_in

    assert {:ok, expr17e} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\{ visited, value } -> value")

    assert expr17e[:op] == :lambda
    assert expr17e[:args] == ["recordArg"]
    assert expr17e[:body][:op] == :let_in

    assert {:ok, expr17f} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\\(weight, _) -> weight")

    assert expr17f[:op] == :lambda
    assert expr17f[:args] == ["tupleArg"]
    assert expr17f[:body][:op] == :let_in

    assert {:ok, expr17g} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "let (Parser parse) = callback in parse"
             )

    assert expr17g[:op] == :let_in

    assert {:ok, expr17h} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "let className = if currentIndex == index then \"a\" else \"b\" in className"
             )

    assert expr17h[:op] == :let_in

    assert {:ok, expr18} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case Dict.get key dict of\nJust value -> value\nNothing -> 0"
             )

    assert expr18[:op] == :let_in
    assert expr18[:name] == "caseSubject"
    assert expr18[:in_expr][:op] == :case

    assert {:ok, expr19} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case values of\n[] -> 1\n_ -> 0")

    assert expr19[:op] == :case
    assert expr19[:subject] == "values"
    assert length(expr19[:branches]) == 2

    assert {:ok, expr20} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case values of\nx :: xs -> x\n[] -> 0"
             )

    assert expr20[:op] == :case
    assert expr20[:subject] == "values"
    assert Enum.at(expr20[:branches], 0)[:pattern][:name] == "::"
    assert Enum.at(expr20[:branches], 1)[:pattern][:name] == "[]"

    assert {:ok, expr20b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case parsers of\nParser parse :: rest -> parse\n[] -> parse"
             )

    assert expr20b[:op] == :case
    assert Enum.at(expr20b[:branches], 0)[:pattern][:name] == "::"

    assert Enum.at(expr20b[:branches], 0)[:pattern][:arg_pattern][:elements]
           |> Enum.at(0)
           |> Map.get(:name) == "Parser"

    assert Enum.at(expr20b[:branches], 0)[:pattern][:arg_pattern][:elements]
           |> Enum.at(1)
           |> Map.get(:name) == "rest"

    assert {:ok, expr21} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case values of\n(x :: xs) as full -> x + List.length full\n[] -> 0"
             )

    assert expr21[:op] == :case
    assert Enum.at(expr21[:branches], 0)[:pattern][:name] == "::"
    assert Enum.at(expr21[:branches], 0)[:pattern][:bind] == "full"

    assert {:ok, expr21b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case side of\n\"left\" -> 0\n_ -> 1")

    assert expr21b[:op] == :case
    assert Enum.at(expr21b[:branches], 0)[:pattern][:kind] == :string

    assert {:ok, expr22} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case record of\n{ value } -> value")

    assert expr22[:op] == :case
    assert expr22[:subject] == "record"
    assert Enum.at(expr22[:branches], 0)[:pattern][:kind] == :record
    assert Enum.at(expr22[:branches], 0)[:pattern][:fields] == ["value"]

    assert {:ok, expr23} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a + b + c")

    assert expr23[:op] == :call
    assert expr23[:name] == "__add__"

    assert {:ok, expr24} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a + b - c")

    assert expr24[:op] == :call
    assert expr24[:name] == "__sub__"

    assert {:ok, expr24c} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a-0x2")

    assert expr24c[:op] == :sub_const
    assert expr24c[:var] == "a"
    assert expr24c[:value] == 2

    assert {:ok, expr24e} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a-1")

    assert expr24e[:op] == :sub_const
    assert expr24e[:var] == "a"
    assert expr24e[:value] == 1

    assert {:ok, expr24f} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a-1e2")

    assert expr24f[:op] == :call
    assert expr24f[:name] == "__sub__"

    assert {:ok, expr24d} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("-0x2")

    assert expr24d[:op] == :call
    assert expr24d[:name] == "negate"
    assert Enum.at(expr24d[:args], 0)[:op] == :int_literal
    assert Enum.at(expr24d[:args], 0)[:value] == 2

    assert {:ok, expr24g} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("-n")

    assert expr24g[:op] == :call
    assert expr24g[:name] == "negate"
    assert Enum.at(expr24g[:args], 0)[:op] == :var
    assert Enum.at(expr24g[:args], 0)[:name] == "n"

    assert {:ok, expr24h} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("if lt n 0 then -n else n")

    assert expr24h[:op] == :if
    assert expr24h[:then_expr][:op] == :call
    assert expr24h[:then_expr][:name] == "negate"

    assert {:ok, expr24b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\"a\" ++ String.fromInt n")

    assert expr24b[:op] == :call
    assert expr24b[:name] == "__append__"
    assert length(expr24b[:args]) == 2

    assert {:ok, expr24b2} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "\"x\" ++ case context of\n[] -> \"!\"\n_ -> \"?\""
             )

    assert expr24b2[:op] == :call
    assert expr24b2[:name] == "__append__"
    assert Enum.at(expr24b2[:args], 1)[:op] == :case

    assert {:ok, expr24m} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "command (Perform (\ntask\n|> andThen (succeed << resultToMessage << Ok)\n|> onError (succeed << resultToMessage << Err)\n))"
             )

    assert expr24m[:op] == :call
    assert expr24m[:name] == "command"

    assert {:ok, expr24n} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "let\nstarter =\ncase context of\n[] -> \"Json.Decode.oneOf\"\n_ -> \"The Json.Decode.oneOf at json\" ++ String.join \"\" (List.reverse context)\nintroduction =\nstarter ++ \" failed in the following \" ++ String.fromInt (List.length errors) ++ \" ways:\"\nin\nString.join \"\\n\\n\" (introduction :: List.indexedMap errorOneOf errors)"
             )

    assert expr24n[:op] == :let_in
    assert expr24n[:name] == "starter"
    assert expr24n[:in_expr][:op] == :let_in

    assert {:ok, expr24o} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\"\"\"")

    assert expr24o[:op] == :string_literal
    assert expr24o[:value] == ""

    assert {:ok, expr24i} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a * b")

    assert expr24i[:op] == :call
    assert expr24i[:name] == "__mul__"

    assert {:ok, expr24j} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a // b")

    assert expr24j[:op] == :call
    assert expr24j[:name] == "__idiv__"

    assert {:ok, expr24j2} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a / b")

    assert expr24j2[:op] == :call
    assert expr24j2[:name] == "__fdiv__"

    assert {:ok, expr24k} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("List.foldl (::) [] values")

    assert expr24k[:op] == :qualified_call

    assert expr24k[:target] == "List.foldl"

    assert {:ok, expr25} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a > 0 && b > 0 && c > 0")

    assert expr25[:op] == :if

    assert {:ok, expr26} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a > 0 || b > 0 || c > 0")

    assert expr26[:op] == :if

    assert {:ok, expr27} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a >= b")

    assert expr27[:op] == :if

    assert {:ok, expr28} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a <= b")

    assert expr28[:op] == :if

    assert {:ok, expr29} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a /= b")

    assert expr29[:op] == :call
    assert expr29[:name] == "not"

    assert {:ok, expr30} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case flag of\nTrue -> 1\nFalse -> 0")

    assert expr30[:op] == :case
    assert expr30[:subject] == "flag"
    assert length(expr30[:branches]) == 2

    assert {:ok, expr31} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("a > 0 || b > 0 && c > 0")

    assert expr31[:op] == :if

    assert {:ok, expr32} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("(a > 0 || b > 0) && c > 0")

    assert expr32[:op] == :if

    assert {:ok, expr33} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("if a > 0 && b > 0 then 1 else 0")

    assert expr33[:op] == :if
    assert expr33[:cond][:op] == :if

    assert {:ok, expr34} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("not (a > 0 || b > 0)")

    assert expr34[:op] == :call
    assert expr34[:name] == "not"

    assert {:ok, expr35} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case flag of ; True -> 1 ; False -> 0"
             )

    assert expr35[:op] == :case
    assert length(expr35[:branches]) == 2

    assert {:ok, expr36} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(".value")

    assert expr36[:op] == :lambda
    assert expr36[:args] == ["fieldAccessorArg"]
    assert expr36[:body][:op] == :field_access
    assert expr36[:body][:field] == "value"

    assert {:ok, expr37} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("values |> List.map .value")

    assert expr37[:op] == :qualified_call
    assert expr37[:target] == "List.map"
    assert length(expr37[:args]) == 2

    assert {:ok, expr38} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1.5 + 2.25")

    assert expr38[:op] == :call
    assert expr38[:name] == "__add__"
    assert Enum.at(expr38[:args], 0)[:op] == :float_literal
    assert Enum.at(expr38[:args], 1)[:op] == :float_literal

    assert {:ok, expr39} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("()")

    assert expr39[:op] == :constructor_ref
    assert expr39[:target] == "()"

    assert {:ok, expr40} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("Task.succeed ()")

    assert expr40[:op] == :qualified_call
    assert expr40[:target] == "Task.succeed"
    assert length(expr40[:args]) == 1
    assert Enum.at(expr40[:args], 0)[:target] == "()"

    assert {:ok, expr41} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0x10 + 0x0F")

    assert expr41[:op] == :call
    assert expr41[:name] == "__add__"
    assert Enum.at(expr41[:args], 0)[:value] == 16
    assert Enum.at(expr41[:args], 1)[:value] == 15

    assert {:ok, expr42} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1e-3 + 2E2")

    assert expr42[:op] == :call
    assert expr42[:name] == "__add__"
    assert Enum.at(expr42[:args], 0)[:op] == :float_literal
    assert Enum.at(expr42[:args], 1)[:op] == :float_literal

    assert {:ok, expr43} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case record of\n{ value, temperature } -> value\n_ -> 0"
             )

    assert expr43[:op] == :case
    assert Enum.at(expr43[:branches], 0)[:pattern][:kind] == :record
    assert Enum.at(expr43[:branches], 0)[:pattern][:fields] == ["value", "temperature"]

    assert {:ok, expr44} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case unitValue of\n() -> 1\n_ -> 0")

    assert expr44[:op] == :case
    assert Enum.at(expr44[:branches], 0)[:pattern][:kind] == :constructor
    assert Enum.at(expr44[:branches], 0)[:pattern][:name] == "()"

    assert {:ok, expr45} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case point of\n(x, y, z) -> x\n_ -> 0"
             )

    assert expr45[:op] == :case
    assert Enum.at(expr45[:branches], 0)[:pattern][:kind] == :tuple
    assert Enum.at(expr45[:branches], 0)[:pattern][:elements] |> length() == 2
    assert Enum.at(Enum.at(expr45[:branches], 0)[:pattern][:elements], 1)[:kind] == :tuple

    assert {:ok, expr46} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case values of\n[x, y] -> x\n_ -> 0")

    assert expr46[:op] == :case
    assert Enum.at(expr46[:branches], 0)[:pattern][:name] == "::"
    assert Enum.at(expr46[:branches], 1)[:pattern][:kind] == :wildcard

    assert {:ok, expr47} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case record of\n{ value } as full -> value\n_ -> 0"
             )

    assert expr47[:op] == :case
    assert Enum.at(expr47[:branches], 0)[:pattern][:kind] == :record
    assert Enum.at(expr47[:branches], 0)[:pattern][:bind] == "full"

    assert {:ok, expr48} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case values of\n[x, y] as pair -> x\n_ -> 0"
             )

    assert expr48[:op] == :case
    assert Enum.at(expr48[:branches], 0)[:pattern][:name] == "::"
    assert Enum.at(expr48[:branches], 0)[:pattern][:bind] == "pair"

    assert {:ok, expr49} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case ch of\n'a' -> 1\n_ -> 0")

    assert expr49[:op] == :case
    assert Enum.at(expr49[:branches], 0)[:pattern][:kind] == :int
    assert Enum.at(expr49[:branches], 0)[:pattern][:value] == ?a

    assert {:ok, expr49b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case result of\nErr _ -> 0\nOk n -> n"
             )

    assert expr49b[:op] == :case
    assert Enum.at(expr49b[:branches], 0)[:pattern][:name] == "Err"
    assert Enum.at(expr49b[:branches], 0)[:pattern][:arg_pattern][:kind] == :wildcard

    assert {:ok, expr50} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\"line\\nnext\\tend\"")

    assert expr50[:op] == :string_literal
    assert expr50[:value] == "line\nnext\tend"

    assert {:ok, expr50b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("\"…\"")

    assert expr50b[:op] == :string_literal
    assert expr50b[:value] == "…"

    assert {:ok, expr51} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("'\\n'")

    assert expr51[:op] == :char_literal
    assert expr51[:value] == ?\n

    assert {:ok, expr52} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("[a, b,]")

    assert expr52[:op] == :list_literal
    assert length(expr52[:items]) == 2

    assert {:ok, expr52b} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("[]")

    assert expr52b[:op] == :list_literal
    assert expr52b[:items] == []

    assert {:ok, expr53} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "{ value = model.value, temperature = model.temperature, }"
             )

    assert expr53[:op] == :record_literal
    assert Enum.map(expr53[:fields], & &1[:name]) == ["value", "temperature"]

    assert {:ok, expr54} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case values of\n[x, y,] -> x\n_ -> 0"
             )

    assert expr54[:op] == :case
    assert Enum.at(expr54[:branches], 0)[:pattern][:name] == "::"

    assert {:ok, expr55} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(
               "case record of\n{ value, temperature, } -> value\n_ -> 0"
             )

    assert expr55[:op] == :case
    assert Enum.at(expr55[:branches], 0)[:pattern][:kind] == :record
    assert Enum.at(expr55[:branches], 0)[:pattern][:fields] == ["value", "temperature"]

    assert {:ok, expr56} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("case pair of\nPair x y -> x\n_ -> 0")

    assert expr56[:op] == :case
    assert Enum.at(expr56[:branches], 0)[:pattern][:kind] == :constructor
    assert Enum.at(expr56[:branches], 0)[:pattern][:name] == "Pair"
    assert Enum.at(expr56[:branches], 0)[:pattern][:bind] == nil
    assert Enum.at(expr56[:branches], 0)[:pattern][:arg_pattern][:kind] == :tuple
    assert Enum.at(expr56[:branches], 0)[:pattern][:arg_pattern][:elements] |> length() == 2
  end

  test "generated expression parser rejects backtick infix syntax (Elm 0.19.1)" do
    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("x `modBy` 10")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0XFF")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0X")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0X1g")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("01")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0b101")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0o77")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0b")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0b101x")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse(".foo.bar")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0x")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("0x1g")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1e")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1e+")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1.0e+")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1.e2")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1foo")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1.0foo")

    assert {:error, _reason} =
             ElmEx.Frontend.GeneratedExpressionParser.parse("1e2foo")
  end

  test "generated declaration parser handles alias, union, and signature lines" do
    assert {:ok, {:type_alias, "Model"}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line(
               "type alias Model = { value : Int }"
             )

    assert {:ok, {:type_alias, "Box"}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line(
               "type alias Box a msg = { value : a, tag : msg }"
             )

    assert {:ok, {:union_start, "Msg", :none}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line("type Msg")

    assert {:ok, {:union_constructors, [{:constructor, "ProvideTemperature", "Int"}]}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line("| ProvideTemperature Int")

    assert {:ok,
            {:union_start_many, "LaunchReason",
             [
               {:constructor, "LaunchSystem", nil},
               {:constructor, "LaunchUser", nil},
               {:constructor, "LaunchPhone", nil}
             ]}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line(
               "type LaunchReason = LaunchSystem | LaunchUser | LaunchPhone"
             )

    assert {:ok,
            {:union_start_many, "Wrapped",
             [
               {:constructor, "Wrap", "Maybe Int"},
               {:constructor, "Empty", nil}
             ]}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line(
               "type Wrapped = Wrap Maybe Int | Empty"
             )

    assert {:ok, {:union_start, "Boxed", :none}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line("type Boxed a")

    assert {:ok, {:function_signature, "headOrZero", "List Int -> Int"}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line("headOrZero : List Int -> Int")

    assert {:ok, {:function_signature, "decode'", "{a | value : Int} -> a -> a"}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_line(
               "decode' : { a | value : Int } -> a -> a"
             )
  end

  test "generated declaration parser handles function header lines" do
    assert {:ok, %{name: "update", args: ["msg", "model"], body: "case msg of"}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_function_header_line(
               "update msg model = case msg of"
             )

    assert {:ok, %{name: "decode'", args: ["arg'"], body: "arg'"}} =
             ElmEx.Frontend.GeneratedDeclarationParser.parse_function_header_line(
               "decode' arg' = arg'"
             )
  end

  test "generated declaration parser scans declaration lines once" do
    source = """
    type alias Model = { value : Int }
    type Msg
      = Tick
      | Set Int
    update : Msg -> Model -> Model
    update msg model = model
    """

    scanned = ElmEx.Frontend.GeneratedDeclarationParser.scan_lines(source)

    assert Enum.any?(
             scanned,
             &(&1.line_no == 1 and match?({:ok, {:type_alias, "Model"}}, &1.decl))
           )

    assert Enum.any?(
             scanned,
             &(&1.line_no == 2 and match?({:ok, {:union_start, "Msg", :none}}, &1.decl))
           )

    assert Enum.any?(
             scanned,
             &(&1.line_no == 3 and match?({:ok, {:union_constructors, _}}, &1.decl))
           )

    assert Enum.any?(
             scanned,
             &(&1.line_no == 5 and match?({:ok, {:function_signature, "update", _}}, &1.decl))
           )

    assert Enum.any?(
             scanned,
             &(&1.line_no == 6 and
                 match?(
                   {:ok, %{name: "update", args: ["msg", "model"], body: "model"}},
                   &1.function_header
                 ))
           )
  end

  test "generated parser keeps top-level declaration extraction stable" do
    source = """
    module Main exposing (main)

    type alias Model = { value : Int }

    type Msg
      = Tick
      | Set Int

    update : Msg -> Model -> Model
    update msg model =
        model

    main = update Tick { value = 1 }
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_decl_stable_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    assert Enum.any?(mod.declarations, &(&1.kind == :type_alias and &1.name == "Model"))
    assert Enum.any?(mod.declarations, &(&1.kind == :union and &1.name == "Msg"))
    assert Enum.any?(mod.declarations, &(&1.kind == :function_signature and &1.name == "update"))
    assert Enum.any?(mod.declarations, &(&1.kind == :function_definition and &1.name == "update"))
  end

  test "generated parser accepts non-4-space function body indentation" do
    source = """
    module Main exposing (main)

    main =
      1

    tabbed =
    \t2
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_indent_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    defs =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function_definition))
      |> Map.new(&{&1.name, &1})

    assert defs["main"].expr.op == :int_literal
    assert defs["main"].expr.value == 1
    assert defs["tabbed"].expr.op == :int_literal
    assert defs["tabbed"].expr.value == 2
  end

  test "generated parser captures multiline alias and signature declarations" do
    source = """
    module Main exposing (main)

    type alias Pair
      a
      b
      =
      { left : a, right : b }

    decode :
      -- keep comments in wrapped annotations
      { a | value : Int }
      -> a
      -> a
    decode x = x

    main = 1
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_multiline_decl_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    assert Enum.any?(mod.declarations, &(&1.kind == :type_alias and &1.name == "Pair"))

    assert Enum.any?(
             mod.declarations,
             &(&1.kind == :function_signature and
                 &1.name == "decode" and
                 String.contains?(&1.type, "{a | value : Int} -> a -> a"))
           )
  end

  test "generated parser keeps multiline union blocks across comment and blank lines" do
    source = """
    module Main exposing (main)

    type Msg a
      -- constructor branch
      = Tick

      | Wrap a
      | None

    main = 1
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_union_block_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    union = Enum.find(mod.declarations, &(&1.kind == :union and &1.name == "Msg"))
    assert union

    assert union.constructors == [
             %{name: "Tick", arg: nil},
             %{name: "Wrap", arg: "a"},
             %{name: "None", arg: nil}
           ]
  end

  test "generated parser hydrates wrapped constructor args in multiline unions" do
    source = """
    module Main exposing (main)

    type Msg
      = Wrap
          Int
      | Done

    main = 1
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_union_wrapped_arg_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    union = Enum.find(mod.declarations, &(&1.kind == :union and &1.name == "Msg"))
    assert union

    assert union.constructors == [
             %{name: "Wrap", arg: "Int"},
             %{name: "Done", arg: nil}
           ]
  end

  test "generated parser preserves multi-token constructor payload types" do
    source = """
    module Main exposing (main)

    type Msg
      = Wrap (Maybe Int)
      | Pair Int Int
      | Fn (Int -> String)
      | Done

    main = 1
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_union_multitoken_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    union = Enum.find(mod.declarations, &(&1.kind == :union and &1.name == "Msg"))
    assert union

    assert union.constructors == [
             %{name: "Wrap", arg: "(Maybe Int)"},
             %{name: "Pair", arg: "Int Int"},
             %{name: "Fn", arg: "(Int -> String)"},
             %{name: "Done", arg: nil}
           ]
  end

  test "generated parser keeps consecutive union declarations" do
    source = """
    module Main exposing (main)

    type First
      = First Int

    type Second
      = Second Int Int

    main = 1
    """

    path =
      Path.join(
        System.tmp_dir!(),
        "elmc_generated_consecutive_unions_#{System.unique_integer([:positive])}.elm"
      )

    mod =
      try do
        File.write!(path, source)
        assert {:ok, mod} = ElmEx.Frontend.GeneratedParser.parse_file(path)
        mod
      after
        _ = File.rm(path)
      end

    first_union = Enum.find(mod.declarations, &(&1.kind == :union and &1.name == "First"))
    second_union = Enum.find(mod.declarations, &(&1.kind == :union and &1.name == "Second"))

    assert first_union
    assert second_union
    assert first_union.constructors == [%{name: "First", arg: "Int"}]
    assert second_union.constructors == [%{name: "Second", arg: "Int Int"}]
  end

  test "generated expression parser covers fixture bodies" do
    fixture_root = Path.expand("fixtures/simple_project/src", __DIR__)
    module_paths = Path.wildcard(Path.join(fixture_root, "**/*.elm"))
    assert module_paths != []

    failures =
      module_paths
      |> Enum.flat_map(fn path ->
        {:ok, module} = ElmEx.Frontend.GeneratedParser.parse_file(path)

        module.declarations
        |> Enum.filter(
          &(&1.kind == :function_definition and is_binary(&1.body) and &1.body != "")
        )
        |> Enum.filter(fn decl ->
          match?({:error, _}, ElmEx.Frontend.GeneratedExpressionParser.parse(decl.body))
        end)
        |> Enum.map(&"#{Path.basename(path)}##{&1.name}")
      end)
      |> Enum.sort()

    assert failures == []
  end

  test "generated parser handles cached elm/core Basics when available" do
    path = Path.expand("~/.elm/0.19.1/packages/elm/core/1.0.5/src/Basics.elm")

    if File.exists?(path) do
      assert {:ok, module} = ElmEx.Frontend.GeneratedParser.parse_file(path)
      assert module.name == "Basics"
      assert is_list(module.declarations)
    else
      assert true
    end
  end
end
