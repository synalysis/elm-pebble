module RecordFieldTest exposing (main)

type alias WalkerOptions =
    { ignoreDirs : List String
    , ignoreFiles : List String
    }

type alias WalkState =
    { pending : List String
    , options : WalkerOptions
    }

type alias DiscoveryState =
    { walker : WalkState
    , foundFiles : List String
    }

start : DiscoveryState
start =
    { walker =
        { pending = ["."]
        , options = { ignoreDirs = [], ignoreFiles = [] }
        }
    , foundFiles = []
    }

processAndGetNext : DiscoveryState -> Maybe String
processAndGetNext state =
    let
        newPending =
            case state.walker.pending of
                [] -> []
                _ :: rest -> rest

        newWalker =
            { pending = newPending, options = state.walker.options }
    in
    case newWalker.pending of
        [] ->
            Nothing
        first :: _ ->
            Just first

main : String
main =
    case processAndGetNext start of
        Nothing ->
            "empty"
        Just dir ->
            dir
