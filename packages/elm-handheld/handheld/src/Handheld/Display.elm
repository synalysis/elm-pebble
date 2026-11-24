module Handheld.Display exposing
    ( Metrics
    , metrics
    )

{-| A fresh reading of the panel.

`init` already receives width, height, and color depth on
`context.screen`. Call `metrics` when the app needs to read them again.

    import Handheld.Display as Display

    type Msg
        = Panel Display.Metrics

    refresh =
        Display.metrics Panel

@docs Metrics, metrics
-}

import Handheld.Raw as Raw


{-| Width, height, and bits per pixel. Depth `1` is mono. Depth `16` is color.
-}
type alias Metrics =
    { width : Int
    , height : Int
    , colorDepth : Int
    }


{-| Read the panel again. The message receives the new metrics.
-}
metrics : (Metrics -> msg) -> Cmd msg
metrics _ =
    Raw.none
