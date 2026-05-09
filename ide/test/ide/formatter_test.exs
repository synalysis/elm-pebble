defmodule Ide.FormatterTest do
  use ExUnit.Case, async: true

  alias Ide.Formatter
  alias Ide.Formatter.Printer.ModuleHeader
  alias Ide.Formatter.Semantics.SpacingRules
  alias Ide.Tokenizer

  test "formats trailing spaces and ensures terminal newline" do
    source = "module Main exposing (main)   \nmain = 1   "

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.ends_with?(result.formatted_source, "\n")
    refute String.contains?(result.formatted_source, "   \n")
  end

  test "returns parser error for invalid elm source" do
    source = "value = @"

    assert {:error, reason} = Formatter.format(source)
    assert reason.source =~ "formatter/"
    assert reason.severity == "error"
  end

  test "reports parser error line from metadata parser failure" do
    source = """
    module Main exposing (main)
    import

    main = 1
    """

    assert {:error, reason} = Formatter.format(source)
    assert reason.source == "formatter/parser"
    assert reason.line == 2
  end

  test "normalizes module/import keyword spacing from parser metadata" do
    source = """
    module   Main    exposing (main)
    import   Html
    import  String   exposing (length)

    main = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.contains?(result.formatted_source, "module Main exposing (main)")
    assert String.contains?(result.formatted_source, "import Html")
    assert String.contains?(result.formatted_source, "import String exposing (length)")
  end

  test "module header normalization preserves port module syntax" do
    source = "port module Spelling exposing (main)\n"

    metadata = %{
      module: "Spelling",
      module_exposing: ["main"],
      header_lines: %{module: 1, imports: []},
      import_entries: []
    }

    assert ModuleHeader.normalize(source, metadata) == source
  end

  test "module header normalization preserves effect module syntax" do
    source =
      "effect module WebSocket where { command = MyCmd, subscription = MySub } exposing (send)\n"

    metadata = %{
      module: "WebSocket",
      module_exposing: ["send"],
      header_lines: %{module: 1, imports: []},
      import_entries: []
    }

    assert ModuleHeader.normalize(source, metadata) == source
  end

  test "declaration spacing keeps multiline comment trick closer line attached" do
    source = """
    module Main exposing (value)

    {--}
    value =
        ()
    --}
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    ()\n--}")
  end

  test "declaration spacing preserves blank lines inside doc comments" do
    source = """
    module Main exposing (value)

    {-| Bullet list
    - item one

    ref: #ref

    -}
    value = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "- item one\n\nref: #ref\n\n-}")
  end

  test "canonicalizes constructor exposing in multiline module header" do
    source = """
    module Main exposing
        ( Data(A, B), view
        )
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "( Data(..), view")
  end

  test "canonicalizes constructor exposing with inline comments in import header" do
    source = """
    module Main exposing (main)

    import {- A -} Maybe exposing ({- B -} Maybe({- C -} Just, {- D -} Nothing) {- E -}, map)
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "Maybe(..)")
    refute String.contains?(result.formatted_source, "Just")
    refute String.contains?(result.formatted_source, "Nothing")
  end

  test "rhs indentation does not treat infixr declarations as value definitions" do
    source = """
    module Main exposing ((|.))

    infixr 9 |.

    (|.) : Int -> Int -> Int
    (|.) a b =
        a + b
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "infixr 9 |.\n\n(|.) : Int -> Int -> Int")
  end

  test "record alignment tracks extensible nested record openings" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { nested :
            { a
                | field : Int
            }
        }
    """

    assert {:ok, result} = Formatter.format(source)
    refute String.contains?(result.formatted_source, "| field : Int\n    }")
  end

  test "union constructor continuation lines stay attached" do
    source = """
    module Main exposing (Data)

    type Data
        = Wrap
            { value : Int
            }
    """

    assert {:ok, result} = Formatter.format(source)
    refute String.contains?(result.formatted_source, "= Wrap\n\n            { value")
  end

  test "ignores block-commented fake headers when normalizing metadata" do
    source = """
    {- module Fake exposing (..) -}
    {- import Fake exposing (..) -}
    module   Real    exposing (main)
    import   Html

    main = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.contains?(result.formatted_source, "module Real exposing (main)")
    assert String.contains?(result.formatted_source, "import Html")
  end

  test "normalizes range expression syntax" do
    source = """
    module Main exposing (range)

    range =
        [1..2]
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "List.range 1 2")
  end

  test "normalizes constructor exposing syntax to double-dot" do
    source = """
    module Main exposing (Result(Ok,Err), value)

    value = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "Result(..)")
  end

  test "normalizes extra spaces before commas" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { value : Int    , temperature : Maybe Int }
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.contains?(result.formatted_source, "{ value : Int, temperature : Maybe Int }")
  end

  test "spacing rules normalize comma spacing directly" do
    assert SpacingRules.normalize_comma_spacing("{ value : Int    ,temperature : Maybe Int }") ==
             "{ value : Int, temperature : Maybe Int }"
  end

  test "spacing rules collapse extra spaces after comma on multiline record fields" do
    source = "    ,       temperature : Maybe Int"
    assert SpacingRules.normalize_comma_spacing(source) == "    , temperature : Maybe Int"
    assert SpacingRules.normalize_comma_spacing(source, []) == "    , temperature : Maybe Int"
  end

  test "spacing rules do not rewrite line comment comma spacing" do
    source = "    -- , 2"
    assert SpacingRules.normalize_comma_spacing(source) == source
  end

  test "spacing rules keep tuple function commas compact" do
    assert SpacingRules.normalize_comma_spacing("tupleFunction = (,,) 1 2 3") ==
             "tupleFunction = (,,) 1 2 3"
  end

  test "spacing rules do not rewrite commas inside string literals" do
    source = "view = prefix ++ \", \" ++ suffix"
    assert SpacingRules.normalize_comma_spacing(source) == source
  end

  test "spacing rules keep inline list comma spacing unchanged" do
    source = "values = [3,7]"
    assert SpacingRules.normalize_comma_spacing(source) == source
  end

  test "spacing rules do not rewrite commas inside doc comments" do
    source = "{-| Coordinates (x,y) stay as-is. -}"
    assert SpacingRules.normalize_comma_spacing(source) == source
  end

  test "spacing rules can use token positions for comma normalization" do
    source = "{ value : Int    ,temperature : Maybe Int }"

    tokens = [
      %{line: 1, column: 18, text: ",", class: "operator"}
    ]

    assert SpacingRules.normalize_comma_spacing(source, tokens) ==
             "{ value : Int, temperature : Maybe Int }"
  end

  test "spacing rules ignore stale comma token columns safely" do
    source = "module Main exposing (Model, Msg, headOrZero, main, update, view)"

    stale_tokens = [
      %{line: 1, column: 30, text: ",", class: "operator"},
      %{line: 1, column: 60, text: ",", class: "operator"},
      %{line: 1, column: 90, text: ",", class: "operator"}
    ]

    assert SpacingRules.normalize_comma_spacing(source, stale_tokens) ==
             source
  end

  test "keeps leading comma indentation and moves multiline record closing brace" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { value : Int
            , temperature : Maybe Int }
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.contains?(result.formatted_source, "    { value : Int")
    assert String.contains?(result.formatted_source, "    , temperature : Maybe Int")
    assert String.contains?(result.formatted_source, "    }")
  end

  test "formatter removes extra spaces after comma in multiline record fields" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { value : Int
        ,       temperature : Maybe Int
        }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    , temperature : Maybe Int")
    refute String.contains?(result.formatted_source, ",       temperature")
  end

  test "formatter normalizes multiline record indentation to four spaces" do
    source = """
    module Main exposing (Model)

    type alias Model =
           { value  : Int
           , temperature :  Maybe  Int
           }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    { value : Int")
    assert String.contains?(result.formatted_source, "    , temperature : Maybe Int")
    assert String.contains?(result.formatted_source, "    }")
  end

  test "record alignment does not re-introduce spacing after comma" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { value : Int
            ,       temperature : Maybe Int }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    , temperature : Maybe Int")
    refute String.contains?(result.formatted_source, ",       temperature")
  end

  test "record alignment ignores doc comment block delimiters" do
    source = """
    module Main exposing (App)

    {-| Description with punctuation: this should not affect record alignment.
    -}
    type alias App model =
        { html : Signal Html
        , model : Signal model
        , tasks : Signal (Task.Task Never ())
        }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    { html : Signal Html")
    assert String.contains?(result.formatted_source, "    , model : Signal model")
    assert String.contains?(result.formatted_source, "    , tasks : Signal (Task.Task Never ())")
    assert String.contains?(result.formatted_source, "    }")
  end

  test "record alignment keeps nested record commas aligned to inner indent" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { original :
            { counterExample : String
            , actual : String
            , expected : String
            }
        , seed : Int
        }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "        { counterExample : String")
    assert String.contains?(result.formatted_source, "        , actual : String")
    assert String.contains?(result.formatted_source, "        , expected : String")
    assert String.contains?(result.formatted_source, "        }")
  end

  test "record alignment does not rewrite doc comment prose indentation" do
    source = """
    module Main exposing (check)

    {-| This is very useful when trying to debug or reading reports.
    2.  The `actualStatement` is compared by equality `==` to the
        result of the `expectedStatement`.
    4.  The `investigator` generates random values.
    -}
    check : Int
    check =
        1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    result of the `expectedStatement`.")

    assert String.contains?(
             result.formatted_source,
             "4.  The `investigator` generates random values."
           )

    refute String.contains?(result.formatted_source, "        4.  The `investigator`")
  end

  test "rhs indentation does not indent block comment prose lines" do
    source = """
    module Main exposing (x)

    x =
        {-| Notes:
        2. keep this line at comment indentation
        4. do not add extra rhs indentation here
        -}
        1
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    2. keep this line at comment indentation"
           )

    assert String.contains?(
             result.formatted_source,
             "    4. do not add extra rhs indentation here"
           )

    refute String.contains?(
             result.formatted_source,
             "        2. keep this line at comment indentation"
           )
  end

  test "record comma lines do not split nested inline record expressions" do
    source = """
    module Main exposing (layout)

    layout =
        { node = "div"
        , layout = Style.Grid (Style.GridTemplate { rows = config.rows, columns = config.columns }) gridAttributes
        }
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    , layout = Style.Grid (Style.GridTemplate { rows = config.rows, columns = config.columns }) gridAttributes"
           )
  end

  test "keeps inline attribute list on record assignment lines" do
    source = """
    module Main exposing (view)

    view =
        { attrs = [ Attr.attribute "role" "navigation", Attr.attribute "aria-label" name ] }
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "attrs = [ Attr.attribute \"role\" \"navigation\", Attr.attribute \"aria-label\" name ]"
           )
  end

  test "aligns multiline list elements and closing bracket to opening bracket" do
    source = """
    module Main exposing (Msg, requestSystemInfo)

    requestSystemInfo : Cmd Msg
    requestSystemInfo =
        Cmd.batch
            [ Pebble.Cmd.getCurrentTimeString CurrentTimeString
    , Pebble.Cmd.getClockStyle24h ClockStyle24h
    , Pebble.Cmd.getTimezoneIsSet TimezoneIsSet
    , Pebble.Cmd.getTimezone TimezoneName
    , Pebble.Cmd.getWatchModel WatchModelName
    , Pebble.Cmd.getFirmwareVersion FirmwareVersionString
            ]
    """

    tokens = Tokenizer.tokenize(source, mode: :fast).tokens
    assert {:ok, result} = Formatter.format(source, tokens: tokens)

    assert String.contains?(
             result.formatted_source,
             "        [ Pebble.Cmd.getCurrentTimeString CurrentTimeString"
           )

    assert String.contains?(
             result.formatted_source,
             "        , Pebble.Cmd.getClockStyle24h ClockStyle24h"
           )

    assert String.contains?(
             result.formatted_source,
             "        , Pebble.Cmd.getFirmwareVersion FirmwareVersionString"
           )

    assert String.contains?(result.formatted_source, "        ]")
  end

  test "normalizes rhs and nested list indentation to 4-space steps" do
    source = """
    module Main exposing (Msg, requestSystemInfo)

    requestSystemInfo : Cmd Msg
    requestSystemInfo =
       Cmd.batch
             [ Pebble.Cmd.getCurrentTimeString CurrentTimeString
             , Pebble.Cmd.getClockStyle24h ClockStyle24h
             , Pebble.Cmd.getTimezoneIsSet TimezoneIsSet
             , Pebble.Cmd.getTimezone TimezoneName
             , Pebble.Cmd.getWatchModel WatchModelName
             , Pebble.Cmd.getFirmwareVersion FirmwareVersionString
             ]
    """

    tokens = Tokenizer.tokenize(source, mode: :fast).tokens
    assert {:ok, result} = Formatter.format(source, tokens: tokens)
    assert String.contains?(result.formatted_source, "    Cmd.batch")

    assert String.contains?(
             result.formatted_source,
             "        [ Pebble.Cmd.getCurrentTimeString CurrentTimeString"
           )

    assert String.contains?(
             result.formatted_source,
             "        , Pebble.Cmd.getClockStyle24h ClockStyle24h"
           )

    assert String.contains?(result.formatted_source, "        ]")
  end

  test "does not align non-record braces in multiline strings" do
    source = """
    module Main exposing (shader)

    shader =
        \"\"\"
        void main() {
          gl_FragColor = vec4(1.0);
        }
        \"\"\"
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "void main() {")
    assert String.contains?(result.formatted_source, "}")
    refute String.contains?(result.formatted_source, "             }")
  end

  test "aligns union constructor pipes with equals line" do
    source = """
    module Main exposing (Msg)

    type Msg
        = Increment
        | Decrement
         | Tick
       | UpPressed
        | SelectPressed
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.contains?(result.formatted_source, "    = Increment")
    assert String.contains?(result.formatted_source, "    | Tick")
    assert String.contains?(result.formatted_source, "    | UpPressed")
  end

  test "normalizes union equals indentation to one indent step" do
    source = """
    module Main exposing (MyType)

    type MyType
      = FirstType
      | SecondType
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "type MyType\n    = FirstType\n    | SecondType"
           )
  end

  test "removes blank lines inside union constructor block" do
    source = """
    module Main exposing (Msg)

    type Msg
        = Increment
        | Decrement

        | Tick
        | UpPressed
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    refute String.contains?(result.formatted_source, "| Decrement\n\n")
    assert String.contains?(result.formatted_source, "| Decrement\n    | Tick")
  end

  test "normalizes extra spaces in union constructor payloads" do
    source = """
    module Main exposing (Msg)

    type Msg
        = Increment  Int
        | Decrement
    """

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.contains?(result.formatted_source, "= Increment Int")
  end

  test "splits multiple union constructors written on one line" do
    source = """
    module Main exposing (Msg)

    type Msg
        = A
        | B Int | C String
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    | B Int\n    | C String")
  end

  test "normalizes type alias head spacing" do
    source = """
    module Main exposing (Model)

    type alias  Model  =
        { value : Int }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "type alias Model =")
  end

  test "restores elm-format spacing between top-level functions" do
    source = """
    module Main exposing (a, b)

    a =
        1
    b =
        2
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "a =\n    1\n\n\nb =")
  end

  test "splits extra list items on same line without token input" do
    source = """
    module Main exposing (requestSystemInfo)

    requestSystemInfo =
        Cmd.batch
            [ Pebble.Cmd.getCurrentTimeString CurrentTimeString
            , Pebble.Cmd.getClockStyle24h ClockStyle24h
            , Pebble.Cmd.getTimezoneIsSet TimezoneIsSet, Pebble.Cmd.getTimezone TimezoneName
            ]
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "        , Pebble.Cmd.getTimezoneIsSet TimezoneIsSet"
           )

    assert String.contains?(
             result.formatted_source,
             "        , Pebble.Cmd.getTimezone TimezoneName"
           )
  end

  test "normalizes case branch indentation and arrow spacing" do
    source = """
    module Main exposing (update, Msg(..))

    type Msg
        = DownPressed

    update msg =
       case msg of
             DownPressed  ->
                1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "    case msg of")
    assert String.contains?(result.formatted_source, "        DownPressed ->")
  end

  test "rhs indentation does not over-indent next case branch after inline let expression" do
    source = """
    module Main exposing (f, Msg(..))

    type Msg
        = Increment
        | Decrement

    f msg model =
        case msg of
            Increment ->
                let counter = model.value in ( counter, Cmd.none )

            Decrement ->
                ( model.value - 1, Cmd.none )
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "        Decrement ->")
    refute String.contains?(result.formatted_source, "                Decrement ->")
  end

  test "expands inline let-expression into multiline let/in layout" do
    source = """
    module Main exposing (advanced)

    advanced n =
        let counter = n + 1 in counter + 2
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    let\n        counter =\n            n + 1\n    in\n    counter + 2"
           )
  end

  test "expands binding line after standalone let when it still contains in" do
    source = """
    module Main exposing (advanced)

    advanced n =
        let
           base = n + 1 in base + 2
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    let\n        base =\n            n + 1\n    in\n    base + 2"
           )
  end

  test "expands inline if then else to multiline layout" do
    source = """
    module Main exposing (advanced)

    advanced n =
        if n > 10 then n else n + 1
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    if n > 10 then\n        n\n\n    else\n        n + 1"
           )
  end

  test "expands inline if tuple element without moving comma to line start" do
    source = """
    module Main exposing (update)

    type Msg
        = ConnectionChanged Bool

    update msg model =
        case msg of
            ConnectionChanged connected ->
                ( { model | connected = Just connected }
                , if connected then Cmd.none else PebbleVibes.doublePulse
                )
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "            , if connected then\n                  Cmd.none\n\n              else\n                  PebbleVibes.doublePulse"
           )

    refute String.contains?(result.formatted_source, "\n, if connected then")
  end

  test "aligns else in multiline if tuple element" do
    source = """
    module Main exposing (update)

    type Msg
        = ConnectionChanged Bool

    update msg model =
        case msg of
            ConnectionChanged connected ->
                ( { model | connected = Just connected }
                , if connected then
                    Cmd.none

                   else
                    PebbleVibes.doublePulse
                )
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "            , if connected then\n                  Cmd.none\n\n              else\n                  PebbleVibes.doublePulse"
           )

    refute String.contains?(result.formatted_source, "\n               else")
  end

  test "expands one-line doc comments to multiline form" do
    source = """
    module Main exposing (value)

    {-| Short docs. -}
    value = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "{-| Short docs.\n-}")
  end

  test "expands long inline list call to multiline list block" do
    source = """
    module Main exposing (subs)

    subs =
        PebbleEvents.batch [ PebbleEvents.onTick Tick, PebbleButton.onPress PebbleButton.Up UpPressed, PebbleButton.onPress PebbleButton.Select SelectPressed, PebbleButton.onPress PebbleButton.Down DownPressed, PebbleAccel.onTap AccelTap ]
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    PebbleEvents.batch\n        [ PebbleEvents.onTick Tick"
           )

    assert String.contains?(result.formatted_source, "        , PebbleAccel.onTap AccelTap")
    assert String.contains?(result.formatted_source, "        ]")
  end

  test "moves additional opening-line list items to separate comma lines" do
    source = """
    module Main exposing (subs)

    subs =
        PebbleEvents.batch [ PebbleEvents.onTick Tick, PebbleButton.onPress PebbleButton.Up UpPressed
           , PebbleButton.onPress PebbleButton.Select SelectPressed
           , PebbleButton.onPress PebbleButton.Down DownPressed
           , PebbleAccel.onTap AccelTap ]
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    PebbleEvents.batch\n        [ PebbleEvents.onTick Tick"
           )

    assert String.contains?(
             result.formatted_source,
             "        , PebbleButton.onPress PebbleButton.Up UpPressed"
           )
  end

  test "moves multiline list closing bracket to own line" do
    source = """
    module Main exposing (subs)

    subs =
        PebbleEvents.batch
            [ PebbleEvents.onTick Tick
            , PebbleButton.onPress PebbleButton.Up UpPressed
            , PebbleAccel.onTap AccelTap ]
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "        , PebbleAccel.onTap AccelTap\n        ]"
           )
  end

  test "expands let binding with trailing in and next-line expression" do
    source = """
    module Main exposing (statusDraw)

    statusDraw model =
        let maybeTemp = model.temperature in
        case maybeTemp of
            Just _ ->
                1

            Nothing ->
                0
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    let\n        maybeTemp =\n            model.temperature\n    in\n    case maybeTemp of"
           )
  end

  test "keeps blank line between import block and top-level docs" do
    source = """
    module Main exposing (value)

    import Html
    {-| Docs -}
    value = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "import Html\n\n\n{-| Docs")
  end

  test "aligns tuple comma with opening record tuple line" do
    source = """
    module Main exposing (init)

    init launchReason =
        ( { value = launchReason, temperature = Nothing }
      , Cmd.none
        )
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "    ( { value = launchReason, temperature = Nothing }\n    , Cmd.none"
           )
  end

  test "aligns nested extensible record and tuple comma lines in case branch" do
    source = """
    module Main exposing (update, Msg(..), Model)

    type Msg
        = CurrentDateTime { hour : Int, minute : Int }

    type alias Model =
        { hour : Int, minute : Int }

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            CurrentDateTime value ->
                ( { model
                    | hour = value.hour
            , minute = value.minute
                  }
        , Cmd.none
                )
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "| hour = value.hour\n                , minute = value.minute"
           )

    assert String.contains?(result.formatted_source, "              }\n            , Cmd.none")
  end

  test "aligns second argument list in multiline call block" do
    source = """
    module Main exposing (view)

    view =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.strokeWidth 3
                ]
            [ PebbleUi.roundRect 6 6 132 70 6 1
            ]
            )
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             "            [ PebbleUi.roundRect 6 6 132 70 6 1"
           )
  end

  test "expands nested call with inline list argument into multiline call layout" do
    source = """
    module Main exposing (view)

    view =
        [ PebbleUi.arc 20 16 36 36 0 45000
        , PebbleUi.pathOutline (PebbleUi.path [ ( 0, 0 ), ( 10, 4 ), ( 16, 14 ) ] 86 16 0)
        ]
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, ", PebbleUi.pathOutline")
    assert String.contains?(result.formatted_source, "(PebbleUi.path")
    assert String.contains?(result.formatted_source, "        [ ( 0, 0 )")
    assert String.contains?(result.formatted_source, "        86")
  end

  test "expands multiline nested call-list block to structured call layout" do
    source = """
    module Main exposing (view)

    view =
        [ PebbleUi.arc 20 16 36 36 0 45000
        , PebbleUi.pathOutline (PebbleUi.path [ ( 0, 0 )
        , ( 10, 4 )
        , ( 16, 14 )
        ] 86 16 0)
        ]
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(
             result.formatted_source,
             ", PebbleUi.pathOutline\n        (PebbleUi.path"
           )

    assert String.contains?(result.formatted_source, "            [ ( 0, 0 )")
    assert String.contains?(result.formatted_source, "            86")
    assert String.contains?(result.formatted_source, "        )")
  end

  test "collapses excessive blank lines between top-level functions" do
    source = """
    module Main exposing (a, b)

    a =
        1



    b =
        2
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "a =\n    1\n\n\nb =")
    refute String.contains?(result.formatted_source, "a =\n    1\n\n\n\nb =")
  end

  test "keeps grouped infix declarations compact" do
    source = """
    module Main exposing ((<|), (==), (<<))

    infix right 0 (<|) = apL

    infix non   4 (==) = eq
    infix left  9 (<<) = composeL
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "(<|) = apL\ninfix non")
    assert String.contains?(result.formatted_source, "(==) = eq\ninfix left")
    refute String.contains?(result.formatted_source, "(==) = eq\n\ninfix left")
  end

  test "uses two blank lines between type and function declarations" do
    source = """
    module Main exposing (Msg, view)

    type Msg
        = Tick
    view =
        Tick
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "= Tick\n\n\nview =")
  end

  test "keeps blank-line separator after type definition" do
    source = """
    module Main exposing (Msg, headOrZero)

    type Msg
        = WatchModelName String
        | FirmwareVersionString String
    {-| Return the first integer in a list, or `0` when empty. -}
    headOrZero : List Int -> Int
    headOrZero list =
        Maybe.withDefault 0 (List.head list)
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "| FirmwareVersionString String\n\n\n{-|")
    assert String.contains?(result.formatted_source, "-}\nheadOrZero : List Int -> Int")
  end

  test "normalizes hex escapes to unicode braced escapes" do
    source = """
    module Main exposing (value)

    value =
        "\\x0a\\x0B"
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "\\u{000A}\\u{000B}")
  end

  test "normalizes NBSP characters to unicode escapes" do
    nbsp = <<0xC2, 0xA0>>

    source =
      "module Main exposing (value)\n\nvalue =\n    \"#{nbsp}S#{nbsp}\"\n"

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "\"\\u{00A0}S\\u{00A0}\"")
  end

  test "normalizes legacy module syntax to exposing form" do
    source = """
    module Main (..) where

    value = 1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "module Main exposing (..)")
  end

  test "removes constructor parens in case branch patterns" do
    source = """
    module Main exposing (value)

    value m =
        case m of
            Maybe.Just (Maybe.Nothing) ->
                1

            _ ->
                0
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "Maybe.Just Maybe.Nothing ->")
  end

  test "normalizes nested as-pattern constructor parens" do
    source = """
    module Main exposing (value)

    value m =
        case m of
            ((Maybe.Nothing) as y) as x ->
                1

            _ ->
                0
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "(Maybe.Nothing as y) as x ->")
  end

  test "is idempotent for representative fixtures" do
    samples = [
      """
      module Main exposing (main)

      type alias Model = { value : Int , temperature : Maybe Int }

      main =
          1
      """,
      """
      module Main exposing (value)

      value list =
          case list of
              [] ->
                  0

              first :: rest ->
                  first
      """
    ]

    Enum.each(samples, fn source ->
      assert {:ok, once} = Formatter.format(source)
      assert {:ok, twice} = Formatter.format(once.formatted_source)
      assert twice.formatted_source == once.formatted_source
    end)
  end
end
