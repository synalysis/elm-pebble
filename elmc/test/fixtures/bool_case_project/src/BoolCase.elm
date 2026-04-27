module BoolCase exposing (fromFlag)


fromFlag : Bool -> Int
fromFlag flag =
    case flag of
        True ->
            1

        False ->
            0
