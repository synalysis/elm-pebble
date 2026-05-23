module Pebble.Companion.Platform exposing
    ( Part
    , batch
    , with
    )

{-| Combine companion platform listeners into one subscription.

Use `Pebble.Companion.batch` or the `part` helpers from typed platform modules
such as `Pebble.Companion.Battery`.

    import Pebble.Companion as Companion
    import Pebble.Companion.Battery as Battery
    import Pebble.Companion.Locale as Locale

    subscriptions _ =
        Sub.batch
            [ Companion.batch
                [ Battery.part GotBattery
                , Locale.part GotLocale
                ]
            , Phone.onWatchToPhone FromWatch
            ]

Single-stream apps can keep using `Battery.onBattery GotBattery`.

# Composition

@docs Part, batch, with

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Contract exposing (CommandEnvelope)
import Pebble.Companion.Phone as Phone
import Sub


type Interest
    = Interest
        { id : String
        , subscribeCommand : Maybe CommandEnvelope
        , eventPrefixes : List String
        , resultIdPrefixes : List String
        }


type Handler msg
    = Handler Interest (Decode.Value -> Result String msg)


{-| A platform listener that can be combined with `batch` or `with`.
-}
type Part msg
    = Part (Handler msg)


handler : Interest -> (Decode.Value -> Result String a) -> (a -> msg) -> Handler msg
handler interest decode toMsg =
    Handler interest (decode >> Result.map toMsg)


part : Handler msg -> Part msg
part =
    Part


interest :
    { id : String
    , subscribeCommand : Maybe CommandEnvelope
    , eventPrefixes : List String
    , resultIdPrefixes : List String
    }
    -> Interest
interest =
    Interest


attach : Handler msg -> Sub msg
attach (Handler (Interest interest_) _) =
    Sub.batch <|
        List.filterMap identity
            [ Maybe.map Phone.subscribeBridge interest_.subscribeCommand
            , Just (Phone.registerHandler interest_.id (encodeInterest (Interest interest_)))
            ]


subscriptions : List (Handler msg) -> Sub msg
subscriptions handlers =
    with handlers


{-| Combine multiple platform listeners into one subscription.
-}
batch : List (Part msg) -> Sub msg
batch parts =
    with (List.map (\(Part handler_) -> handler_) parts)


{-| Combine multiple platform handlers into one subscription.
-}
with : List (Handler msg) -> Sub msg
with handlers =
    if List.isEmpty handlers then
        Sub.none

    else
        Sub.batch <|
            incoming (route handlers)
                :: List.map attach handlers


incoming : (Decode.Value -> msg) -> Sub msg
incoming =
    Phone.platformIncoming


encodeInterest : Interest -> Encode.Value
encodeInterest (Interest interest_) =
    Encode.object
        [ ( "id", Encode.string interest_.id )
        , ( "eventPrefixes", Encode.list Encode.string interest_.eventPrefixes )
        , ( "resultIdPrefixes", Encode.list Encode.string interest_.resultIdPrefixes )
        ]


route : List (Handler msg) -> Decode.Value -> msg
route handlers raw =
    case List.filterMap (tryHandler raw) handlers of
        msg :: _ ->
            msg

        [] ->
            Debug.todo "Unhandled companion platform message"


tryHandler : Decode.Value -> Handler msg -> Maybe msg
tryHandler raw (Handler interest_ decode) =
    if matches interest_ raw then
        decode raw
            |> Result.toMaybe

    else
        Nothing


matches : Interest -> Decode.Value -> Bool
matches (Interest interest_) raw =
    case Decode.decodeValue Codec.decodeEvent raw of
        Ok event ->
            List.any (\prefix -> String.startsWith prefix event.event) interest_.eventPrefixes

        Err _ ->
            case Decode.decodeValue Codec.decodeResult raw of
                Ok envelope ->
                    List.any (\prefix -> String.startsWith prefix envelope.id) interest_.resultIdPrefixes

                Err _ ->
                    case decodeRoutedEnvelope raw of
                        Just ( routedId, envelope ) ->
                            List.any (\prefix -> String.startsWith prefix routedId) interest_.resultIdPrefixes
                                || List.any
                                    (\prefix ->
                                        case Decode.decodeValue Codec.decodeEvent envelope of
                                            Ok event ->
                                                String.startsWith prefix event.event

                                            Err _ ->
                                                False
                                    )
                                    interest_.eventPrefixes

                        Nothing ->
                            False


decodeRoutedEnvelope : Decode.Value -> Maybe ( String, Decode.Value )
decodeRoutedEnvelope raw =
    Decode.decodeValue
        (Decode.map2 Tuple.pair
            (Decode.field "handlerId" Decode.string)
            (Decode.field "envelope" Decode.value)
        )
        raw
        |> Result.toMaybe
