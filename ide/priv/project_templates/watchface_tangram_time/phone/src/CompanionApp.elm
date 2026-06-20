module CompanionApp exposing (main)

import Pebble.Companion.Phone as CompanionPhone
import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Http
import Json.Decode as Decode
import Platform
import Time


type alias Model =
    { figure : Int
    , names : List String
    , rotationsSinceDownload : Int
    }


type alias RawPoint =
    { x : Float
    , y : Float
    }


type alias Matrix =
    { a : Float
    , b : Float
    , c : Float
    , d : Float
    , e : Float
    , f : Float
    }


type alias RawPiece =
    { index : Int
    , vertexCount : Int
    , points : List RawPoint
    }


type alias Piece =
    { index : Int
    , vertexCount : Int
    , points : List Point
    }


type alias Point =
    { x : Int
    , y : Int
    }


type alias Bounds =
    { minX : Float
    , maxX : Float
    , minY : Float
    , maxY : Float
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | RotateFigure Time.Posix
    | CatalogReceived (Result Http.Error String)
    | SvgReceived (Result Http.Error String)


init : Decode.Value -> ( Model, Cmd Msg )
init _ =
    ( { figure = 0, names = fallbackNames, rotationsSinceDownload = 0 }
    , Cmd.batch
        [ CompanionPhone.sendPhoneToWatch (ProvideFigure 0)
        , fetchCatalog
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestFigure) ->
            ( { model | rotationsSinceDownload = 0 }, fetchCurrentFigure model )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        RotateFigure _ ->
            let
                nextModel =
                    advanceFigure model

                rotationsSinceDownload =
                    model.rotationsSinceDownload + 1
            in
            if rotationsSinceDownload >= rotationsBetweenDownloads then
                ( { nextModel | rotationsSinceDownload = 0 }
                , fetchCurrentFigure nextModel
                )
            else
                ( { nextModel | rotationsSinceDownload = rotationsSinceDownload }
                , CompanionPhone.sendPhoneToWatch (ProvideFigure nextModel.figure)
                )

        CatalogReceived (Ok json) ->
            case catalogNames json of
                [] ->
                    ( model, Cmd.none )

                names ->
                    ( { model | figure = 0, names = names, rotationsSinceDownload = 0 }
                    , Cmd.none
                    )

        CatalogReceived (Err _) ->
            ( model, Cmd.none )

        SvgReceived (Ok svg) ->
            let
                figureId =
                    model.figure

                pieces =
                    parseSvgPieces svg
            in
            case pieces of
                [] ->
                    ( model, CompanionPhone.sendPhoneToWatch (ProvideFigure figureId) )

                _ ->
                    ( model, sendFigureGeometry figureId pieces )

        SvgReceived (Err _) ->
            ( model, CompanionPhone.sendPhoneToWatch (ProvideFigure model.figure) )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , Time.every figureRotationInterval RotateFigure
        ]


figureCount : Int
figureCount =
    6


figureRotationInterval : Float
figureRotationInterval =
    5 * 60 * 1000


rotationsBetweenDownloads : Int
rotationsBetweenDownloads =
    6


fetchCatalog : Cmd Msg
fetchCatalog =
    Http.get
        { url = "https://raw.githubusercontent.com/lil-lab/kilogram/main/dataset/dense10.json"
        , expect = Http.expectString CatalogReceived
        }


catalogNames : String -> List String
catalogNames json =
    json
        |> String.split "\""
        |> List.filter isFigureName
        |> uniqueStrings


isFigureName : String -> Bool
isFigureName value =
    String.startsWith "page" value && String.contains "-" value


uniqueStrings : List String -> List String
uniqueStrings values =
    List.foldl
        (\value seen ->
            if List.member value seen then
                seen
            else
                value :: seen
        )
        []
        values
        |> List.reverse


advanceFigure : Model -> Model
advanceFigure model =
    { model | figure = modBy (List.length model.names) (model.figure + 1) }


currentName : Model -> String
currentName model =
    model.names
        |> List.drop model.figure
        |> List.head
        |> Maybe.withDefault "page1-0"


fetchCurrentFigure : Model -> Cmd Msg
fetchCurrentFigure model =
    fetchFigure model.figure (currentName model)


fetchFigure : Int -> String -> Cmd Msg
fetchFigure _ name =
    Http.get
        { url = "https://raw.githubusercontent.com/lil-lab/kilogram/main/dataset/tangrams-svg/" ++ svgUrlName name ++ ".svg"
        , expect = Http.expectString SvgReceived
        }


svgUrlName : String -> String
svgUrlName name =
    name
        |> String.replace "-" "%2D"
        |> String.replace " " ""


sendFigureGeometry : Int -> List Piece -> Cmd Msg
sendFigureGeometry figureId pieces =
    Cmd.batch
        ([ CompanionPhone.sendPhoneToWatch (BeginFigure figureId) ]
            ++ List.map (sendPiece figureId) pieces
            ++ [ CompanionPhone.sendPhoneToWatch (EndFigure figureId) ]
        )


sendPiece : Int -> Piece -> Cmd Msg
sendPiece figureId piece =
    let
        p1 =
            pointAt 0 piece.points

        p2 =
            pointAt 1 piece.points

        p3 =
            pointAt 2 piece.points

        p4 =
            pointAt 3 piece.points
    in
    CompanionPhone.sendPhoneToWatch
        (ProvidePiece figureId
            (piece.index
                :: piece.vertexCount
                :: p1.x
                :: p1.y
                :: p2.x
                :: p2.y
                :: p3.x
                :: p3.y
                :: p4.x
                :: p4.y
                :: []
            )
        )


pointAt : Int -> List Point -> Point
pointAt index points =
    points
        |> List.drop index
        |> List.head
        |> Maybe.withDefault
            (points
                |> List.drop 2
                |> List.head
                |> Maybe.withDefault { x = 0, y = 0 }
            )


parseSvgPieces : String -> List Piece
parseSvgPieces svg =
    svg
        |> polygonSegments
        |> List.indexedMap parsePolygon
        |> List.filterMap identity
        |> normalizePieces


polygonSegments : String -> List String
polygonSegments svg =
    svg
        |> String.split "<polygon"
        |> List.drop 1
        |> List.map (\segment -> segment |> String.split "/>" |> List.head |> Maybe.withDefault segment)


parsePolygon : Int -> String -> Maybe RawPiece
parsePolygon index segment =
    case attrValue "points" segment of
        Just pointsText ->
            let
                matrix =
                    attrValue "transform" segment
                        |> Maybe.andThen parseMatrix
                        |> Maybe.withDefault identityMatrix

                points =
                    pointsText
                        |> parsePoints
                        |> List.map (applyMatrix matrix)

                vertexCount =
                    List.length points
            in
            if vertexCount >= 3 then
                Just { index = index, vertexCount = min 4 vertexCount, points = List.take 4 points }
            else
                Nothing

        Nothing ->
            Nothing


attrValue : String -> String -> Maybe String
attrValue name segment =
    case String.split (name ++ "=\"") segment |> List.drop 1 |> List.head of
        Just rest ->
            rest
                |> String.split "\""
                |> List.head

        Nothing ->
            Nothing


parsePoints : String -> List RawPoint
parsePoints pointsText =
    pointsText
        |> String.words
        |> List.filterMap parsePoint


parsePoint : String -> Maybe RawPoint
parsePoint token =
    case String.split "," token of
        xText :: yText :: _ ->
            Maybe.map2 RawPoint (parseFloat xText) (parseFloat yText)

        _ ->
            Nothing


parseMatrix : String -> Maybe Matrix
parseMatrix text =
    case String.split "matrix(" text |> List.drop 1 |> List.head of
        Just rest ->
            let
                values =
                    rest
                        |> String.split ")"
                        |> List.head
                        |> Maybe.withDefault ""
                        |> String.replace "," " "
                        |> String.words
                        |> List.filterMap parseFloat
            in
            case values of
                a :: b :: c :: d :: e :: f :: _ ->
                    Just { a = a, b = b, c = c, d = d, e = e, f = f }

                _ ->
                    Nothing

        Nothing ->
            Nothing


parseFloat : String -> Maybe Float
parseFloat text =
    let
        trimmed =
            String.trim text

        sign =
            if String.startsWith "-" trimmed then
                -1
            else
                1

        unsigned =
            trimmed
                |> String.replace "-" ""
                |> String.replace "+" ""
    in
    case String.split "." unsigned of
        wholeText :: fractionText :: _ ->
            Maybe.map2
                (\whole fraction ->
                    toFloat sign * (toFloat whole + (toFloat fraction / toFloat (pow10 (String.length fractionText))))
                )
                (String.toInt (blankAsZero wholeText))
                (String.toInt (blankAsZero fractionText))

        wholeText :: [] ->
            String.toInt wholeText
                |> Maybe.map (\whole -> toFloat (sign * whole))

        _ ->
            Nothing


blankAsZero : String -> String
blankAsZero text =
    if text == "" then
        "0"
    else
        text


pow10 : Int -> Int
pow10 exponent =
    if exponent <= 0 then
        1
    else
        10 * pow10 (exponent - 1)


identityMatrix : Matrix
identityMatrix =
    { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }


applyMatrix : Matrix -> RawPoint -> RawPoint
applyMatrix matrix point =
    { x = matrix.a * point.x + matrix.c * point.y + matrix.e
    , y = matrix.b * point.x + matrix.d * point.y + matrix.f
    }


normalizePieces : List RawPiece -> List Piece
normalizePieces pieces =
    let
        allPoints =
            List.concatMap .points pieces

        bounds =
            pointsBounds allPoints

        width =
            max 1 (bounds.maxX - bounds.minX)

        height =
            max 1 (bounds.maxY - bounds.minY)

        scale =
            min (86 / width) (76 / height)

        centerX =
            (bounds.minX + bounds.maxX) / 2

        centerY =
            (bounds.minY + bounds.maxY) / 2
    in
    List.map
        (\piece ->
            { index = piece.index
            , vertexCount = piece.vertexCount
            , points = List.map (normalizePoint centerX centerY scale) piece.points
            }
        )
        pieces


pointsBounds : List RawPoint -> Bounds
pointsBounds points =
    case points of
        first :: rest ->
            List.foldl
                (\point bounds ->
                    { minX = min point.x bounds.minX
                    , maxX = max point.x bounds.maxX
                    , minY = min point.y bounds.minY
                    , maxY = max point.y bounds.maxY
                    }
                )
                { minX = first.x, maxX = first.x, minY = first.y, maxY = first.y }
                rest

        [] ->
            { minX = -1, maxX = 1, minY = -1, maxY = 1 }


normalizePoint : Float -> Float -> Float -> RawPoint -> Point
normalizePoint centerX centerY scale point =
    { x = round ((point.x - centerX) * scale)
    , y = round ((point.y - centerY) * scale)
    }


figureSeed : String -> Int
figureSeed name =
    stableHash name
        |> modBy 4096


stableHash : String -> Int
stableHash text =
    text
        |> String.toList
        |> List.foldl (\char total -> modBy 65521 ((total * 33) + Char.toCode char)) 5381


fallbackNames : List String
fallbackNames =
    [ "page1-0"
    , "page1-105"
    , "page1-116"
    , "page2-112"
    , "page3-121"
    , "page4-10"
    ]


main : Program Decode.Value Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
