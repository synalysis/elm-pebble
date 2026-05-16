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


type Color
    = Color Int


argb8 : Int -> Color
argb8 =
    Color


indexed : Int -> Color
indexed =
    Color


rgb : Int -> Int -> Int -> Color
rgb r g b =
    Color (r * 65536 + g * 256 + b)


rgba : Int -> Int -> Int -> Int -> Color
rgba a r g b =
    Color (a * 16777216 + r * 65536 + g * 256 + b)


toInt : Color -> Int
toInt (Color value) =
    value


clearColor : Color
clearColor =
    Color 0


black : Color
black =
    Color 1


oxfordBlue : Color
oxfordBlue =
    Color 2


dukeBlue : Color
dukeBlue =
    Color 3


blue : Color
blue =
    Color 4


darkGreen : Color
darkGreen =
    Color 5


midnightGreen : Color
midnightGreen =
    Color 6


cobaltBlue : Color
cobaltBlue =
    Color 7


blueMoon : Color
blueMoon =
    Color 8


islamicGreen : Color
islamicGreen =
    Color 9


jaegerGreen : Color
jaegerGreen =
    Color 10


tiffanyBlue : Color
tiffanyBlue =
    Color 11


vividCerulean : Color
vividCerulean =
    Color 12


green : Color
green =
    Color 13


malachite : Color
malachite =
    Color 14


mediumSpringGreen : Color
mediumSpringGreen =
    Color 15


cyan : Color
cyan =
    Color 16


bulgarianRose : Color
bulgarianRose =
    Color 17


imperialPurple : Color
imperialPurple =
    Color 18


indigo : Color
indigo =
    Color 19


electricUltramarine : Color
electricUltramarine =
    Color 20


armyGreen : Color
armyGreen =
    Color 21


darkGray : Color
darkGray =
    Color 22


liberty : Color
liberty =
    Color 23


veryLightBlue : Color
veryLightBlue =
    Color 24


kellyGreen : Color
kellyGreen =
    Color 25


mayGreen : Color
mayGreen =
    Color 26


cadetBlue : Color
cadetBlue =
    Color 27


pictonBlue : Color
pictonBlue =
    Color 28


brightGreen : Color
brightGreen =
    Color 29


screaminGreen : Color
screaminGreen =
    Color 30


mediumAquamarine : Color
mediumAquamarine =
    Color 31


electricBlue : Color
electricBlue =
    Color 32


darkCandyAppleRed : Color
darkCandyAppleRed =
    Color 33


jazzberryJam : Color
jazzberryJam =
    Color 34


purple : Color
purple =
    Color 35


vividViolet : Color
vividViolet =
    Color 36


windsorTan : Color
windsorTan =
    Color 37


roseVale : Color
roseVale =
    Color 38


purpureus : Color
purpureus =
    Color 39


lavenderIndigo : Color
lavenderIndigo =
    Color 40


limerick : Color
limerick =
    Color 41


brass : Color
brass =
    Color 42


lightGray : Color
lightGray =
    Color 43


babyBlueEyes : Color
babyBlueEyes =
    Color 44


springBud : Color
springBud =
    Color 45


inchworm : Color
inchworm =
    Color 46


mintGreen : Color
mintGreen =
    Color 47


celeste : Color
celeste =
    Color 48


red : Color
red =
    Color 49


folly : Color
folly =
    Color 50


fashionMagenta : Color
fashionMagenta =
    Color 51


magenta : Color
magenta =
    Color 52


orange : Color
orange =
    Color 53


sunsetOrange : Color
sunsetOrange =
    Color 54


brilliantRose : Color
brilliantRose =
    Color 55


shockingPink : Color
shockingPink =
    Color 56


chromeYellow : Color
chromeYellow =
    Color 57


rajah : Color
rajah =
    Color 58


melon : Color
melon =
    Color 59


richBrilliantLavender : Color
richBrilliantLavender =
    Color 60


yellow : Color
yellow =
    Color 61


icterine : Color
icterine =
    Color 62


pastelYellow : Color
pastelYellow =
    Color 63


white : Color
white =
    Color 64
