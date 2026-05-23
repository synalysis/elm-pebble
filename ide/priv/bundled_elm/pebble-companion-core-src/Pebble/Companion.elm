module Pebble.Companion exposing (batch)

{-| Composition helpers for companion platform subscriptions.

@docs batch

-}

import Pebble.Companion.Platform as Platform


{-| Combine multiple companion platform listeners into one subscription.

This mirrors `Pebble.Events.batch` on the watch.

    import Pebble.Companion as Companion
    import Pebble.Companion.Battery as Battery
    import Pebble.Companion.Locale as Locale

    subscriptions _ =
        Sub.batch
            [ Companion.batch
                [ Battery.part GotBattery
                , Locale.part GotLocale
                ]
            , CompanionWatch.onPhoneToWatch FromWatch
            ]
-}
batch : List (Platform.Part msg) -> Sub msg
batch =
    Platform.batch
