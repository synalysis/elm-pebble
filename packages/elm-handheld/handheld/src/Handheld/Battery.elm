module Handheld.Battery exposing (level)

{-| Battery charge.

    import Handheld.Battery as Battery

    type Msg
        = Level Int

    init _ =
        ( { level = 0 }, Battery.level Level )

    update msg model =
        case msg of
            Level percent ->
                ( { model | level = percent }, Cmd.none )

The percent is `0` to `100`.

@docs level
-}

import Handheld.Raw as Raw


{-| Read the charge percent.
-}
level : (Int -> msg) -> Cmd msg
level _ =
    Raw.none
