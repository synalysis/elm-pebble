module Main exposing (Person, mkPerson, personDecoder)

import Json.Decode as Decode exposing (Decoder)


type alias Person =
    { name : String
    , age : Int
    }


mkPerson : String -> Int -> Person
mkPerson =
    Person


personDecoder : Decoder Person
personDecoder =
    Decode.map2 Person
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)

