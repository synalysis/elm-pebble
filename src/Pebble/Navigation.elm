module Pebble.Navigation exposing
    ( Screen
    , NavigationState
    , NavigationMsg(..)
    , init
    , update
    , currentScreen
    , push
    , pop
    , replace
    , canGoBack
    , stackDepth
    )

{-| Navigation system for multi-screen Pebble applications.

# Types
@docs Screen, NavigationState, NavigationMsg

# Initialize
@docs init

# Update
@docs update

# Query
@docs currentScreen, canGoBack, stackDepth

# Navigate
@docs push, pop, replace

-}


-- TYPES

{-| Represents a screen in your application. Use a custom type to define your screens:

    type MyScreen = HomeScreen | SettingsScreen | GameScreen

-}
type alias Screen screen =
    screen


{-| Internal navigation state tracking the screen stack.
-}
type NavigationState screen
    = NavigationState
        { stack : List screen
        , current : screen
        }


{-| Navigation messages that can be handled by your update function.
-}
type NavigationMsg screen
    = Push screen
    | Pop
    | Replace screen
    | GoBack
    | GoHome screen


-- INITIALIZE

{-| Initialize navigation with a home screen.

    init HomeScreen

-}
init : screen -> NavigationState screen
init homeScreen =
    NavigationState
        { stack = []
        , current = homeScreen
        }


-- UPDATE

{-| Update navigation state based on navigation messages.

    case msg of
        NavigationMsg navMsg ->
            let
                ( newNavState, navCmd ) = 
                    Navigation.update navMsg model.navigation
            in
            ( { model | navigation = newNavState }
            , Cmd.map NavigationMsg navCmd
            )

-}
update : NavigationMsg screen -> NavigationState screen -> ( NavigationState screen, Cmd (NavigationMsg screen) )
update msg (NavigationState state) =
    case msg of
        Push screen ->
            ( NavigationState
                { stack = state.current :: state.stack
                , current = screen
                }
            , Cmd.none
            )
        
        Pop ->
            case state.stack of
                [] ->
                    ( NavigationState state, Cmd.none )
                
                previous :: rest ->
                    ( NavigationState
                        { stack = rest
                        , current = previous
                        }
                    , Cmd.none
                    )
        
        Replace screen ->
            ( NavigationState
                { stack = state.stack
                , current = screen
                }
            , Cmd.none
            )
        
        GoBack ->
            update Pop (NavigationState state)
        
        GoHome homeScreen ->
            ( NavigationState
                { stack = []
                , current = homeScreen
                }
            , Cmd.none
            )


-- QUERY

{-| Get the current screen.

    currentScreen model.navigation == HomeScreen

-}
currentScreen : NavigationState screen -> screen
currentScreen (NavigationState state) =
    state.current


{-| Check if there are screens to go back to.

    if canGoBack model.navigation then
        -- Show back button
    else
        -- Hide back button

-}
canGoBack : NavigationState screen -> Bool
canGoBack (NavigationState state) =
    not (List.isEmpty state.stack)


{-| Get the depth of the navigation stack.

    stackDepth model.navigation == 0  -- On home screen
    stackDepth model.navigation == 2  -- Two screens deep

-}
stackDepth : NavigationState screen -> Int
stackDepth (NavigationState state) =
    List.length state.stack


-- NAVIGATE

{-| Push a new screen onto the stack.

    Navigation.push SettingsScreen model.navigation

-}
push : screen -> NavigationState screen -> NavigationState screen
push screen (NavigationState state) =
    NavigationState
        { stack = state.current :: state.stack
        , current = screen
        }


{-| Pop the current screen, returning to the previous one.

    Navigation.pop model.navigation

-}
pop : NavigationState screen -> NavigationState screen
pop (NavigationState state) =
    case state.stack of
        [] ->
            NavigationState state
        
        previous :: rest ->
            NavigationState
                { stack = rest
                , current = previous
                }


{-| Replace the current screen without affecting the stack.

    Navigation.replace GameOverScreen model.navigation

-}
replace : screen -> NavigationState screen -> NavigationState screen
replace screen (NavigationState state) =
    NavigationState
        { stack = state.stack
        , current = screen
        } 