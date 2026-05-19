module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Shared messages for the Elm Tangram Time watchface.

Downloaded figures are streamed as one message per tangram piece so AppMessage
payloads stay compact and the watch can assemble a complete figure safely.
-}


type WatchToPhone
    = RequestFigure


type PhoneToWatch
    = ProvideFigure Int
    | BeginFigure Int
    | ProvidePiece Int Int Int Int Int Int Int Int Int Int Int
    | EndFigure Int
