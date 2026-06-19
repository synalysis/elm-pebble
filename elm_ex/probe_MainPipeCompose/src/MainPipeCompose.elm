module MainPipeCompose exposing (main)


main =
    let
        items =
            [ 1, 2, 3, 4, 5 ]

        -- Using |> and >> together like parsetopian does
        result =
            items
                |> (List.foldl (+) 0
                        >> (*) 2
                   )
    in
    result
