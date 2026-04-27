module RecordPattern exposing (valueFromCase)


valueFromCase : { value : Int } -> Int
valueFromCase record =
    case record of
        { value } ->
            value
