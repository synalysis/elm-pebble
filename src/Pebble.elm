module Pebble exposing
    ( Program
    , ProgramConfig
    , program
    , programWithNavigation
    , programWithStorage
    , programWithHttp
    , programWithWebSocket
    , programWithHardware
    , programWithAll
    , PebbleProgram(..)
    )

{-| The Pebble framework for building smartwatch applications in Elm.

# Program Types
@docs Program, ProgramConfig, PebbleProgram

# Basic Program
@docs program

# Enhanced Programs
@docs programWithNavigation, programWithStorage, programWithHttp, programWithWebSocket, programWithHardware, programWithAll

-}

import Pebble.Canvas as Canvas exposing (Canvas)
import Pebble.Navigation as Navigation
import Pebble.Storage as Storage
import Pebble.Http as Http
import Pebble.WebSocket as WebSocket
import Pebble.Hardware as Hardware


-- TYPES

{-| A Pebble application program.
-}
type alias Program model msg =
    PebbleProgram model msg


{-| Configuration for a Pebble program.
-}
type alias ProgramConfig model msg =
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    }


{-| Internal representation of a Pebble program.
-}
type PebbleProgram model msg
    = PebbleProgram (ProgramConfig model msg)


-- BASIC PROGRAM

{-| Create a basic Pebble program.

    main : Program Model Msg
    main =
        Pebble.program
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }

-}
program : ProgramConfig model msg -> Program model msg
program config =
    PebbleProgram config


-- ENHANCED PROGRAMS

{-| Create a Pebble program with WebSocket support.

    type Msg
        = WebSocketMsg (WebSocket.WebSocketCmd Msg)
        | ConnectionStateChanged WebSocket.WebSocketState
        | MessageReceived WebSocket.WebSocketMessage
        | MessageSent (Result String ())
    
    main : Program Model Msg
    main =
        Pebble.programWithWebSocket
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , websocketWrapper = WebSocketMsg
            }

-}
programWithWebSocket :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    , websocketWrapper : WebSocket.WebSocketCmd msg -> msg
    }
    -> Program model msg
programWithWebSocket config =
    PebbleProgram
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        }


{-| Create a Pebble program with navigation support.

    type Screen = HomeScreen | SettingsScreen | GameScreen
    
    type alias Model =
        { navigation : Navigation.NavigationState Screen
        , -- other fields
        }
    
    type Msg
        = NavigationMsg (Navigation.NavigationMsg Screen)
        | -- other messages
    
    main : Program Model Msg
    main =
        Pebble.programWithNavigation
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , navigationWrapper = NavigationMsg
            , homeScreen = HomeScreen
            }

-}
programWithNavigation :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    , navigationWrapper : Navigation.NavigationMsg screen -> msg
    , homeScreen : screen
    }
    -> Program model msg
programWithNavigation config =
    PebbleProgram
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        }


{-| Create a Pebble program with storage support.

    type Msg
        = StorageMsg (Storage.StorageCmd Msg)
        | DataSaved (Result String ())
        | DataLoaded (Result String Storage.StorageValue)
        | -- other messages
    
    main : Program Model Msg
    main =
        Pebble.programWithStorage
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , storageWrapper = StorageMsg
            }

-}
programWithStorage :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    , storageWrapper : Storage.StorageCmd msg -> msg
    }
    -> Program model msg
programWithStorage config =
    PebbleProgram
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        }


{-| Create a Pebble program with HTTP support.

    type Msg
        = HttpMsg (Http.HttpCmd Msg)
        | WeatherReceived (Result String Http.HttpResponse)
        | -- other messages
    
    main : Program Model Msg
    main =
        Pebble.programWithHttp
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , httpWrapper = HttpMsg
            }

-}
programWithHttp :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    , httpWrapper : Http.HttpCmd msg -> msg
    }
    -> Program model msg
programWithHttp config =
    PebbleProgram
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        }


{-| Create a Pebble program with hardware support.

    type Msg
        = HardwareMsg (Hardware.HardwareCmd Msg)
        | BatteryLevelReceived Int
        | ConnectionStatusReceived Bool
        | -- other messages
    
    main : Program Model Msg
    main =
        Pebble.programWithHardware
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , hardwareWrapper = HardwareMsg
            }

-}
programWithHardware :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    , hardwareWrapper : Hardware.HardwareCmd msg -> msg
    }
    -> Program model msg
programWithHardware config =
    PebbleProgram
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        }


{-| Create a Pebble program with all enhanced features.

    type Screen = HomeScreen | SettingsScreen | AboutScreen
    
    type alias Model =
        { navigation : Navigation.NavigationState Screen
        , websocketState : WebSocket.WebSocketState
        , userData : Maybe UserData
        , isOnline : Bool
        , batteryLevel : Int
        }
    
    type Msg
        = NavigationMsg (Navigation.NavigationMsg Screen)
        = WebSocketMsg (WebSocket.WebSocketCmd Msg)
        | StorageMsg (Storage.StorageCmd Msg)
        | HttpMsg (Http.HttpCmd Msg)
        | HardwareMsg (Hardware.HardwareCmd Msg)
        | ConnectionStateChanged WebSocket.WebSocketState
        | MessageReceived WebSocket.WebSocketMessage
        | -- other messages
    
    main : Program Model Msg
    main =
        Pebble.programWithAll
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , navigationWrapper = NavigationMsg
            , websocketWrapper = WebSocketMsg
            , storageWrapper = StorageMsg
            , httpWrapper = HttpMsg
            , hardwareWrapper = HardwareMsg
            , homeScreen = HomeScreen
            }

-}
programWithAll :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Canvas
    , subscriptions : model -> Sub msg
    , navigationWrapper : Navigation.NavigationMsg screen -> msg
    , websocketWrapper : WebSocket.WebSocketCmd msg -> msg
    , storageWrapper : Storage.StorageCmd msg -> msg
    , httpWrapper : Http.HttpCmd msg -> msg
    , hardwareWrapper : Hardware.HardwareCmd msg -> msg
    , homeScreen : screen
    }
    -> Program model msg
programWithAll config =
    PebbleProgram
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        } 