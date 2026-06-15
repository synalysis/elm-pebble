module RcTrackResultProbe exposing
    ( probeAndThen
    , probeFromMaybe
    , probeMap
    , probeMapError
    , probeToMaybe
    , probeWithDefault
    )

import Maybe
import Result


okFour : Result String Int
okFour =
    Ok 4


probeMap : Int
probeMap =
    Result.withDefault 0 (Result.map (\x -> x + 1) okFour)


probeMapError : Int
probeMapError =
    Result.withDefault 0 (Result.mapError (\e -> e ++ "!") (Err "x"))


probeAndThen : Int
probeAndThen =
    Result.withDefault 0 (Result.andThen (\x -> Ok (x * 2)) okFour)


probeWithDefault : Int
probeWithDefault =
    Result.withDefault 0 okFour


probeToMaybe : Int
probeToMaybe =
    Maybe.withDefault 0 (Result.toMaybe okFour)


probeFromMaybe : Int
probeFromMaybe =
    Result.withDefault 0 (Result.fromMaybe "err" (Just 4))
