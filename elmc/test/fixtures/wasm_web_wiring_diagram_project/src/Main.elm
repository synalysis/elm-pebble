module Main exposing (main)

import Browser
import Cartesian as Wiring exposing (C)
import Cartesian.Layout as WiringLayout
import Cartesian.Layout.Svg as WiringLayoutSvg
import Diagram.Layout.Config as WiringLayoutConfig
import Diagram.Svg as WiringSvg
import Diagram.Svg.Config as WiringSvgConfig
import Html exposing (Html, div)
import Internal.Bound as WiringBound
import Internal.Extent as WiringExtent
import Diagram.Vec2 as WiringVec2
import Svg exposing (Svg)
import Svg.Attributes as SvgAttr


type alias Model =
    ()


init : Model
init =
    ()


update : () -> Model -> Model
update _ model =
    model


main : Program () Model ()
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


view : Model -> Html ()
view _ =
    div [] [ wiringDiagramView teaWiring ]


wiringDiagramView : C String -> Html.Html msg
wiringDiagramView diagram =
    let
        layout =
            WiringLayout.toLayoutWithConfig wiringLayoutConfig diagram
    in
    WiringSvg.view
        (WiringLayoutSvg.viewportFor layout)
        [ WiringLayoutSvg.toSvgWith wiringSvgConfig layout ]


teaWiring : C String
teaWiring =
    (Wiring.initWith 0 1 "Events"
        |> Wiring.aside (Wiring.initWith 0 1 "Sub")
    )
        |> Wiring.before (Wiring.initWith 2 1 "Msg")
        |> Wiring.before (Wiring.initWith 1 2 "Update")
        |> Wiring.before
            ((Wiring.init "Model"
                |> Wiring.before (Wiring.init "View")
                |> Wiring.before (Wiring.initWith 1 0 "Pebble UI")
             )
                |> Wiring.aside (Wiring.initWith 1 0 "Cmd")
            )


wiringLayoutConfig : WiringLayoutConfig.Config String
wiringLayoutConfig =
    WiringLayoutConfig.default
        |> WiringLayoutConfig.setSpacing (WiringVec2.init 34 24)
        |> WiringLayoutConfig.setLeafExtent wiringBoxBound


wiringBoxBound : String -> WiringBound.Bound
wiringBoxBound label =
    let
        width =
            if String.length label > 16 then
                112

            else if String.length label > 10 then
                92

            else
                72

        height =
            if String.length label > 16 then
                56

            else
                38
    in
    WiringBound.init <|
        WiringExtent.init
            (WiringVec2.init 0 0)
            (WiringVec2.init width height)


wiringSvgConfig : WiringSvgConfig.Config String msg
wiringSvgConfig =
    -- Default wrap is `always <| Svg.g []` (arity-1 returning arity-1). WASM
    -- must oversaturate/curry when applying label then children — same as Index.
    WiringSvgConfig.forStringLabels
        |> WiringSvgConfig.withCellAttributesFunction wiringCellAttributes
        |> WiringSvgConfig.withTextAttributes
            [ SvgAttr.fill "#0f172a"
            , SvgAttr.stroke "none"
            , SvgAttr.fontSize "12px"
            , SvgAttr.fontWeight "700"
            ]


wiringCellAttributes : Maybe String -> List (Svg.Attribute msg)
wiringCellAttributes maybeLabel =
    case maybeLabel of
        Just label ->
            if List.member label [ "Events", "Sub", "Cmd", "Pebble UI", "Watch", "Emulator", "Phone" ] then
                [ SvgAttr.fill "#eff6ff"
                , SvgAttr.fillOpacity "1"
                , SvgAttr.stroke "#2563eb"
                , SvgAttr.strokeWidth "1.5"
                ]

            else
                [ SvgAttr.fill "#ecfdf5"
                , SvgAttr.fillOpacity "1"
                , SvgAttr.stroke "#059669"
                , SvgAttr.strokeWidth "1.5"
                ]

        Nothing ->
            [ SvgAttr.fill "none"
            , SvgAttr.stroke "none"
            ]
