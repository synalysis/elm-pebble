module Handheld.Color exposing
    ( Color
    , black
    , off
    , on
    , rgb
    , white
    )

{-| Panel colors.

A color is a packed pixel. `rgb` builds an RGB565 value for a color panel.
`on` and `off` are the two pixels of a mono panel.

    import Handheld.Color as Color
    import Handheld.Ui as Ui

    view model =
        Cmd.batch
            [ Ui.clear Color.black
            , Ui.fill { x = 0, y = 0, width = model.width, height = 8 } Color.white
            ]

@docs Color, rgb, black, white, on, off
-}

import Bitwise


{-| Packed pixel. Pass it straight to `Handheld.Ui`.
-}
type alias Color =
    Int


{-| Opaque black, and the unlit pixel on a mono panel.
-}
black : Color
black =
    0


{-| Opaque white.
-}
white : Color
white =
    rgb 255 255 255


{-| Lit pixel on a mono panel.
-}
on : Color
on =
    1


{-| Unlit pixel on a mono panel.
-}
off : Color
off =
    0


{-| Build an opaque RGB565 color. Each channel is `0` to `255`.
-}
rgb : Int -> Int -> Int -> Color
rgb r g b =
    let
        red =
            Bitwise.shiftRightBy 3 (clamp 0 255 r)

        green =
            Bitwise.shiftRightBy 2 (clamp 0 255 g)

        blue =
            Bitwise.shiftRightBy 3 (clamp 0 255 b)
    in
    Bitwise.or (Bitwise.shiftLeftBy 11 red)
        (Bitwise.or (Bitwise.shiftLeftBy 5 green) blue)
