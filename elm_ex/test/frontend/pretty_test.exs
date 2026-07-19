defmodule ElmEx.Frontend.PrettyTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedExpressionParser, Module, Pretty}

  test "format_expr renders literals and calls" do
    assert Pretty.format_expr(%{op: :int_literal, value: 42}) == "42"
    assert Pretty.format_expr(%{op: :var, name: "model"}) == "model"

    assert Pretty.format_expr(%{
             op: :call,
             name: "Just",
             args: [%{op: :int_literal, value: 1}]
           }) == "Just 1"
  end

  test "format_expr renders multiline let/in layout" do
    expr = %{
      op: :let_in,
      name: "x",
      value_expr: %{op: :int_literal, value: 1},
      in_expr: %{
        op: :let_in,
        name: "y",
        value_expr: %{op: :int_literal, value: 2},
        in_expr: %{op: :call, name: "add", args: [%{op: :var, name: "x"}, %{op: :var, name: "y"}]}
      }
    }

    formatted = Pretty.format_expr(expr)

    assert formatted =~ "let"
    assert formatted =~ "in"
    assert formatted =~ "x ="
    assert formatted =~ "y ="
    assert formatted =~ "add x y"
  end

  test "format_expr renders case arms on separate lines" do
    expr = %{
      op: :case,
      subject: "n",
      branches: [
        %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}},
        %{
          pattern: %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "x"}},
          expr: %{op: :var, name: "x"}
        }
      ]
    }

    formatted = Pretty.format_expr(expr)

    assert formatted =~ "case n of"
    assert formatted =~ "_ ->"
    assert formatted =~ "Just x ->"
  end

  test "parse then format then parse accepts let/in" do
    source = """
    let
        a = 1
    in
        a
    """

    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    formatted = Pretty.format_expr(ast)
    assert {:ok, _} = GeneratedExpressionParser.parse(formatted)
  end

  test "round_trip? accepts sibling let bindings, case, if, and nested case" do
    assert Pretty.round_trip?("""
           let
               a = 1
               b = 2
           in
               a + b
           """)

    assert Pretty.round_trip?("""
           case x of
               A ->
                   1
               B ->
                   2
           """)

    assert Pretty.round_trip?("""
           if True then
               1
           else
               2
           """)

    assert Pretty.round_trip?("""
           let
               x =
                   case n of
                       Zero ->
                           0
                       Succ m ->
                           m
           in
               x
           """)
  end

  test "round_trip? accepts function let bindings and split case in let body" do
    assert Pretty.round_trip?("""
           let point x y = ""
               flag b = if b then 1 else 0
           in
               flag True
           """)

    assert Pretty.round_trip?("""
           let
               f = 1
           in
               case seg of
                   A ->
                       ""
           """)
  end

  test "round_trip? accepts tuple and pattern let bindings" do
    assert Pretty.round_trip?("""
           let
               msg = update model
               ( _, paths ) = msg
           in
               paths
           """)

    assert Pretty.round_trip?("""
           case c of
               C.Wrap label a ->
                   let
                       ( contents, fullExtent, wrappingExtent ) =
                           case innerBound of
                               Just extent ->
                                   1
                               _ ->
                                   0
                   in
                   contents
           """)
  end

  test "round_trip? formats empty collections compactly and pipe operators infix" do
    assert Pretty.format_expr(%{op: :list_literal, items: []}) == "[]"
    assert Pretty.format_expr(%{op: :record_literal, fields: []}) == "{}"

    assert Pretty.round_trip?("Svg.g []")
    assert Pretty.round_trip?("x |. f")
    assert Pretty.round_trip?("x |= 1")
  end

  test "format_expr renders float literals including negatives" do
    assert Pretty.format_expr(%{op: :float_literal, value: -0.3}) == "-0.3"
    assert Pretty.round_trip?("degrees -0.3")
  end

  test "format_expr renders record updates with pipe separator" do
    assert Pretty.format_expr(%{
             op: :record_update,
             base: %{op: :var, name: "scan"},
             fields: [%{name: "prevAbove", expr: %{op: :var, name: "above"}}]
           }) == "{scan | prevAbove = above}"

    assert Pretty.round_trip?("{ scan | prevAbove = Just above }")

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("{ a = 1, b = 2 }"), 1)
           ) == "{a = 1, b = 2}"
  end

  test "format_expr omits trailing space on nullary calls" do
    assert Pretty.format_expr(%{op: :qualified_call, target: "Cmd.none", args: []}) == "Cmd.none"

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("(model, Cmd.none)"), 1)
           ) == "(model, Cmd.none)"
  end

  test "format_expr renders simple case branches inline" do
    formatted =
      Pretty.format_expr(
        elem(
          GeneratedExpressionParser.parse("""
          case msg of
              Tick -> ( model, Cmd.none )
              _ -> model
          """),
          1
        ),
        width: 120
      )

    assert formatted =~ "Tick ->"
    assert formatted =~ "(model, Cmd.none)"
    assert formatted =~ "_ ->"
    assert formatted =~ "model"

    assert Pretty.round_trip_ast?("""
           case msg of
               Tick -> ( model, Cmd.none )
               _ -> model
           """)
  end

  test "format_expr renders simple if expressions inline" do
    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("if x then 1 else 0"), 1)
           ) == "if x then 1 else 0"

    assert Pretty.format_expr(
             elem(
               GeneratedExpressionParser.parse("if x then 1 else if y then 2 else 0"),
               1
             )
           ) == "if x then 1 else if y then 2 else 0"

    assert Pretty.round_trip_ast?("""
           if batteryLevel <= 20 then
               red
           else if batteryLevel <= 40 then
               yellow
           else
               green
           """)
  end

  test "round_trip? accepts cons and append expressions and list patterns" do
    assert Pretty.round_trip?("""
           case list of
               (Wrapped InnerA) :: [] ->
                   "single-wrapped-A"
               _ ->
                   "other"
           """)

    assert Pretty.round_trip?("""
           case segments of
               [ "packages", author, name ] ->
                   author
               _ ->
                   ""
           """)

    assert Pretty.format_expr(
             elem(
               GeneratedExpressionParser.parse("""
               case segments of
                   [ "packages", author, name ] ->
                       author
                   _ ->
                       ""
               """),
               1
             )
           ) =~ "[\"packages\", author, name]"

    assert Pretty.round_trip?("a :: b")
    assert Pretty.round_trip?("x ++ y")
    assert Pretty.round_trip?("(1 :: []) ++ [2]")
  end

  test "round_trip? accepts pattern lambda and constructor let binding" do
    assert Pretty.round_trip?("""
           \\title build (Schema data) ->
               let
                   start =
                       Schema { data | currentSection = Just title, sections = data.sections ++ [ Section title [] ] }

                   (Schema next) =
                       build start
               in
               Schema { next | currentSection = data.currentSection }
           """)

    assert Pretty.round_trip?("""
           \\(Config svgConfig) b ->
               let
                   rectAttributes =
                       [ width <| String.fromFloat b.width ]
                           ++ svgConfig.toBoxAttributes b.label
               in
               Svg.g [] <|
                   Svg.rect rectAttributes []
                       :: (case b.label of
                               Just label ->
                                   let
                                       textPosition =
                                           svgConfig.labelPosition b
                                   in
                                   [ svgBoxText label textPosition (svgConfig.toLabelString label) ]
                               _ ->
                                   []
                          )
           """)

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("\\(Config svgConfig) b -> 1"), 1)
           ) == "\\(Config svgConfig) b -> 1"

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("\\title build (Schema data) -> 1"), 1)
           ) == "\\title build (Schema data) -> 1"
  end

  test "round_trip? accepts else-if and multiline lambda patterns" do
    assert Pretty.round_trip?("""
           let
               batteryColor =
                   if batteryLevel <= 20 then
                       PebbleColor.red
                   else if batteryLevel <= 40 then
                       PebbleColor.chromeYellow
                   else
                       PebbleColor.green
           in
               batteryColor
           """)

    assert Pretty.round_trip?("""
           \\title build (Schema data) ->
               let
                   start = build data
               in
               start
           """)
  end

  test "format_expr renders arithmetic with precedence parentheses" do
    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("(a + b) * c"), 1)
           ) == "(a + b) * c"

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("a + (b - c)"), 1)
           ) == "a + (b - c)"

    assert Pretty.round_trip?("(a + b) * c")
    assert Pretty.round_trip?("a + b * c")
  end

  test "format_expr renders compact list literals for simple items" do
    assert Pretty.format_expr(%{
             op: :list_literal,
             items: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
           }) == "[a, b]"

    assert Pretty.round_trip?("[a, b]")
  end

  test "round_trip_ast? preserves nested call application grouping" do
    src =
      "moonAltitudeRad (Time.millisToPosix (baseUtcMillis + sampleMinute * 60000)) location > degrees -0.3"

    assert Pretty.round_trip?(src)
    assert Pretty.round_trip_ast?(src)
  end

  test "format_expr renders nested call args and multiline records" do
    assert Pretty.format_expr(%{
             op: :call,
             name: "moonAltitudeRad",
             args: [
               %{
                 op: :qualified_call,
                 target: "Time.millisToPosix",
                 args: [
                   %{
                     op: :call,
                     name: "__add__",
                     args: [
                       %{op: :var, name: "baseUtcMillis"},
                       %{
                         op: :call,
                         name: "__mul__",
                         args: [
                           %{op: :var, name: "sampleMinute"},
                           %{op: :int_literal, value: 60000}
                         ]
                       }
                     ]
                   }
                 ]
               },
               %{op: :var, name: "location"}
             ]
           }) =~ "(Time.millisToPosix"

    assert Pretty.round_trip?("""
           Http.request
               { expect =
                   Http.expectBytesResponse callback
                       (\\bytes ->
                           Cmd.none
                       )
               , tracker = Just (String.fromInt transitionId)
               , body = Http.emptyBody
               }
           """)
  end

  test "round_trip? formats compact single-binding let on one line" do
    assert Pretty.round_trip?("let a = 1 in a")
    assert Pretty.format_expr(%{
             op: :let_bindings,
             bindings: [%{kind: :name, name: "a", value: %{op: :int_literal, value: 1}}],
             in_expr: %{op: :var, name: "a"}
           }) == "let a = 1 in a"
  end

  test "round_trip? preserves discard lambda in call arguments" do
    src = "Maybe.withDefault 0 (Maybe.map (\\_ -> 1) maybeValue)"
    assert Pretty.round_trip?(src)
    assert Pretty.round_trip_ast?(src)
    assert Pretty.format_source(src) == {:ok, src}
  end

  test "round_trip? preserves partial operator sections" do
    assert Pretty.round_trip?("List.map ((+) 1) values")
    assert Pretty.round_trip_ast?("values |> List.map ((+) 1)")
    assert Pretty.round_trip_ast?("List.foldl (+) 0 values")

    assert Pretty.format_expr(
             elem(GeneratedExpressionParser.parse("((+) 1)"), 1)
           ) == "(+) 1"
  end

  test "round_trip? preserves char literals and inclusive compares" do
    assert Pretty.format_expr(%{op: :char_literal, value: 65}) == "'A'"
    assert Pretty.format_expr(%{op: :char_literal, value: 48}) == "'0'"
    assert Pretty.round_trip?("'A'")
    assert Pretty.round_trip_ast?("y < 0 || y >= 4 || x < 0 || x >= 4")
  end

  test "round_trip? preserves nested field calls and apply-left call args" do
    assert Pretty.round_trip_ast?("(api.child child).read key")
    assert Pretty.round_trip_ast?("Char.toCode (Char.fromCode 66)")
    assert Pretty.round_trip_ast?("BackendTask.Http.post url (BackendTask.Http.jsonBody <| body) decoder")
    assert Pretty.round_trip_ast?("Task.attempt Got <| BackendTask.Http.post url (BackendTask.Http.jsonBody <| body) decoder")
  end

  test "format_pattern renders cons as-bindings" do
    formatted =
      ElmEx.Frontend.Pretty.Pattern.format(%{
        kind: :constructor,
        name: "::",
        bind: "full",
        arg_pattern: %{
          kind: :tuple,
          elements: [
            %{kind: :var, name: "x"},
            %{kind: :var, name: "xs"}
          ]
        }
      })
      |> ElmEx.Frontend.Pretty.Doc.render()

    assert formatted == "(x :: xs) as full"
  end

  test "format_source parses and returns formatted text" do
    assert {:ok, formatted} =
             Pretty.format_source("""
             let
                 a = 1
             in
                 a
             """)

    assert formatted =~ "let"
    assert formatted =~ "in"
    assert formatted =~ "a ="
  end

  test "format_module renders header imports and function" do
    mod = %Module{
      name: "Main",
      path: "src/Main.elm",
      imports: ["Html"],
      module_exposing: nil,
      import_entries: [%{"module" => "Html", "as" => nil, "exposing" => nil}],
      declarations: [
        %{
          kind: :function_definition,
          name: "main",
          args: [],
          expr: %{op: :int_literal, value: 0},
          span: %{start_line: 3, end_line: 3}
        }
      ]
    }

    formatted = Pretty.format_module(mod)

    assert formatted =~ "module Main"
    assert formatted =~ "import Html"
    assert formatted =~ "main ="
    assert formatted =~ "0"
  end

  test "format_module round-trips function expression bodies" do
    alias ElmEx.Frontend.{GeneratedParser, Pretty.AstNormalize}

    source = """
    module Main exposing (..)

    import Html

    init _ =
        let
            a = 1
        in
            ( a, Html.text "hi" )

    update msg model =
        case msg of
            Tick ->
                ( model, Cmd.none )
    """

    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)
    formatted = Pretty.format_module(mod)
    assert formatted =~ "module Main exposing (..)"
    assert formatted =~ "import Html"
    assert formatted =~ "init _ ="
    assert formatted =~ "update msg model ="

    assert {:ok, reparsed} = GeneratedParser.parse_source("Main.elm", formatted)

    for name <- ["init", "update"] do
      original = Enum.find(mod.declarations, &(&1.name == name))
      again = Enum.find(reparsed.declarations, &(&1.name == name))

      assert AstNormalize.equivalent?(original.expr, again.expr),
             "expression AST mismatch for #{name}\nformatted:\n#{formatted}"
    end
  end

  test "format_module renders type alias and union declarations" do
    alias ElmEx.Frontend.GeneratedParser

    source = """
    module Main exposing (..)

    type alias Model =
        { on : Bool
        , count : Int
        }

    type Msg
        = Tick
        | Set Bool

    main =
        0
    """

    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)
    formatted = Pretty.format_module(mod)

    assert formatted =~ "type alias Model ="
    assert formatted =~ "on : Bool"
    assert formatted =~ "type Msg"
    assert formatted =~ "= Tick"
    assert formatted =~ "| Set Bool"

    assert {:ok, reparsed} = GeneratedParser.parse_source("Main.elm", formatted)

    assert Enum.find(reparsed.declarations, &(&1.kind == :type_alias)).field_types == %{
             "on" => "Bool",
             "count" => "Int"
           }

    assert Enum.find(reparsed.declarations, &(&1.kind == :union)).constructors == [
             %{name: "Tick", arg: nil},
             %{name: "Set", arg: "Bool"}
           ]
  end

  test "format_module renders port module header and port signatures" do
    alias ElmEx.Frontend.GeneratedParser

    source = """
    port module Main exposing (..)

    port log : String -> Cmd msg
    """

    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)
    formatted = Pretty.format_module(mod)

    assert formatted =~ "port module Main exposing (..)"
    assert formatted =~ "port log : String -> Cmd msg"
  end

  test "Layout.indent_lines prefixes each line" do
    assert ElmEx.Frontend.Layout.indent_lines("a\nb", 1) == "    a\n    b"
  end
end
