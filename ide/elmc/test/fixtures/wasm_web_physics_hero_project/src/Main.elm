module Main exposing (main)

{-| Minimal elm-physics + Svg animation for elmc WASM probing. -}

import Browser
import Browser.Events
import Duration
import Html exposing (Html)
import Length
import Physics exposing (Body, Contacts)
import Physics.Material as Material
import Plane3d
import Point3d
import Sphere3d
import Svg exposing (circle, svg, text, text_)
import Svg.Attributes as SA
import Time


type Id
    = Floor
    | Ball


type alias Model =
    { bodies : List ( Id, Body )
    , contacts : Contacts Id
    , accumulator : Float
    , lastMillis : Maybe Int
    }


type Msg
    = Frame Time.Posix


init : () -> ( Model, Cmd Msg )
init _ =
    ( { bodies =
            [ ( Floor, Physics.plane Plane3d.xy Material.wood )
            , ( Ball
              , Physics.sphere (Sphere3d.atOrigin (Length.meters 0.25)) Material.rubber
                    |> Physics.moveTo (Point3d.meters 0 0 1.5)
              )
            ]
      , contacts = Physics.emptyContacts
      , accumulator = 0
      , lastMillis = Nothing
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Frame now ->
            let
                nowMs =
                    Time.posixToMillis now

                dt =
                    case model.lastMillis of
                        Nothing ->
                            1 / 60

                        Just prev ->
                            min 0.05 (toFloat (nowMs - prev) / 1000)

                ( bodies, contacts, leftover ) =
                    stepFixed (model.accumulator + dt) model.bodies model.contacts
            in
            ( { model
                | bodies = bodies
                , contacts = contacts
                , accumulator = leftover
                , lastMillis = Just nowMs
              }
            , Cmd.none
            )


stepFixed :
    Float
    -> List ( Id, Body )
    -> Contacts Id
    -> ( List ( Id, Body ), Contacts Id, Float )
stepFixed accumulator bodies contacts =
    let
        stepSeconds =
            Duration.inSeconds (Duration.seconds (1 / 60))
    in
    if accumulator < stepSeconds then
        ( bodies, contacts, accumulator )

    else
        let
            onEarth =
                Physics.onEarth

            config =
                { onEarth | contacts = contacts }

            ( nextBodies, nextContacts ) =
                Physics.simulate config bodies
        in
        stepFixed (accumulator - stepSeconds) nextBodies nextContacts


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onAnimationFrame Frame


view : Model -> Html Msg
view model =
    let
        ballY =
            model.bodies
                |> List.filterMap
                    (\( id, body ) ->
                        case id of
                            Ball ->
                                Just (Point3d.zCoordinate (Physics.originPoint body) |> Length.inMeters)

                            Floor ->
                                Nothing
                    )
                |> List.head
                |> Maybe.withDefault 0

        cy =
            90 - ballY * 40
    in
    svg [ SA.viewBox "0 0 120 120", SA.width "120", SA.height "120" ]
        [ circle
            [ SA.cx "60"
            , SA.cy (String.fromFloat cy)
            , SA.r "12"
            , SA.fill "#5A8F2F"
            ]
            []
        , text_
            [ SA.x "60"
            , SA.y "110"
            , SA.textAnchor "middle"
            , SA.fontSize "10"
            , SA.fill "#334155"
            ]
            [ text "elm→pebble" ]
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
