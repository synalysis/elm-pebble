module Elm.Kernel.Random exposing (generate)


generate : (a -> msg) -> b -> Cmd msg
generate toMsg generator =
    let
        keep =
            ( toMsg, generator )
    in
    Cmd.none
