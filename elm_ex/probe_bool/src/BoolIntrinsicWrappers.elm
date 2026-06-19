module BoolIntrinsicWrappers exposing (main)


andFn : Bool -> Bool -> Bool
andFn =
    (&&)


orFn : Bool -> Bool -> Bool
orFn =
    (||)


main : Bool
main =
    let
        notDirect =
            not False

        andDirect =
            True && True

        orDirect =
            False || True

        andWrapped =
            andFn True True

        orWrapped =
            orFn False True

        caseFalse =
            case False of
                False ->
                    True

                True ->
                    False
    in
    notDirect && andDirect && orDirect && andWrapped && orWrapped && caseFalse
