module Main exposing (main)

import Companion.Types exposing (Color(..), Measure(..), PhoneToWatch(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Dict
import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { screenW : Int
    , screenH : Int
    , selected : Int
    , active : Maybe Int
    , cases : List CaseState
    , extras : ExtrasState
    }


type alias CaseState =
    { name : String
    , status : Status
    }


type alias ExtrasState =
    { boolOk : Bool
    , stringOk : Bool
    , pointsOk : Bool
    , labelsOk : Bool
    }


type Status
    = Pending
    | Running
    | Pass
    | Fail


type Msg
    = SelectPressed
    | DownPressed
    | FromPhone PhoneToWatch


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { screenW = context.screen.width
      , screenH = context.screen.height
      , selected = 0
      , active = Nothing
      , cases = initialCases
      , extras = emptyExtras
      }
    , CompanionWatch.sendWatchToPhone Ping
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            runSelected model

        DownPressed ->
            ( { model | selected = nextIndex model.selected (List.length model.cases) }, Cmd.none )

        FromPhone phoneMsg ->
            handlePhone model phoneMsg


runSelected : Model -> ( Model, Cmd Msg )
runSelected model =
    let
        idx =
            model.selected

        cases =
            model.cases
                |> List.indexedMap
                    (\i case_ ->
                        if i == idx then
                            { case_ | status = Running }

                        else if case_.status == Running then
                            { case_ | status = Pending }

                        else
                            case_
                    )
    in
    ( { model | active = Just idx, cases = cases, extras = emptyExtras }
    , sendForIndex idx
    )


handlePhone : Model -> PhoneToWatch -> ( Model, Cmd Msg )
handlePhone model phoneMsg =
    case model.active of
    Nothing ->
      if phoneMsg == Pong then
          ( { model | cases = setCaseStatus 0 Pass model.cases }, Cmd.none )

      else
          ( model, Cmd.none )

    Just idx ->
      if idx == extrasIndex then
          handleExtras model phoneMsg

      else
          case ( idx, phoneMsg ) of
          ( 0, Pong ) ->
            finishCase model idx Pass

          ( 1, EchoColor Red ) ->
            finishCase model idx Pass

          ( 2, EchoMeasure (Liters 3) ) ->
            finishCase model idx Pass

          ( 3, EchoPoint point ) ->
            if point.x == 1 && point.y == 2 then
                finishCase model idx Pass

            else
                finishCase model idx Fail

          ( 4, EchoCounts counts ) ->
            if counts == [ 1, 2, 3 ] then
                finishCase model idx Pass

            else
                finishCase model idx Fail

          _ ->
            finishCase model idx Fail


handleExtras : Model -> PhoneToWatch -> ( Model, Cmd Msg )
handleExtras model phoneMsg =
    let
    extras =
        case phoneMsg of
        PushBool True ->
          { model.extras | boolOk = True }

        PushString "elm" ->
          { model.extras | stringOk = True }

        PushPoints points ->
            case List.head points of
                Just point ->
                    if point.x == 4 && point.y == 5 then
                        { model.extras | pointsOk = True }

                    else
                        model.extras

                Nothing ->
                    model.extras

        PushLabels labels ->
          if Dict.get "k" labels == Just 9 then
              { model.extras | labelsOk = True }

          else
              model.extras

        _ ->
          model.extras

    allOk =
        extras.boolOk && extras.stringOk && extras.pointsOk && extras.labelsOk
  in
  if allOk then
      finishCase { model | extras = extras } extrasIndex Pass

  else
      ( { model | extras = extras }, Cmd.none )


finishCase : Model -> Int -> Status -> ( Model, Cmd Msg )
finishCase model idx status =
    ( { model
    | active = Nothing
        , cases = setCaseStatus idx status model.cases
      }
    , Cmd.none
  )


sendForIndex : Int -> Cmd Msg
sendForIndex idx =
    case idx of
    0 ->
      CompanionWatch.sendWatchToPhone Ping

    1 ->
      CompanionWatch.sendWatchToPhone (SendColor Red)

    2 ->
      CompanionWatch.sendWatchToPhone (SendMeasure (Liters 3))

    3 ->
      CompanionWatch.sendWatchToPhone (SendPoint { x = 1, y = 2 })

    4 ->
      CompanionWatch.sendWatchToPhone (SendCounts [ 1, 2, 3 ])

    _ ->
      CompanionWatch.sendWatchToPhone RequestPhoneExtras


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Down DownPressed
        , CompanionWatch.onPhoneToWatch FromPhone
        ]


view : Model -> Ui.UiNode
view model =
    let
    lineH =
        16

    startY =
        28

    summary =
        passCount model.cases
        ++ "/"
        ++ String.fromInt (List.length model.cases)
        ++ " PASS"

    label x y text_ =
        Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = y, w = model.screenW - 8, h = lineH } text_
  in
  Ui.windowStack
    [ Ui.window 1
        [ Ui.canvasLayer 1
            [ Ui.clear Color.white
            , label 4 4 "Protocol matrix"
            , label 4 14 summary
            , label 4 startY (statusLine model)
            , label 4 (startY + lineH) "SEL run  DN next"
            ]
        ]
    ]


statusLine : Model -> String
statusLine model =
    case dropAt model.selected model.cases of
    Nothing ->
      "--"

    Just case_ ->
      case_.name ++ " " ++ statusLabel case_.status


dropAt : Int -> List a -> Maybe a
dropAt idx items =
    items
    |> List.drop idx
    |> List.head


statusLabel : Status -> String
statusLabel status =
    case status of
    Pending ->
      "--"

    Running ->
      ".."

    Pass ->
      "OK"

    Fail ->
      "FAIL"


passCount : List CaseState -> String
passCount cases =
    cases
    |> List.filter (\case_ -> case_.status == Pass)
    |> List.length
    |> String.fromInt


setCaseStatus : Int -> Status -> List CaseState -> List CaseState
setCaseStatus idx status cases =
    List.indexedMap
    (\i case_ ->
      if i == idx then
          { case_ | status = status }

      else
          case_
    )
    cases


nextIndex : Int -> Int -> Int
nextIndex current total =
    modBy total (current + 1)


initialCases : List CaseState
initialCases =
    [ case_ "Ping"
    , case_ "Enum"
    , case_ "Union"
    , case_ "Record"
    , case_ "List"
    , case_ "Extras"
    ]


case_ : String -> CaseState
case_ name =
    { name = name, status = Pending }


emptyExtras : ExtrasState
emptyExtras =
    { boolOk = False, stringOk = False, pointsOk = False, labelsOk = False }


extrasIndex : Int
extrasIndex =
    5


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
