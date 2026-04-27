module Pebble.Ui.Color exposing
    ( Color(..)
    , argb8
    , indexed
    , rgb
    , rgba
    , toInt
    , clearColor
    , black
    , oxfordBlue
    , dukeBlue
    , blue
    , darkGreen
    , midnightGreen
    , cobaltBlue
    , blueMoon
    , islamicGreen
    , jaegerGreen
    , tiffanyBlue
    , vividCerulean
    , green
    , malachite
    , mediumSpringGreen
    , cyan
    , bulgarianRose
    , imperialPurple
    , indigo
    , electricUltramarine
    , armyGreen
    , darkGray
    , liberty
    , veryLightBlue
    , kellyGreen
    , mayGreen
    , cadetBlue
    , pictonBlue
    , brightGreen
    , screaminGreen
    , mediumAquamarine
    , electricBlue
    , darkCandyAppleRed
    , jazzberryJam
    , purple
    , vividViolet
    , windsorTan
    , roseVale
    , purpureus
    , lavenderIndigo
    , limerick
    , brass
    , lightGray
    , babyBlueEyes
    , springBud
    , inchworm
    , mintGreen
    , celeste
    , red
    , folly
    , fashionMagenta
    , magenta
    , orange
    , sunsetOrange
    , brilliantRose
    , shockingPink
    , chromeYellow
    , rajah
    , melon
    , richBrilliantLavender
    , yellow
    , icterine
    , pastelYellow
    , white
    )

import Bitwise


{-| Color values used by Pebble graphics.
-}
type Color
    = Indexed Int
    | RGBA Int Int Int Int


{-| Construct a color from a packed Pebble ARGB8 value.
-}
argb8 : Int -> Color
argb8 =
    indexed


{-| Construct a color from a packed Pebble ARGB8 value.
-}
indexed : Int -> Color
indexed code =
    Indexed code


{-| Construct an opaque color from RGB channels (0..255).
-}
rgb : Int -> Int -> Int -> Color
rgb r g b =
    RGBA r g b 255


{-| Construct a color from RGBA channels (0..255).
-}
rgba : Int -> Int -> Int -> Int -> Color
rgba r g b a =
    RGBA r g b a


{-| Convert a color to packed Pebble 8-bit ARGB format.
-}
toInt : Color -> Int
toInt color =
    case color of
        Indexed code ->
            clampInt 0 255 code

        RGBA r g b a ->
            let
                rr =
                    channelTo2Bit r

                gg =
                    channelTo2Bit g

                bb =
                    channelTo2Bit b

                aa =
                    channelTo2Bit a
            in
            Bitwise.or (Bitwise.shiftLeftBy 6 aa)
                (Bitwise.or (Bitwise.shiftLeftBy 4 rr)
                    (Bitwise.or (Bitwise.shiftLeftBy 2 gg) bb)
                )


clearColor : Color
clearColor =
    indexed 0x00


black : Color
black =
    indexed 0xC0


oxfordBlue : Color
oxfordBlue =
    indexed 0xC1


dukeBlue : Color
dukeBlue =
    indexed 0xC2


blue : Color
blue =
    indexed 0xC3


darkGreen : Color
darkGreen =
    indexed 0xC4


midnightGreen : Color
midnightGreen =
    indexed 0xC5


cobaltBlue : Color
cobaltBlue =
    indexed 0xC6


blueMoon : Color
blueMoon =
    indexed 0xC7


islamicGreen : Color
islamicGreen =
    indexed 0xC8


jaegerGreen : Color
jaegerGreen =
    indexed 0xC9


tiffanyBlue : Color
tiffanyBlue =
    indexed 0xCA


vividCerulean : Color
vividCerulean =
    indexed 0xCB


green : Color
green =
    indexed 0xCC


malachite : Color
malachite =
    indexed 0xCD


mediumSpringGreen : Color
mediumSpringGreen =
    indexed 0xCE


cyan : Color
cyan =
    indexed 0xCF


bulgarianRose : Color
bulgarianRose =
    indexed 0xD0


imperialPurple : Color
imperialPurple =
    indexed 0xD1


indigo : Color
indigo =
    indexed 0xD2


electricUltramarine : Color
electricUltramarine =
    indexed 0xD3


armyGreen : Color
armyGreen =
    indexed 0xD4


darkGray : Color
darkGray =
    indexed 0xD5


liberty : Color
liberty =
    indexed 0xD6


veryLightBlue : Color
veryLightBlue =
    indexed 0xD7


kellyGreen : Color
kellyGreen =
    indexed 0xD8


mayGreen : Color
mayGreen =
    indexed 0xD9


cadetBlue : Color
cadetBlue =
    indexed 0xDA


pictonBlue : Color
pictonBlue =
    indexed 0xDB


brightGreen : Color
brightGreen =
    indexed 0xDC


screaminGreen : Color
screaminGreen =
    indexed 0xDD


mediumAquamarine : Color
mediumAquamarine =
    indexed 0xDE


electricBlue : Color
electricBlue =
    indexed 0xDF


darkCandyAppleRed : Color
darkCandyAppleRed =
    indexed 0xE0


jazzberryJam : Color
jazzberryJam =
    indexed 0xE1


purple : Color
purple =
    indexed 0xE2


vividViolet : Color
vividViolet =
    indexed 0xE3


windsorTan : Color
windsorTan =
    indexed 0xE4


roseVale : Color
roseVale =
    indexed 0xE5


purpureus : Color
purpureus =
    indexed 0xE6


lavenderIndigo : Color
lavenderIndigo =
    indexed 0xE7


limerick : Color
limerick =
    indexed 0xE8


brass : Color
brass =
    indexed 0xE9


lightGray : Color
lightGray =
    indexed 0xEA


babyBlueEyes : Color
babyBlueEyes =
    indexed 0xEB


springBud : Color
springBud =
    indexed 0xEC


inchworm : Color
inchworm =
    indexed 0xED


mintGreen : Color
mintGreen =
    indexed 0xEE


celeste : Color
celeste =
    indexed 0xEF


red : Color
red =
    indexed 0xF0


folly : Color
folly =
    indexed 0xF1


fashionMagenta : Color
fashionMagenta =
    indexed 0xF2


magenta : Color
magenta =
    indexed 0xF3


orange : Color
orange =
    indexed 0xF4


sunsetOrange : Color
sunsetOrange =
    indexed 0xF5


brilliantRose : Color
brilliantRose =
    indexed 0xF6


shockingPink : Color
shockingPink =
    indexed 0xF7


chromeYellow : Color
chromeYellow =
    indexed 0xF8


rajah : Color
rajah =
    indexed 0xF9


melon : Color
melon =
    indexed 0xFA


richBrilliantLavender : Color
richBrilliantLavender =
    indexed 0xFB


yellow : Color
yellow =
    indexed 0xFC


icterine : Color
icterine =
    indexed 0xFD


pastelYellow : Color
pastelYellow =
    indexed 0xFE


white : Color
white =
    indexed 0xFF


channelTo2Bit : Int -> Int
channelTo2Bit channel =
    (clampInt 0 255 channel * 3 + 127) // 255


clampInt : Int -> Int -> Int -> Int
clampInt low high value =
    max low (min high value)
