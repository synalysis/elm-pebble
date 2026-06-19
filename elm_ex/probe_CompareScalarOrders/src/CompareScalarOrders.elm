module CompareScalarOrders exposing (main)


main =
    String.join " "
        [ Debug.toString (compare 1 2)
        , Debug.toString (compare 2 2)
        , Debug.toString (compare 3 2)
        , Debug.toString (compare 1.5 2.5)
        , Debug.toString (compare 2.5 2.5)
        , Debug.toString (compare 3.5 2.5)
        , Debug.toString (compare "a" "b")
        , Debug.toString (compare "b" "b")
        , Debug.toString (compare "c" "b")
        , Debug.toString (compare 'a' 'b')
        , Debug.toString (compare 'b' 'b')
        , Debug.toString (compare 'c' 'b')
        ]
