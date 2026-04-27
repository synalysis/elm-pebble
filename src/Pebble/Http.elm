module Pebble.Http exposing
    ( HttpMethod(..)
    , HttpRequest
    , HttpResponse
    , HttpCmd(..)
    , get
    , post
    , put
    , delete
    , request
    , withHeader
    , withTimeout
    , withBody
    , expectString
    , expectJson
    , expectBytes
    )

{-| HTTP requests for Pebble applications to fetch external data.

# Types
@docs HttpMethod, HttpRequest, HttpResponse, HttpCmd

# Simple Requests
@docs get, post, put, delete

# Advanced Requests
@docs request, withHeader, withTimeout, withBody

# Response Handling
@docs expectString, expectJson, expectBytes

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


-- TYPES

{-| HTTP methods supported by Pebble.
-}
type HttpMethod
    = GET
    | POST
    | PUT
    | DELETE


{-| Configuration for an HTTP request.
-}
type alias HttpRequest =
    { method : HttpMethod
    , url : String
    , headers : List ( String, String )
    , body : Maybe String
    , timeout : Maybe Int
    }


{-| Response from an HTTP request.
-}
type alias HttpResponse =
    { status : Int
    , body : String
    , headers : List ( String, String )
    }


{-| Commands for HTTP operations.
-}
type HttpCmd msg
    = Request HttpRequest (Result String HttpResponse -> msg)


-- SIMPLE REQUESTS

{-| Make a GET request.

    Http.get "https://api.weather.com/current" WeatherReceived

-}
get : String -> (Result String HttpResponse -> msg) -> HttpCmd msg
get url toMsg =
    Request
        { method = GET
        , url = url
        , headers = []
        , body = Nothing
        , timeout = Nothing
        }
        toMsg


{-| Make a POST request.

    Http.post "https://api.example.com/data" PostCompleted

-}
post : String -> (Result String HttpResponse -> msg) -> HttpCmd msg
post url toMsg =
    Request
        { method = POST
        , url = url
        , headers = []
        , body = Nothing
        , timeout = Nothing
        }
        toMsg


{-| Make a PUT request.

    Http.put "https://api.example.com/update" PutCompleted

-}
put : String -> (Result String HttpResponse -> msg) -> HttpCmd msg
put url toMsg =
    Request
        { method = PUT
        , url = url
        , headers = []
        , body = Nothing
        , timeout = Nothing
        }
        toMsg


{-| Make a DELETE request.

    Http.delete "https://api.example.com/item/123" DeleteCompleted

-}
delete : String -> (Result String HttpResponse -> msg) -> HttpCmd msg
delete url toMsg =
    Request
        { method = DELETE
        , url = url
        , headers = []
        , body = Nothing
        , timeout = Nothing
        }
        toMsg


-- ADVANCED REQUESTS

{-| Create a custom HTTP request.

    request GET "https://api.example.com/data"
        |> withHeader "Authorization" "Bearer token123"
        |> withTimeout 5000
        |> withBody (Encode.object [("name", Encode.string "test")] |> Encode.encode 0)
        |> expectJson dataDecoder DataReceived

-}
request : HttpMethod -> String -> HttpRequest
request method url =
    { method = method
    , url = url
    , headers = []
    , body = Nothing
    , timeout = Nothing
    }


{-| Add a header to the request.

    request GET "https://api.example.com"
        |> withHeader "Content-Type" "application/json"

-}
withHeader : String -> String -> HttpRequest -> HttpRequest
withHeader name value req =
    { req | headers = ( name, value ) :: req.headers }


{-| Set a timeout for the request (in milliseconds).

    request GET "https://api.example.com"
        |> withTimeout 10000  -- 10 seconds

-}
withTimeout : Int -> HttpRequest -> HttpRequest
withTimeout timeout req =
    { req | timeout = Just timeout }


{-| Add a body to the request.

    request POST "https://api.example.com"
        |> withBody jsonString

-}
withBody : String -> HttpRequest -> HttpRequest
withBody body req =
    { req | body = Just body }


-- RESPONSE HANDLING

{-| Expect a string response.

    request GET "https://api.example.com/text"
        |> expectString TextReceived

-}
expectString : (Result String String -> msg) -> HttpRequest -> HttpCmd msg
expectString toMsg req =
    Request req (\result ->
        case result of
            Err error ->
                toMsg (Err error)
            
            Ok response ->
                toMsg (Ok response.body)
    )


{-| Expect a JSON response and decode it.

    type alias User = { name : String, id : Int }
    
    userDecoder : Decoder User
    userDecoder =
        Decode.map2 User
            (Decode.field "name" Decode.string)
            (Decode.field "id" Decode.int)
    
    request GET "https://api.example.com/user"
        |> expectJson userDecoder UserReceived

-}
expectJson : Decoder a -> (Result String a -> msg) -> HttpRequest -> HttpCmd msg
expectJson decoder toMsg req =
    Request req (\result ->
        case result of
            Err error ->
                toMsg (Err error)
            
            Ok response ->
                case Decode.decodeString decoder response.body of
                    Ok decoded ->
                        toMsg (Ok decoded)
                    
                    Err decodeError ->
                        toMsg (Err (Decode.errorToString decodeError))
    )


{-| Expect a binary response.

    request GET "https://api.example.com/image.png"
        |> expectBytes ImageReceived

-}
expectBytes : (Result String String -> msg) -> HttpRequest -> HttpCmd msg
expectBytes toMsg req =
    Request req (\result ->
        case result of
            Err error ->
                toMsg (Err error)
            
            Ok response ->
                toMsg (Ok response.body)
    ) 