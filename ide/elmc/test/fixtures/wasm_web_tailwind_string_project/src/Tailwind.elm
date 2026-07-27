module Tailwind exposing (classes, shrink_0, px, p, md, dark, text_color, gray, s3, s700)


import Html exposing (Attribute)
import Html.Attributes


type Tailwind
    = Tailwind String


type Spacing
    = S3


type Shade
    = S50
    | S100
    | S200
    | S300
    | S400
    | S500
    | S600
    | S700
    | S800
    | S900
    | S950


type Color
    = Color String


s3 : Spacing
s3 =
    S3


s700 : Shade
s700 =
    S700


spacingToString : Spacing -> String
spacingToString spacing =
    case spacing of
        S3 ->
            "3"


shadeToString : Shade -> String
shadeToString shade =
    case shade of
        S50 ->
            "50"

        S100 ->
            "100"

        S200 ->
            "200"

        S300 ->
            "300"

        S400 ->
            "400"

        S500 ->
            "500"

        S600 ->
            "600"

        S700 ->
            "700"

        S800 ->
            "800"

        S900 ->
            "900"

        S950 ->
            "950"


gray : Shade -> Color
gray shade =
    Color ("gray-" ++ shadeToString shade)


colorToString : Color -> String
colorToString (Color str) =
    str


px : Spacing -> Tailwind
px spacing =
    Tailwind ("px-" ++ spacingToString spacing)


p : Spacing -> Tailwind
p spacing =
    Tailwind ("p-" ++ spacingToString spacing)


text_color : Color -> Tailwind
text_color color =
    Tailwind ("text-" ++ colorToString color)


md : List Tailwind -> Tailwind
md twClasses =
    Tailwind (String.join " " (List.map (\(Tailwind c) -> "md:" ++ c) twClasses))


dark : List Tailwind -> Tailwind
dark twClasses =
    Tailwind (String.join " " (List.map (\(Tailwind c) -> "dark:" ++ c) twClasses))


shrink_0 =
    Tailwind "shrink-0"


toClassName (Tailwind className) =
    className


classes : List Tailwind -> Attribute msg
classes twClasses =
    Html.Attributes.class (String.join " " (List.map toClassName twClasses))
