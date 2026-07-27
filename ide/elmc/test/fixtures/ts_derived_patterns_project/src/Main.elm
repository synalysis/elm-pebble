module Main exposing (main)

import Debug
import TsDerivedPatterns


main : String
main =
    Debug.toString
        { nestedFieldCall =
            TsDerivedPatterns.nestedFieldCall
                { child = TsDerivedPatterns.childHandler }
                { getName = String.length }
                "abc"
        , composeWithLambda = TsDerivedPatterns.composeWithLambda 120
        , qualifiedRefIdentity = TsDerivedPatterns.qualifiedRefIdentity 7
        , constructorRefJust = TsDerivedPatterns.constructorRefJust 3
        , nestedCaseCtor = TsDerivedPatterns.nestedCaseCtor (Just (TsDerivedPatterns.Custom 9))
        , unicodeLen = String.length TsDerivedPatterns.unicodeMathAlpha
        }
