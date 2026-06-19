module Main exposing (main)


main : Int
main =
    go 5


go : Int -> Int
go n =
    let
        helper acc x =
            if x <= 0 then
                acc

            else
                helper (acc + x) (x - 1)
    in
    helper 0 n
