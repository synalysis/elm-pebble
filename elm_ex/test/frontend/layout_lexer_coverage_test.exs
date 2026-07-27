defmodule ElmEx.Frontend.LayoutLexerCoverageTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedExpressionParser, Pretty}

  @sources [
    {"multiline let/in", """
     let
         a = 1
         b = 2
     in
         a + b
     """},
    {"split binding rhs", """
     let
         counter =
             n + 1
     in
         counter + 2
     """},
    {"multiline case", """
     case x of
         A ->
             1
         B ->
             2
     """},
    {"multiline if", """
     if True then
         1
     else
         2
     """},
    {"else if chain", """
     if x then
         1
     else if y then
         2
     else
         3
     """},
    {"nested multiline if", """
     if a then
         if b then
             1
         else
             2
     else
         3
     """},
    {"pipe in if else before outer case arm", """
     case msg of
         A ->
             if cond then
                 1
             else
                 2
                 |> f x
         B ->
             0
     """},
    {"nested if in case arm with pipe else", """
     case msg of
         Nothing ->
             if True then
                 1
             else
                 2
         _ ->
             0
                 |> identity
     """},
    {"first binding on let line", """
     let a = 10
         b = a + 30
     in b
     """},
    {"pipe in let body", """
     let
         a = 1
     in
         a
             |> f
     """},
    {"nested let in case arm", """
     case x of
         A ->
             let
                 y = 1
             in
                 y
     """},
    {"nested let/case with else if", """
     let
         batteryOps =
             case model.batteryLevel of
                 Nothing ->
                     []
                 Just batteryLevel ->
                     let
                         batteryColor =
                             if batteryLevel <= 20 then
                                 PebbleColor.red
                             else if batteryLevel <= 40 then
                                 PebbleColor.chromeYellow
                             else
                                 PebbleColor.green
                     in
                     []
     in
     []
         |> PebbleUi.toUiNode
     """},
    {"in on own line with body on next line", """
     let counter = n + 1
     in
     counter + 2
     """},
    {"in on own line with indented body", """
     let counter = n + 1
     in
         counter + 2
     """},
    {"wildcard binding with split rhs", """
     let
         _ =
             value
     in
     0
     """},
    {"case arm let with in body on next line", """
     case x of
         A ->
             let
                 _ =
                     value
             in
             0
     """},
    {"nested case after let in case arm", """
     case msg of
         SvgReceived (Ok svg) ->
             let
                 figureId =
                     model.figure
             in
             case pieces of
                 [] ->
                     0
                 _ ->
                     1
     """},
    {"multiline tuple binding in let", """
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
     """},
    {"split Cmd.batch application", """
     let
         encodedBody =
             encodeFormData formData.fields
     in
     Cmd.batch
         [ Http.get url Nothing ]
     """},
    {"record literal in let binding", """
     let
         formData =
             { method = "POST"
             , action = "/api"
             }
     in
     formData
     """},
    {"wildcard tuple destructuring in let", """
     let
         msg = update model
         ( _, paths ) = msg
     in
     paths
     """},
    {"case inside list literal", """
     List.concat
         [ case x of
               A ->
                   1
               B ->
                   2
         ]
     """},
    {"multiline let binding with paren application arg", """
     case c of
         C.Sequenced l r ->
             let
                 pair =
                     horizontal config
                         ( layout config l
                         , layout config r
                         )
                 contents =
                     tie 10 pair
             in
             contents
     """},
    {"triple tuple case subject", """
     case ( maybeBytes, maybeUrl, pageData ) of
         ( Just bytes, Just url, Ok previous ) ->
             ( previous, NoEffect )
         ( Just bytes, Just _, Err _ ) ->
             ( model, NoEffect )
         _ ->
             ( model, NoEffect )
     """},
    {"split record argument", """
     case c of
         C.Wrap label a ->
             let
                 inner =
                     layout config a
             in
             Layout
                 { inArrows = []
                 , contents = [ inner ]
                 }
     """},
    {"function bindings in let", """
     let point x y = ""
         flag b = if b then 1 else 0
     in
     flag True
     """},
    {"function binding with multiline if before in case", """
     let point x y = ""
         flag b = if b then
                     1
                 else
                     0
     in case seg of
         M ( x, y ) ->
             ""
     """},
    {"multiline lambda expression", """
     \\title build (Schema data) ->
         let
             start = build data
         in
         start
     """},
    {"function let binding with nested case", """
     case c of
         C.Sequenced l r ->
             let
                 wallX polarity =
                     case polarity of
                         In ->
                             1
                         Out ->
                             0
             in
             wallX In
     """},
    {"lambda in record field", """
     Http.expectBytesResponse callback
         (\\bytes ->
             case bytes of
                 Good _ ->
                     Ok bytes
                 Bad _ ->
                     Err bytes
         )
     """},
    {"split multi-arg application", """
     case appMsg of
         UrlChanged url ->
             loadDataAndUpdateUrl
                 ( newPageData, newSharedData, newActionData )
                 Nothing
                 url
                 model
     """},
    {"split cons expression", """
     ( "twitter:card", cardValue card |> Head.raw |> Just )
         :: (case card of
                 Summary details ->
                     [ ( "twitter:title", details.title |> Head.raw |> Just ) ]
            )
     """},
    {"heredoc-style uniform indent", """
         let
             a = 1
         in
             a
     """},
    {"apply_left multiline", """
     Svg.g [] <|
         Svg.rect attrs []
             :: tail
     """},
    {"bool_and in if condition", """
     if crossed && not previousAbove && above && scan.rise == Nothing then
         Just 1
     else
         scan.rise
  """},
  {"filterMap lambda case arms", """
      model.inFlightFetchers
          |> Dict.toList
          |> List.filterMap
              (\\( _, ( id, fetcher ) ) ->
                  case fetcher.status of
                      Pages.ConcurrentSubmission.Reloading _ ->
                          Http.cancel (String.fromInt id)
                              |> Just
                      Pages.ConcurrentSubmission.Submitting ->
                          Nothing
                      Pages.ConcurrentSubmission.Complete _ ->
                          Nothing
              )
          |> Cmd.batch
  """},
  {"Http.request record with nested lambda case", """
    let
        encodedBody =
            encodeFormData formData.fields
    in
    Cmd.batch
        [ cancelStaleFetchers model
        , case Dict.get fetcherKey model.inFlightFetchers of
            Just ( inFlightId, _ ) ->
                Http.cancel (String.fromInt inFlightId)
            Nothing ->
                Cmd.none
        , Http.request
            { expect =
                Http.expectBytesResponse callback
                    (\\bytes ->
                        case bytes of
                            Http.GoodStatus_ _ bytesBody ->
                                let
                                    decodedAction =
                                        case Bytes.Decode.decode config.decodeResponse bytesBody of
                                            Just (ResponseSketch.Redirect redirectTo) ->
                                                RedirectResponse redirectTo
                                            _ ->
                                                ActionResponse Nothing
                                in
                                Ok ( Nothing, decodedAction )
                            Http.BadUrl_ string ->
                                Err <| Http.BadUrl string
                    )
            , tracker = Just (String.fromInt transitionId)
            , body = Http.emptyBody
            }
        ]
  """},
  {"pattern lambda with constructor let binding", """
     \\title build (Schema data) ->
         let
             start =
                 Schema { data | currentSection = Just title, sections = data.sections ++ [ Section title [] ] }

             (Schema next) =
                 build start
         in
         Schema { next | currentSection = data.currentSection }
  """},
  {"svg box lambda cons case", """
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
  """},
  {"split case arm in indented let body", """
     let
         f = 1
     in
         case seg of
             A ->
                 ""
     """},
    {"if then case else if chain", """
     if a then
         case args of
             [] ->
                 Nothing
             _ ->
                 Nothing
     else if b then
         case args of
             [x] ->
                 Just x
             _ ->
                 Nothing
     else
         Nothing
     """},
    {"if case let pipe withDefault nested case", """
     if b then
         case args of
             [ f, d1, d2 ] ->
                 let
                     finalizer = f
                     decoders = [d1, d2]
                 in
                 coalesceFixedSpan finalizer decoders
                     |> Maybe.withDefault
                         (case decoders of
                             [ c1, c2 ] ->
                                 Map2 finalizer c1 c2
                             _ ->
                                 Map2 finalizer d1 d2
                         )
                     |> Just
             _ ->
                 Nothing
     else
         Nothing
     """},
    {"inline let with deeper indented in before plus case", """
     let isolate = testState.isolate
         in
         phaseToInt isolate.phase * 10000
         + (case isolate.suspendedContinuation of
             Nothing -> 0
             Just (ContinuationRef contId) ->
                 phaseToInt isolate.phase * 100 + contId)
     """}
  ]

  for {name, source} <- @sources do
    test "parse_with_layout_lexer parses #{name}" do
      assert {:ok, _} = GeneratedExpressionParser.parse_with_layout_lexer(unquote(source))
    end

    test "default parse matches layout lexer for #{name}" do
      assert {:ok, default_ast} = GeneratedExpressionParser.parse(unquote(source))
      assert {:ok, layout_ast} = GeneratedExpressionParser.parse_with_layout_lexer(unquote(source))
      assert default_ast == layout_ast
    end

    @tag :layout_round_trip
    test "Pretty round_trip? for #{name}" do
      assert Pretty.round_trip?(unquote(source))
    end

    @tag :layout_round_trip_ast
    test "Pretty round_trip_ast? for #{name}" do
      assert Pretty.round_trip_ast?(unquote(source))
    end
  end

  test "default parse uses layout lexer for multiline sources" do
    source = """
    let
        a = 1
    in
        a
    """

    assert {:ok, default_ast} = GeneratedExpressionParser.parse(source)
    assert {:ok, layout_ast} = GeneratedExpressionParser.parse_with_layout_lexer(source)
    assert default_ast == layout_ast
  end

  test "layout lexer parses heredoc-style uniformly indented snippets" do
    source = """
         let
             batteryOps =
                 case model.batteryLevel of
                     Nothing ->
                         []
         in
             batteryOps
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "legacy ;; sources still use normalize path" do
    source = """
    case x of
        A ->
            1
    ;; B ->
            2
    """

    previous = Application.get_env(:elm_ex, :expr_layout_lexer)

    try do
      Application.put_env(:elm_ex, :expr_layout_lexer, true)
      assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
      assert length(branches) == 2
    after
      case previous do
        nil -> Application.delete_env(:elm_ex, :expr_layout_lexer)
        value -> Application.put_env(:elm_ex, :expr_layout_lexer, value)
      end
    end
  end

  test "layout lexer can be disabled via application env" do
    source = """
    let
        a = 1
    in
        a
    """

    previous = Application.get_env(:elm_ex, :expr_layout_lexer)

    try do
      Application.put_env(:elm_ex, :expr_layout_lexer, false)
      assert {:ok, _} = GeneratedExpressionParser.parse(source)
    after
      case previous do
        nil -> Application.delete_env(:elm_ex, :expr_layout_lexer)
        value -> Application.put_env(:elm_ex, :expr_layout_lexer, value)
      end
    end
  end

  test "inline let/in uses normalize path through default parse" do
    source = "let base = helper n in base + 1"

    assert {:ok, _} = GeneratedExpressionParser.parse(source)

    assert {:error, {1, :elm_ex_expr_parser, _}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "default parse falls back to legacy normalize when layout lexer rejects multiline &&" do
    source = """
    not (Platform.displayShapeIsRound model.displayShape)
        && model.sun
        /= Nothing
    """

    previous = Application.get_env(:elm_ex, :expr_layout_lexer)

    try do
      Application.put_env(:elm_ex, :expr_layout_lexer, true)

      assert {:error, {1, :elm_ex_expr_parser, _}} =
               GeneratedExpressionParser.parse_with_layout_lexer(source)

      assert {:ok, %{op: :bool_and}} = GeneratedExpressionParser.parse(source)
    after
      case previous do
        nil -> Application.delete_env(:elm_ex, :expr_layout_lexer)
        value -> Application.put_env(:elm_ex, :expr_layout_lexer, value)
      end
    end
  end

  test "default parse falls back to legacy normalize for multiline int case arms" do
    source = """
    case month of
        1 ->
            "Jan"

        2 ->
            "Feb"
    """

    previous = Application.get_env(:elm_ex, :expr_layout_lexer)

    try do
      Application.put_env(:elm_ex, :expr_layout_lexer, true)

      assert {:error, {1, :elm_ex_expr_parser, _}} =
               GeneratedExpressionParser.parse_with_layout_lexer(source)

      assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
      assert length(branches) == 2
    after
      case previous do
        nil -> Application.delete_env(:elm_ex, :expr_layout_lexer)
        value -> Application.put_env(:elm_ex, :expr_layout_lexer, value)
      end
    end
  end
end
