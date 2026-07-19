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
import Internal.Vec2 as WiringVec2
import Svg exposing (Svg, g)
import Svg.Attributes as SvgAttr


type alias Model =
    ()


init : () -> ( Model, Cmd () )
init _ =
    ( (), Cmd.none )


update : () -> Model -> ( Model, Cmd () )
update _ model =
    ( model, Cmd.none )


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
    Wiring.initWith 0 1 "A"


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
    WiringSvgConfig.forStringLabels
        |> WiringSvgConfig.withCellAttributesFunction wiringCellAttributes
        |> WiringSvgConfig.withCellWrappingFunction (\_ inners -> g [] inners)


wiringCellAttributes : Maybe String -> List (Svg.Attribute msg)
wiringCellAttributes maybeLabel =
    case maybeLabel of
        Just _ ->
            [ SvgAttr.fill "none", SvgAttr.stroke "#64748b", SvgAttr.strokeWidth "1" ]

        Nothing ->
            []
