module OperatorForms exposing
    ( applyLeft
    , composeLeft
    , composeRight
    , prependOne
    )

applyLeft : (Int -> Int) -> Int -> Int
applyLeft fn value =
    fn <| value

composeLeft : (Int -> Int) -> (Int -> Int) -> Int -> Int
composeLeft f g value =
    (f << g) value

composeRight : (Int -> Int) -> (Int -> Int) -> Int -> Int
composeRight f g value =
    (f >> g) value

prependOne : List Int -> List Int
prependOne values =
    1 :: values
