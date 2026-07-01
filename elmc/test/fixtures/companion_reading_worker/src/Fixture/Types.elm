module Fixture.Types exposing (PhoneToWatch(..), Scale(..))

type Scale
    = Celsius Int
    | Fahrenheit Int

type PhoneToWatch
    = GotReading Scale
