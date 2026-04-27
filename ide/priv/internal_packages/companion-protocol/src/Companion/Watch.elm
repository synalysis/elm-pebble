module Companion.Watch exposing (onPhoneToWatch, sendWatchToPhone)

{-| Watch-side API for typed companion messages.

    import Companion.Types exposing (Location(..), PhoneToWatch(..), WatchToPhone(..))
    import Companion.Watch

    requestWeather : Cmd msg
    requestWeather =
        Companion.Watch.sendWatchToPhone (RequestWeather Berlin)

# Subscriptions
@docs onPhoneToWatch

# Commands
@docs sendWatchToPhone

-}

import Companion.Internal as Internal
import Companion.Types exposing (PhoneToWatch, WatchToPhone)
import Pebble.Internal.Companion as Companion


{-| Subscribe to typed phone-to-watch messages.

The native Pebble runtime delivers these messages through AppMessage.
-}
onPhoneToWatch : (PhoneToWatch -> msg) -> Sub msg
onPhoneToWatch _ =
    Sub.none


{-| Send a typed watch-to-phone message using Pebble app messaging.
-}
sendWatchToPhone : WatchToPhone -> Cmd msg
sendWatchToPhone message =
    Companion.companionSend
        (Internal.watchToPhoneTag message)
        (Internal.watchToPhoneValue message)
