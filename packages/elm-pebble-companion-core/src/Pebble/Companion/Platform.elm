module Pebble.Companion.Platform exposing
    ( Handler
    , Interest
    , attach
    , handler
    , interest
    , subscribe
    )

{-| Companion platform subscription wiring.

Each platform API exposes a real `Sub msg` subscription. Compose them with plain
`Sub.batch` instead of a special batch combinator.

    import Pebble.Companion.Battery as Battery
    import Pebble.Companion.Locale as Locale
    import Pebble.Companion.Phone as Phone

    subscriptions _ =
        Sub.batch
            [ Phone.onWatchToPhone FromWatch
            , Battery.onBattery GotBattery
            , Locale.onLocale GotLocale
            ]

@docs Interest, Handler, handler, interest, subscribe, attach

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Contract exposing (CommandEnvelope)
import Pebble.Companion.Phone as Phone
import Sub


{-| Bridge interest metadata for a platform API incoming stream.
-}
type Interest
    = Interest
        { id : String
        , subscribeCommand : Maybe CommandEnvelope
        , eventPrefixes : List String
        , resultIdPrefixes : List String
        }


{-| Incoming platform event handler for a dedicated port subscription.
-}
type Handler msg
    = Handler Interest (Decode.Value -> Result String msg)


{-| Build a platform handler from interest metadata and decoders.
-}
handler : Interest -> (Decode.Value -> Result String a) -> (a -> msg) -> Handler msg
handler interest decode toMsg =
    Handler interest (decode >> Result.map toMsg)


{-| Describe a platform API bridge interest.
-}
interest :
    { id : String
    , subscribeCommand : Maybe CommandEnvelope
    , eventPrefixes : List String
    , resultIdPrefixes : List String
    }
    -> Interest
interest =
    Interest


{-| Register bridge interest and subscribe to the API's dedicated incoming port.
-}
subscribe : Handler msg -> Sub msg
subscribe (Handler (Interest interest_) decode) =
    Sub.batch
        [ Phone.platformIncomingFor interest_.id (decodeIncoming decode)
        , attach (Handler (Interest interest_) decode)
        ]


{-| Register bridge interest without subscribing to incoming events.
-}
attach : Handler msg -> Sub msg
attach (Handler (Interest interest_) _) =
    Sub.batch <|
        List.filterMap identity
            [ Maybe.map Phone.subscribeBridge interest_.subscribeCommand
            , Just (Phone.registerHandler interest_.id (encodeInterest (Interest interest_)))
            ]


encodeInterest : Interest -> Encode.Value
encodeInterest (Interest interest_) =
    Encode.object
        [ ( "id", Encode.string interest_.id )
        , ( "eventPrefixes", Encode.list Encode.string interest_.eventPrefixes )
        , ( "resultIdPrefixes", Encode.list Encode.string interest_.resultIdPrefixes )
        ]


decodeIncoming : (Decode.Value -> Result String msg) -> Decode.Value -> msg
decodeIncoming decode raw =
    case decode raw of
        Ok msg ->
            msg

        Err _ ->
            Debug.todo "Unexpected platform payload on dedicated incoming port"
