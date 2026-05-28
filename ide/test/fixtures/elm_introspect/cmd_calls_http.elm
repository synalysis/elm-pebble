module CmdCallsHttp exposing (..)

import Companion.Http as Http
import Json.Decode as Decode

type Msg = Tick | WeatherReceived (Result Http.Error Float)

update msg model =
    case msg of
        Tick ->
            ( model, Http.send (Http.get { url = "https://example.com/weather", expect = Http.expectJson (Decode.field "value" Decode.float) WeatherReceived }) )

        WeatherReceived value ->
            ( model, Cmd.none )
