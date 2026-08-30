module Main exposing (main)

import Char
import Html exposing (Html, text)
import Parser exposing ((|.), (|=))
import Set


hex : Parser.Parser Int
hex =
    Parser.number
        { int = Nothing
        , hex = Just identity
        , octal = Nothing
        , binary = Nothing
        , float = Nothing
        }


spacedInt : Parser.Parser Int
spacedInt =
    Parser.succeed identity
        |. Parser.spaces
        |= Parser.int


ints : Parser.Trailing -> Parser.Parser (List Int)
ints trailing =
    Parser.sequence
        { start = "["
        , separator = ","
        , end = "]"
        , spaces = Parser.spaces
        , item = Parser.int
        , trailing = trailing
        }


typeVar : Parser.Parser String
typeVar =
    Parser.variable
        { start = Char.isLower
        , inner = \c -> Char.isAlphaNum c || c == '_'
        , reserved = Set.fromList [ "let", "in", "case", "of" ]
        }


digits : Parser.Parser (List Int)
digits =
    Parser.loop [] digitsHelp


digitsHelp : List Int -> Parser.Parser (Parser.Step (List Int) (List Int))
digitsHelp rev =
    Parser.oneOf
        [ Parser.succeed (\n -> Parser.Loop (n :: rev))
            |= Parser.int
            |. Parser.spaces
        , Parser.succeed ()
            |> Parser.map (\_ -> Parser.Done (List.reverse rev))
        ]


commentThenInt : Parser.Parser Int
commentThenInt =
    Parser.succeed identity
        |. Parser.lineComment "--"
        |. Parser.spaces
        |= Parser.int


nestedComment : Parser.Parser Int
nestedComment =
    Parser.succeed identity
        |. Parser.multiComment "{-" "-}" Parser.Nestable
        |= Parser.int


jsComment : Parser.Parser Int
jsComment =
    Parser.succeed identity
        |. Parser.multiComment "/*" "*/" Parser.NotNestable
        |= Parser.int


digitsInt : Parser.Parser Int
digitsInt =
    Parser.getChompedString (Parser.chompWhile Char.isDigit)
        |> Parser.andThen
            (\str ->
                case String.toInt str of
                    Just n ->
                        Parser.succeed n

                    Nothing ->
                        Parser.problem "expecting int"
            )


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


main : Html String
main =
    text
        (String.join "|"
            [ "int:" ++ flag (Parser.run Parser.int "42" == Ok 42)
            , "float:" ++ flag (Parser.run Parser.float "3.5" == Ok 3.5)
            , "hex:" ++ flag (Parser.run hex "0x2A" == Ok 42)
            , "until:" ++ flag (Parser.run (Parser.getChompedString (Parser.chompUntil "ab")) "xxab" == Ok "xx")
            , "sym:" ++ flag (Parser.run (Parser.symbol "[") "[" == Ok ())
            , "kw:" ++ flag (Parser.run (Parser.keyword "let") "let" == Ok ())
            , "sp:" ++ flag (Parser.run spacedInt "  9" == Ok 9)
            , "seq:" ++ flag (Parser.run (ints Parser.Forbidden) "[1,2,3]" == Ok [ 1, 2, 3 ])
            , "seqf:" ++ flag (Result.toMaybe (Parser.run (ints Parser.Forbidden) "[1,2,3,]") == Nothing)
            , "seqo:" ++ flag (Parser.run (ints Parser.Optional) "[1,2,3,]" == Ok [ 1, 2, 3 ])
            , "seqe:" ++ flag (Parser.run (ints Parser.Forbidden) "[]" == Ok [])
            , "var:" ++ flag (Parser.run typeVar "cat_1" == Ok "cat_1")
            , "varf:" ++ flag (Result.toMaybe (Parser.run typeVar "let") == Nothing)
            , "loop:" ++ flag (Parser.run digits "1 2 3" == Ok [ 1, 2, 3 ])
            , "lc:" ++ flag (Parser.run commentThenInt "-- hi\n9" == Ok 9)
            , "end:" ++ flag (Parser.run (Parser.succeed () |. Parser.end) "" == Ok ())
            , "endf:" ++ flag (Result.toMaybe (Parser.run (Parser.keyword "true" |. Parser.end) "true!") == Nothing)
            , "mc:" ++ flag (Parser.run nestedComment "{- {- hi -} -}42" == Ok 42)
            , "mcn:" ++ flag (Parser.run jsComment "/* a /* b */42" == Ok 42)
            , "cw:" ++ flag (Parser.run (Parser.getChompedString (Parser.chompWhile Char.isDigit)) "123abc" == Ok "123")
            , "ci:" ++ flag (Parser.run (Parser.chompIf Char.isDigit) "9" == Ok ())
            , "cif:" ++ flag (Result.toMaybe (Parser.run (Parser.chompIf Char.isDigit) "a") == Nothing)
            , "off:" ++ flag (Parser.run Parser.getOffset "" == Ok 0)
            , "src:" ++ flag (Parser.run Parser.getSource "hello" == Ok "hello")
            , "row:" ++ flag (Parser.run Parser.getRow "" == Ok 1)
            , "col:" ++ flag (Parser.run Parser.getCol "" == Ok 1)
            , "tok:" ++ flag (Parser.run (Parser.token "--") "--hi" == Ok ())
            , "pr:" ++ flag (Result.toMaybe (Parser.run (Parser.problem "bad") "x") == Nothing)
            , "ue:" ++ flag (Parser.run (Parser.getChompedString (Parser.chompUntilEndOr ",")) "a,b" == Ok "a")
            , "uee:" ++ flag (Parser.run (Parser.getChompedString (Parser.chompUntilEndOr ",")) "ab" == Ok "ab")
            , "bt:" ++ flag (Parser.run (Parser.backtrackable Parser.int) "42" == Ok 42)
            , "pm:" ++ flag (Parser.run (Parser.map (\n -> n + 1) Parser.int) "41" == Ok 42)
            , "at:" ++ flag (Parser.run digitsInt "42x" == Ok 42)
            , "atf:" ++ flag (Result.toMaybe (Parser.run digitsInt "abc") == Nothing)
            , "lz:" ++ flag (Parser.run (Parser.lazy (\_ -> Parser.int)) "7" == Ok 7)
            , "cm:" ++ flag (Parser.run (Parser.commit 3) "ignored" == Ok 3)
            ]
        )
