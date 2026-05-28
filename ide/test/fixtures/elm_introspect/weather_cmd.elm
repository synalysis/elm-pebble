module WeatherCmd exposing (..)

import Companion.Phone as CompanionPhone
import Companion.Types exposing (PhoneToWatch(..), Temperature(..), WeatherCondition(..))

type alias WeatherReport = { temperature : Float, condition : WeatherCondition }

type Msg = WeatherReceived (Result String WeatherReport)

update msg model =
    case msg of
        WeatherReceived (Ok weather) ->
            ( model, Cmd.batch [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius (round weather.temperature))), CompanionPhone.sendPhoneToWatch (ProvideCondition weather.condition) ] )

        WeatherReceived _ ->
            ( model, Cmd.none )
