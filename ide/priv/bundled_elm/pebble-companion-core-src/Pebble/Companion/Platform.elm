module Pebble.Companion.Platform exposing
    ( Handler
    , Interest
    , handler
    , interest
    , setup
    , subscribe
    )

{-| Companion platform subscription wiring.

Each platform API exposes a real `Sub msg` subscription. Compose them with plain
`Sub.batch` instead of a special batch combinator.

    import Pebble.Companion.Battery as Battery
    import Pebble.Companion.Locale as Locale
    import Pebble.Companion.Phone as Phone

    init _ =
        ( model, Cmd.batch [ Battery.setup, Battery.current GotBattery ] )

    subscriptions _ =
        Sub.batch
            [ Phone.onWatchToPhone FromWatch
            , Battery.onBattery GotBattery
            , Locale.onLocale GotLocale
            ]

@docs Interest, Handler, handler, interest, subscribe, setup

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Contract exposing (CommandEnvelope)
import Pebble.Companion.Phone as Phone


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
    = Handler Interest (Decode.Value -> msg)


{-| Build a platform handler from interest metadata and decoders.
-}
handler : Interest -> (Decode.Value -> Result String a) -> (Result String a -> msg) -> Handler msg
handler interest_ decode toMsg =
    Handler interest_ (\value -> toMsg (decode value))


{-| Describe a platform API bridge interest.
-}
interest :
    { id : String
    , subscribeCommand : Maybe CommandEnvelope
    , eventPrefixes : List String
    , resultIdPrefixes : List String
    }
    -> Interest
interest config =
    Interest config


{-| Register bridge interest and subscribe to the API's dedicated incoming port.

Call the matching `setup` command from `init` so the bridge can route events to
this handler.
-}
subscribe : Handler msg -> Sub msg
subscribe (Handler (Interest interest_) deliver) =
    Phone.platformIncomingFor interest_.id deliver


{-| Register bridge interest with the companion bridge.

Pair this with the matching subscription from typed platform modules such as
`Battery.onBattery` or `Calendar.onCalendar`.
-}
setup : Interest -> Cmd msg
setup (Interest interest_) =
    Cmd.batch <|
        List.filterMap identity
            [ Just (Phone.registerHandler interest_.id (encodeInterest (Interest interest_)))
            , Maybe.map Phone.sendBridgeCommand interest_.subscribeCommand
            ]


encodeInterest : Interest -> Encode.Value
encodeInterest (Interest interest_) =
    Encode.object
        [ ( "id", Encode.string interest_.id )
        , ( "eventPrefixes", Encode.list Encode.string interest_.eventPrefixes )
        , ( "resultIdPrefixes", Encode.list Encode.string interest_.resultIdPrefixes )
        ]
