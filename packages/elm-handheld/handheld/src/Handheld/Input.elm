module Handheld.Input exposing
    ( Button(..)
    , Point
    , onPress
    , presses
    , taps
    )

{-| Buttons and touch.

Match a button instead of comparing numbers.

    import Handheld.Input as Input exposing (Button(..))

    type Msg
        = Pressed Button
        | Tapped Input.Point

    subscriptions _ =
        Sub.batch
            [ Input.presses Pressed
            , Input.taps Tapped
            ]

    update msg model =
        case msg of
            Pressed Up ->
                ( { model | y = model.y - 1 }, Cmd.none )

            Pressed Select ->
                ( model, Cmd.none )

            Pressed _ ->
                ( model, Cmd.none )

            Tapped point ->
                ( { model | x = point.x, y = point.y }, Cmd.none )

`presses` covers every button, including Flipper Back. `onPress` listens to
one button. `taps` is for a panel whose launch context has `touch` set.
The host posts each press and tap into `update`.

# Buttons
@docs Button, presses, onPress

# Touch
@docs Point, taps
-}


{-| A physical button.

`A` and `B` are the MeowKit face buttons. `Back` is the Flipper back key.
`Select` is the center key, labeled OK on the device. The d-pad exists on both.
-}
type Button
    = A
    | B
    | Up
    | Down
    | Left
    | Right
    | Select
    | Back


{-| A touch position on the panel.
-}
type alias Point =
    { x : Int
    , y : Int
    }


{-| Subscribe to every button press.
-}
presses : (Button -> msg) -> Sub msg
presses toMsg =
    Sub.batch
        [ onPress A (toMsg A)
        , onPress B (toMsg B)
        , onPress Up (toMsg Up)
        , onPress Down (toMsg Down)
        , onPress Left (toMsg Left)
        , onPress Right (toMsg Right)
        , onPress Select (toMsg Select)
        , onPress Back (toMsg Back)
        ]


{-| Subscribe to one button.
-}
onPress : Button -> msg -> Sub msg
onPress _ _ =
    Sub.none


{-| Subscribe to a finger tap. The point is in panel pixels.
-}
taps : (Point -> msg) -> Sub msg
taps _ =
    Sub.none
