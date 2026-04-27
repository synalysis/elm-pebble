port module Engine exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Platform


port incoming : (Decode.Value -> msg) -> Sub msg


port outgoing : Encode.Value -> Cmd msg


type alias Model =
    Int


type Msg
    = Received Decode.Value


init : () -> ( Model, Cmd Msg )
init _ =
    ( 0, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Received payload ->
            case Decode.decodeValue (Decode.field "type" Decode.string) payload of
                Ok "tick" ->
                    let
                        nextCount =
                            model + 1
                    in
                    ( nextCount
                    , outgoing
                        (Encode.object
                            [ ( "event", Encode.string "tickAck" )
                            , ( "count", Encode.int nextCount )
                            ]
                        )
                    )

                _ ->
                    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    incoming Received


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
