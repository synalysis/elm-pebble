module CaseBranch5Plus exposing (main)

{-| Test for bytecode compiler bug with 5+ case branches.

Bug description: When the update function has a case expression with 5+ branches,
and one of those branches calls a helper function that itself has a nested case,
the bytecode compiler may incorrectly generate a partial closure instead of
executing the function call.

This is a different pattern from CaseBranchCallBug which has only 2 outer branches.
-}


type AppState
    = Loading
    | Ready { cursor : Int }
    | Exiting


type Msg
    = MsgA
    | MsgB
    | MsgC
    | MsgD
    | MsgE


type alias Model =
    { value : Int
    , state : AppState
    }


-- Helper function with nested case on model.state
helper : Model -> ( Model, Int )
helper model =
    case model.state of
        Ready rs ->
            ( { model | state = Ready { rs | cursor = rs.cursor + 1 } }
            , 100
            )

        _ ->
            ( model, 0 )


-- Update with 5 branches - the bug trigger
update : Msg -> Model -> ( Model, Int )
update msg model =
    case msg of
        MsgA ->
            ( { model | value = 1 }, 1 )

        MsgB ->
            ( { model | value = 2 }, 2 )

        MsgC ->
            ( { model | value = 3 }, 3 )

        MsgD ->
            ( { model | value = 4 }, 4 )

        MsgE ->
            -- This branch calls a helper function
            -- The bug might cause this to return a closure instead of a tuple
            helper model


main : Int
main =
    let
        model =
            { value = 0
            , state = Ready { cursor = 0 }
            }

        result =
            update MsgE model
    in
    -- If bug is present, this will fail because result is a closure, not a tuple
    case result of
        ( newModel, cmd ) ->
            -- Should be: cursor incremented to 1, cmd is 100
            case newModel.state of
                Ready rs ->
                    rs.cursor + cmd

                _ ->
                    -1
