module Companion.Types exposing (Color(..), Measure(..), PhoneToWatch(..), Point, WatchToPhone(..))

import Dict


{-| Companion protocol wire-type matrix.

Each constructor exercises a supported AppMessage shape. Use the
`companion-demo-protocol-matrix` template on a real watch + phone and in the
embedded emulator; every case should show PASS when delivery works end-to-end.

Supported wire shapes (both directions where noted):

  - tag-only (`Ping` / `Pong`)
  - enum (`Color`) on watch → phone via `companionSend tag value`
  - nested union (`Measure`), record alias (`Point`), `List Int` on phone → watch
  - `Bool`, `String`, `List Point`, `Dict String Int` (phone → watch via `RequestPhoneExtras`)

Watch → phone uses `companionSend tag value` (message tag + one scalar int). That
carries enum payloads and tag-only messages. Union variant tags decode without
their inner int; record/list/dict payloads cannot round-trip on that path — those
cases are expected to FAIL until multi-key watch encode exists.

Not supported as Elm tuple/`Maybe` payload types — use records or unions instead.

Emulator-only behavior (not a substitute for this matrix passing on device):

  - Simulator weather inject and pkjs weather bootstrap
  - Debugger `DeviceData` simulated time
  - HTTP interception for Open-Meteo in the IDE companion shell
-}


type Color
    = Red
    | Green
    | Blue


type Measure
    = Liters Int
    | Pounds Int


type alias Point =
    { x : Int, y : Int }


type WatchToPhone
    = Ping
    | SendColor Color
    | SendMeasure Measure
    | SendPoint Point
    | SendCounts (List Int)
    | RequestPhoneExtras


type PhoneToWatch
    = Pong
    | EchoColor Color
    | EchoMeasure Measure
    | EchoPoint Point
    | EchoCounts (List Int)
    | PushBool Bool
    | PushString String
    | PushPoints (List Point)
    | PushLabels (Dict.Dict String Int)
