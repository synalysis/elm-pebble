defmodule ElmEx.Frontend.LetLayoutTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.LetLayout
  alias ElmEx.Test.LetExprHelpers

  test "validate rejects let and in on the same line" do
    assert {:error, {:inline_let_in, 1}} =
             LetLayout.validate("let counter = n + 1 in counter + 2")
  end

  test "validate accepts multiline let/in layout" do
    source = """
    let
        counter =
            n + 1
    in
    counter + 2
    """

    assert :ok = LetLayout.validate(source)
    assert {:ok, expr} = GeneratedExpressionParser.parse(source)
    assert expr.op == :let_bindings
  end

  test "parses multiline let with first binding on let line and additional bindings" do
    source = """
    let a = 10 + 20
        b = a + 30
        c = b * 2
    in c
    """

    assert {:ok, expr} = GeneratedExpressionParser.parse(source)
    assert expr.op == :let_bindings
    assert LetExprHelpers.first_binding_name(expr) == "a"
  end

  test "validate accepts first binding on let line when in is on its own line" do
    source = """
    let counter = n + 1
    in
    counter + 2
    """

    assert :ok = LetLayout.validate(source)
    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "parses nested let in case branch after normalization" do
    source = """
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
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "GeneratedExpressionParser normalizes inline let/in before parsing" do
    assert {:ok, expr} = GeneratedExpressionParser.parse("let base = helper n in base + 1")
    assert expr.op == :let_bindings
    assert LetExprHelpers.first_binding_name(expr) == "base"
  end

  test "normalizes let when in is at end of line and body follows on next line" do
    source = "let appended = String.append left right in\n    String.length appended"

    assert {:ok, expr} = GeneratedExpressionParser.parse(source)
    assert expr.op == :let_bindings
    assert LetExprHelpers.first_binding_name(expr) == "appended"
  end

  test "parses top-level let with typed bindings and nested case branches" do
    source = """
    let
        cancelIfStale : Effect msg
        cancelIfStale =
            case model.transition of
                Just ( transitionKey, Pages.Navigation.Loading _ _ ) ->
                    CancelRequest transitionKey

                _ ->
                    NoEffect

        fetchEffect : Effect msg
        fetchEffect =
            FetchFrozenViews { path = urlToGet.path, query = urlToGet.query, body = Nothing }
    in
    ( model, Batch [ fetchEffect, cancelIfStale, effect ] )
    """

    assert {:ok, expr} = GeneratedExpressionParser.parse(source)
    assert expr.op == :let_bindings
    assert LetExprHelpers.first_binding_name(expr) == "cancelIfStale"
  end

  test "parses tangram companion update with nested case in branch" do
    source = """
    case msg of
        CatalogReceived (Ok json) ->
            case catalogNames json of
                [] ->
                    ( model, Cmd.none )

                names ->
                    ( { model | names = names }, Cmd.none )

        SvgReceived (Ok svg) ->
            let
                figureId =
                    model.figure

                pieces =
                    parseSvgPieces svg
            in
            case pieces of
                [] ->
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SvgReceived (Err _) ->
            ( model, Cmd.none )
    """

    assert {:ok, %{op: :case}} = GeneratedExpressionParser.parse(source)
  end

  test "parses List.concat with embedded case and trailing pipe" do
    source = """
    let
        cx =
            model.screenW // 2

        figure =
            case model.companionFigure of
                Just companionFigure ->
                    companionFigure

                Nothing ->
                    minute
    in
    List.concat
        [ [ Ui.clear Color.white
          , Ui.circle { x = cx, y = cy } 60 Color.black
          ]
        , case model.downloadedPieces of
            [] ->
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 0, y = 0, w = 10, h = 10 } "x" ]

            pieces ->
                pieces
        , [ Ui.fillCircle { x = 1, y = 2 } 4 Color.white
          , Ui.fillCircle { x = 3, y = 4 } 3 Color.white
          ]
        |> Ui.toUiNode
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "parses postfix field access on parenthesized expression" do
    assert {:ok, %{op: :qualified_call, target: "String.fromInt", args: [arg]}} =
             GeneratedExpressionParser.parse("String.fromInt (compute 42).y")

    assert %{op: :field_access, field: "y", arg: %{op: :call, name: "compute"}} = arg
  end

  test "parses parenthesized constructor pattern in cons case branch" do
    source = """
    case list of
        (Wrapped InnerA) :: [] ->
            "single-wrapped-A"
        _ ->
            "other"
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    [%{pattern: %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, _tail]}}} | _] =
      branches

    assert %{kind: :constructor, name: "Wrapped", arg_pattern: %{kind: :constructor, name: "InnerA"}} = head
  end

  test "parses wildcard tuple destructuring in multiline let" do
    source = """
    let
        msg = update model
        ( _, paths ) = msg
    in
    paths
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "parses discard wildcard binding in let" do
    source = """
    let
        _ =
            value
    in
    0
    """

    assert {:ok, %{op: :let_bindings, bindings: [%{kind: :discard} | _]}} =
             GeneratedExpressionParser.parse(source)
  end

  test "parses discard wildcard binding inside case branch" do
    source = """
    case msg of
        BatteryChanged value ->
            let
                _ =
                    value
            in
            ( model, Cmd.none )
    """

    assert {:ok, %{op: :case}} = GeneratedExpressionParser.parse(source)
  end

  test "parses constructor pattern binding after multiline let value" do
    source = """
    \\title build (Schema data) ->
        let
            start =
                Schema { data | currentSection = Just title, sections = data.sections ++ [ Section title [] ] }

            (Schema next) =
                build start
        in
        Schema { next | currentSection = data.currentSection }
    """

    assert {:ok, %{op: :lambda}} = GeneratedExpressionParser.parse(source)
  end

  test "parses scientific notation float literals" do
    assert {:ok, %{op: :float_literal, value: 5.0e-324}} =
             GeneratedExpressionParser.parse("5.0e-324")

    assert {:ok, %{op: :float_literal}} = GeneratedExpressionParser.parse("1.0e-300")
  end

  test "preserves hyphenated string literals during numeric minus normalization" do
    assert {:ok, %{op: :string_literal, value: "shrink-0"}} =
             GeneratedExpressionParser.parse(~s/"shrink-0"/)

    assert {:ok,
            %{
              op: :constructor_call,
              target: "Tailwind",
              args: [%{op: :string_literal, value: "top-0 z-50"}]
            }} =
             GeneratedExpressionParser.parse(~s/Tailwind "top-0 z-50"/)
  end

  test "still normalizes numeric subtraction outside string literals" do
    assert {:ok, %{op: :sub_const, var: "width", value: 1}} =
             GeneratedExpressionParser.parse("width-1")
  end

  test "parses leading-zero decimal float literals" do
    assert {:ok, %{op: :float_literal, value: 0.9856}} =
             GeneratedExpressionParser.parse("0.9856")

    assert {:ok, %{op: :float_literal, value: 0.020}} =
             GeneratedExpressionParser.parse("0.020")

    assert {:error, {:invalid_number_literal, :leading_zero}} =
             GeneratedExpressionParser.parse("012")
  end

  test "parses unary minus after comparison operators" do
    assert {:ok, %{op: :compare, kind: :lt, right: %{op: :qualified_call, target: "Basics.negate"}}} =
             GeneratedExpressionParser.parse("normalized < -pi")
  end

  test "parses operator sections for apL and apR" do
    assert {:ok, %{op: :var, name: "<|"}} = GeneratedExpressionParser.parse("(<|)")
    assert {:ok, %{op: :var, name: "|>"}} = GeneratedExpressionParser.parse("(|>)")
    assert {:ok, %{op: :call, name: "|>"}} = GeneratedExpressionParser.parse("(|>) 10 f")
  end

  test "parses field accessor composition without breaking .term" do
    source = "Maybe.map (.term >> blockRefs)"

    assert {:ok, %{op: :qualified_call, target: "Maybe.map"}} =
             GeneratedExpressionParser.parse(source)
  end

  test "parses lambda tuple pattern with trailing wildcards" do
    source = "\\( revEntries, _, _ ) -> List.reverse revEntries"

    assert {:ok, %{op: :lambda}} = GeneratedExpressionParser.parse(source)
  end

  test "GeneratedExpressionParser preserves triple-quoted string contents" do
    source = ~S|D.decodeString (D.field "name" D.string) """{"name": "Alice"}"""|

    assert {:ok,
            %{
              op: :qualified_call,
              target: "D.decodeString",
              args: [_, %{op: :string_literal, value: ~s|{"name": "Alice"}|}]
            }} = GeneratedExpressionParser.parse(source)
  end

  test "parses outer case branches after UrlChanged record update fields" do
    source = """
    case appMsg of
        UrlChanged url ->
            case model.pendingData of
                Just ( newPageData, newSharedData, newActionData ) ->
                    loadDataAndUpdateUrl
                        ( newPageData, newSharedData, newActionData )
                        Nothing
                        url
                        url
                        False
                        config
                        model

                Nothing ->
                    if model.url.path == url.path && model.url.query == url.query then
                        if url.fragment == Nothing then
                            ( { model
                                | url = url
                              }
                            , ScrollToTop
                            )

                        else
                            ( { model
                                | url = url
                              }
                            , NoEffect
                            )

                    else
                        ( model
                        , NoEffect
                        )
                            |> startNewGetLoad url

        FetcherComplete _ fetcherKey _ userMsgResult ->
            ( model, Cmd.none )

        UserMsg userMsg_ ->
            case userMsg_ of
                Pages.Internal.Msg.UserMsg userMsg ->
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)

    assert Enum.map(branches, & &1.pattern.name) == [
             "UrlChanged",
             "FetcherComplete",
             "UserMsg"
           ]
  end

  test "does not postflight-renormalize flat outer update case with distant record fields" do
    source = """
    case appMsg of
        FormMsg formMsg ->
            let
                ( newModel, formCmd ) =
                    Form.update formMsg model.pageFormState
            in
            ( { model | pageFormState = newModel }
            , RunCmd formCmd
            )

        UrlChanged url ->
            case model.pendingData of
                Just ( newPageData, newSharedData, newActionData ) ->
                    loadDataAndUpdateUrl
                        ( newPageData, newSharedData, newActionData )
                        Nothing
                        url
                        url
                        False
                        config
                        model

                Nothing ->
                    ( model, NoEffect )

        UserMsg userMsg_ ->
            case userMsg_ of
                Pages.Internal.Msg.Submit fields ->
                    ( { model | nextTransitionKey = model.nextTransitionKey + 1 }
                    , FetchFrozenViews
                        { path = model.url.path
                        , query = model.url.query
                        , body = Just (encodeFormData fields.fields)
                        }
                    )

                _ ->
                    ( model, NoEffect )
    """

    prep = GeneratedExpressionParser.prepare_for_debug(source)

    refute String.contains?(prep, "of);;")
    refute String.contains?(prep, "FormMsg formMsg -> ((let")

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(prep)

    assert Enum.map(branches, & &1.pattern.name) == [
             "FormMsg",
             "UrlChanged",
             "UserMsg"
           ]
  end

  test "parses filterMap lambda case arms and performUserMsg flat case" do
    cancel =
      """
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
      """

    perform_user_msg =
      """
      case model.pageData of
          Ok pageData ->
              let
                  ( userModel, userCmd ) =
                      config.update model.pageFormState model.key userMsg pageData.userModel
                  updatedPageData =
                      Ok { pageData | userModel = userModel }
              in
              ( { model | pageData = updatedPageData }
              , Batch [ effect, UserCmd userCmd ]
              )
          Err _ ->
              ( model, effect )
      """

    assert {:ok, %{op: :pipe_chain}} = GeneratedExpressionParser.parse(cancel)
    assert {:ok, tree} = GeneratedExpressionParser.parse(perform_user_msg)
    assert tree.op in [:case, :let_in, :let_bindings]
  end

  test "parses nested let with /= rhs and a following binding" do
    source = """
    case scan.prevAbove of
        Nothing ->
            scan

        Just previousAbove ->
            let
                crossed =
                    above /= previousAbove

                rise =
                    1
            in
            { scan | rise = rise, prevAbove = Just above }
    """

    assert {:ok, tree} = GeneratedExpressionParser.parse(source)
    # yecc lowers `case` to a synthetic let_in binding the subject as caseSubject
    assert tree.op in [:case, :let_in, :let_bindings]
  end

  test "parses scanMoonEvents-style nested let inside outer let/case" do
    source = """
    if minute > 1440 then
        scan
    else
        let
            sampleMinute =
                if minute == 1440 then
                    1439
                else
                    minute

            above =
                moonAltitudeRad (Time.millisToPosix (baseUtcMillis + (sampleMinute * 60000))) location > degrees -0.3

            nextScan =
                case scan.prevAbove of
                    Nothing ->
                        { scan
                            | prevAbove = Just above
                            , aboveSamples = countAbove above scan.aboveSamples
                            , totalSamples = scan.totalSamples + 1
                        }

                    Just previousAbove ->
                        let
                            crossed =
                                above /= previousAbove

                            rise =
                                if crossed && not previousAbove && above && scan.rise == Nothing then
                                    Just 1
                                else
                                    scan.rise
                        in
                        { scan
                            | rise = rise
                            , prevAbove = Just above
                            , aboveSamples = countAbove above scan.aboveSamples
                            , totalSamples = scan.totalSamples + 1
                        }
        in
        scanMoonEvents location baseUtcMillis stepMin (minute + stepMin) nextScan
    """

    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "parses nested case expression as outer case branch body" do
    source = """
    case msg of
        MinuteChanged minute ->
            case model.now of
                Nothing ->
                    ( model, Cmd.none )

                Just now ->
                    ( { model | now = Just { now | minute = minute } }
                    , Cmd.none
                    )
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    assert length(branches) == 1
    assert match?(%{pattern: %{name: "MinuteChanged"}}, hd(branches))
  end

  test "parses sibling union case arms when branch body is let with nested case" do
    source = """
    case c of
        C.Leaf a ->
            let
                bound =
                    leafExtent config a
            in
            case extentOf bound of
                Just innerExtent ->
                    Leaf { value = a, extent = innerExtent }

                _ ->
                    Empty

        C.Sequenced l r ->
            let
                pair =
                    horizontal config ( layout config l, layout config r )
            in
            pair

        C.Aside a b ->
            vertical config ( layout config a, layout config b )
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)

    assert Enum.map(branches, & &1.pattern.name) == [
             "C.Leaf",
             "C.Sequenced",
             "C.Aside"
           ]
  end

  test "parses layout-style case arm with let/in/case when blank lines are collapsed" do
    source = """
    case c of
        C.Unit ->
            Empty
        C interface (C.Leaf l) ->
            let
                inner =
                    composeLayout config (C.Leaf l)
                innerBound =
                    boundOf inner
            in
            case Bound.extentOf innerBound of
                Just innerExtent ->
                    let
                        inputArrows =
                            stubsFor In interface innerExtent Arrow.stubForEdge
                        outArrows =
                            stubsFor Out interface innerExtent Arrow.stubForEdge
                    in
                    Layout
                        { inArrows = inputArrows
                        , wrapping = Nothing
                        , contents = [ inner ]
                        , outArrows = outArrows
                        , extent = innerExtent
                        }
                _ ->
                    Empty
        -- A composition of smaller pieces
        C _ composition ->
            composeLayout config composition
    """

    collapsed =
      source
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(collapsed)

    leaf_arm =
      Enum.find(
        branches,
        &match?(
          %{
            pattern: %{
              name: "C",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{name: "interface", kind: :var},
                  %{name: "C.Leaf", kind: :constructor}
                ]
              }
            }
          },
          &1
        )
      )

    assert LetExprHelpers.nested_let_expr?(leaf_arm)
    refute Enum.any?(branches, &match?(%{pattern: %{kind: :wildcard}}, &1))
    assert length(branches) == 3
  end

  test "parses composeLayout Sequenced arm with let and nested tuple case" do
    source = """
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
                extents =
                    Maybe.map (Tuple.mapBoth boundOf boundOf) contents
            in
            case ( contents, extents ) of
                ( Just ( Layout al, Layout bl ), Just ( Just extentA, Just extentB ) ) ->
                    let
                        hull =
                            Extent.hull <| NE.Nonempty extentA [ extentB ]
                        wallX polarity =
                            case polarity of
                                In ->
                                    hull.lo.x
                                Out ->
                                    hull.hi.x
                    in
                    Layout
                        { inArrows = safeArrows In al.inArrows
                        , wrapping = Nothing
                        , contents = [ Layout al, Layout bl ]
                        , outArrows = safeArrows Out bl.outArrows
                        , extent = hull
                        }

                _ ->
                    Empty
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    sequenced = Enum.find(branches, &(&1.pattern.name == "C.Sequenced"))
    assert LetExprHelpers.nested_let_expr?(sequenced)
  end

  test "parses composeLayout Aside arm with parenthesized let and inner tuple case" do
    source = """
    case c of
        C.Aside a b ->
            let
                contents =
                    vertical config ( layout config a, layout config b )
                extents =
                    Tuple.mapBoth boundOf boundOf contents
            in
            case ( contents, extents ) of
                ( ( Layout al, Layout bl ), ( Just extentA, Just extentB ) ) ->
                    let
                        hull =
                            Extent.hull <| NE.Nonempty extentA [ extentB ]
                        displaceToAvoidCorner polarity selfExtent =
                            case polarity of
                                In ->
                                    hull.lo.x - selfExtent.lo.x
                                Out ->
                                    hull.hi.x - selfExtent.hi.x
                    in
                    Layout
                        { inArrows = []
                        , wrapping = Nothing
                        , contents = []
                        , outArrows = []
                        , extent = hull
                        }

                _ ->
                    Empty
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    aside = Enum.find(branches, &(&1.pattern.name == "C.Aside"))
    assert LetExprHelpers.nested_let_expr?(aside)
  end

  test "parses composeLayout Wrap arm with tuple destructuring let binding" do
    source = """
    case c of
        C.Wrap label a ->
            let
                inner =
                    layout config a
                innerBound =
                    boundOf inner
                tr =
                    Vec2 10 10
                ( contents, fullExtent, wrappingExtent ) =
                    case innerBound of
                        Just extent ->
                            ( translate tr inner, extent, extent )

                        _ ->
                            ( translate tr inner, innerBound, innerBound )
            in
            contents
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    wrap = Enum.find(branches, &(&1.pattern.name == "C.Wrap"))
    assert LetExprHelpers.nested_let_expr?(wrap)
  end

  test "parses composeLayout Wrap inner case contents of without leaking wildcard arm" do
    source = """
    case c of
        C.Wrap label a ->
            let
                inner =
                    layout config a
                ( contents, fullExtent, wrappingExtent ) =
                    case innerBound of
                        Just extent ->
                            ( translate tr inner, extent, extent )
                        _ ->
                            ( translate tr inner, innerBound, innerBound )
            in
            case contents of
                Layout al ->
                    Layout
                        { inArrows = al.inArrows
                        , wrapping = Nothing
                        , contents = [ contents ]
                        , outArrows = al.outArrows
                        , extent = fullExtent
                        }
                _ ->
                    Empty
    """

    collapsed =
      source
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(collapsed)
    refute Enum.any?(branches, &match?(%{pattern: %{kind: :wildcard}}, &1))
    assert length(branches) == 1
    assert match?(%{pattern: %{name: "C.Wrap"}}, hd(branches))
  end

  test "parses flat composeLayout Aside arm fragment from wiring layout" do
    source =
      "case c of C.Aside a b -> (let contents = vertical config ( layout config a, layout config b ) ; extents = Tuple.mapBoth boundOf boundOf contents in case ( contents, extents ) of ( ( Layout al, Layout bl ), ( Just extentA, Just extentB ) ) -> (let hull = Extent.hull <| NE.Nonempty extentA [ extentB ] in Layout { extent = hull };;_ -> Empty;; C.Wrap label a -> 1"

    prep = GeneratedExpressionParser.prepare_for_debug(source)
    assert {:ok, %{op: :case}} = GeneratedExpressionParser.parse(prep)
  end

  test "parses ++ (case …) with multiline arms" do
    source = """
    base ++ (case details of
        Website ->
            [ 1 ]
        Article x ->
            [ 2 ]
    )
    """

    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "parses record view with embedded multiline case in list" do
    source = """
    { title = "Greetings"
        , body =
            [ Html.div []
                [ case app.data.name of
                    Just name ->
                        Html.text ("Hello " ++ name)
                    Nothing ->
                        Html.text "hi"
                ]
            ]
        }
    """

    assert {:ok, %{op: :record_literal}} = GeneratedExpressionParser.parse(source)
  end

  test "parses startFetcher2-style lambda case inside Http expect record field" do
    source = """
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
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "parses tuple-embedded case with trailing pipeline in record update" do
    source = """
    ( { model
        | transition =
            ( model.nextTransitionKey
            , case model.transition of
                Just _ ->
                    Loading
                _ ->
                    Done
            )
                |> Just
      }
    , Cmd.none
    )
    """

    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "parses tuple-embedded navigation case with trailing pipeline" do
    source = """
    ( model.nextTransitionKey
    , case model.transition of
        Just ( _, Pages.Navigation.LoadAfterSubmit submitData _ _ ) ->
            Pages.Navigation.LoadAfterSubmit
                submitData
                (urlToGet.path |> UrlPath.fromString)
                Pages.Navigation.Load
        Just ( _, Pages.Navigation.Submitting submitData ) ->
            Pages.Navigation.LoadAfterSubmit
                submitData
                (urlToGet.path |> UrlPath.fromString)
                Pages.Navigation.Load
        _ ->
            Pages.Navigation.Loading
                (urlToGet.path |> UrlPath.fromString)
                Pages.Navigation.Load
    )
        |> Just
    """

    assert {:ok, %{op: :pipe_chain}} = GeneratedExpressionParser.parse(source)
  end

  test "parses nested percentDecode cases in query param update" do
    source = """
    case String.split "=" segment of
        [ rawKey, rawValue ] ->
            case Url.percentDecode rawKey of
                Nothing ->
                    dict
                Just key ->
                    case Url.percentDecode rawValue of
                        Nothing ->
                            dict
                        Just value ->
                            Dict.insert key [ value ] dict
        _ ->
            dict
    """

    assert {:ok, tree} = GeneratedExpressionParser.parse(source)
    assert tree.op in [:case, :let_in, :let_bindings]
  end

  test "parses multiline list case arms with wrapped constructor bodies" do
    source = """
    case segments of
        [ "packages", author, name, version, moduleName ] ->
            Just
                (Packages__Author___Name___Version___ModuleName_
                    { author = author, name = name, version = version, moduleName = moduleName }
                )
        [ "packages", author, name, version ] ->
            Just (Packages__Author___Name___Version_ { author = author, name = name, version = version })
        _ ->
            Nothing
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    assert length(branches) == 3
  end

  test "parses Twitter rawTags-style embedded case in cons list" do
    source = """
    ( "twitter:card", cardValue card |> Head.raw |> Just )
        :: (case card of
                Summary details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just )
                    , ( "twitter:site", details.siteUser |> Maybe.map Head.raw )
                    ]

                App details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just ) ]

                Player details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just ) ]
           )
    """

    assert {:ok, %{op: :qualified_call}} = GeneratedExpressionParser.parse(source)
  end

  test "parses Svg.box-style lambda with nested case after cons" do
    source = """
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
    """

    assert {:ok, %{op: :lambda}} = GeneratedExpressionParser.parse(source)
  end

  test "parses let binding with record literal containing line comment" do
    source = """
    let
        formData =
            { -- TODO remove hardcoding
              method = Form.Get
            , action = url
            , fields = []
            , id = Nothing
            }
    in
    formData
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "parses let with multiline if/else binding before in case" do
    source = """
    let point x y = ""
        flag b = if b then
                    1
                else
                    0
    in case seg of
        M ( x, y ) ->
            ""
    """

    assert {:ok, %{op: :let_bindings}} = GeneratedExpressionParser.parse(source)
  end

  test "parses triple tuple case with inner and outer wildcard arms after Err branch" do
    source = """
    case ( maybeBytes, maybeUrl, pageData ) of
        ( Just bytes, Just url, Ok previous ) ->
            ( previous, NoEffect )

        ( Just bytes, Just _, Err _ ) ->
            let
                pageDataResult =
                    case decode bytes of
                        Just value ->
                            Just value

                        _ ->
                            Nothing
            in
            case pageDataResult of
                Just value ->
                    ( { model | pageData = Ok value }, NoEffect )

                _ ->
                    ( { model | pendingFrozenViewsUrl = Nothing }, NoEffect )

        _ ->
            ( { model | pendingFrozenViewsUrl = Nothing }, NoEffect )
    """

    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "starter watch template Main.elm parses through generated frontend" do
    path =
      Path.expand(
        "../../ide/priv/project_templates/starter_watch/src/Main.elm",
        __DIR__
      )

    if File.exists?(path) do
      assert {:ok, module} = GeneratedParser.parse_file(path)
      assert module.name == "Main"
      assert Enum.any?(module.declarations, &(&1.name == "handleAppMsg"))
    else
      assert true
    end
  end
end
