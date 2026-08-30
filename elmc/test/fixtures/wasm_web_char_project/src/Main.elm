module Main exposing (main)

import Html exposing (Html, text)


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
            [ "tc:" ++ flag (Char.toCode 'A' == 65)
            , "tw:" ++ flag (Char.toCode '木' == 0x6728)
            , "fc:" ++ flag (Char.fromCode 65 == 'A')
            , "fw:" ++ flag (Char.fromCode 0x6728 == '木')
            , "ff:" ++ flag (Char.fromCode -1 == '�')
            , "up:" ++ flag (Char.toUpper 'a' == 'A')
            , "lo:" ++ flag (Char.toLower 'Z' == 'z')
            , "ue:" ++ flag (Char.toUpper 'é' == 'É')
            , "iu:" ++ flag (Char.isUpper 'A' && not (Char.isUpper 'a') && not (Char.isUpper 'Σ'))
            , "il:" ++ flag (Char.isLower 'z' && not (Char.isLower 'A'))
            , "ia:" ++ flag (Char.isAlpha 'Y' && not (Char.isAlpha 'π'))
            , "id:" ++ flag (Char.isDigit '7' && not (Char.isDigit 'a'))
            , "io:" ++ flag (Char.isOctDigit '7' && not (Char.isOctDigit '8'))
            , "ih:" ++ flag (Char.isHexDigit 'f' && not (Char.isHexDigit 'g'))
            , "lu:" ++ flag (Char.toLocaleUpper 'a' == 'A')
            , "ll:" ++ flag (Char.toLocaleLower 'Z' == 'z')
            , "lue:" ++ flag (Char.toLocaleUpper 'é' == 'É')
            , "ian:" ++ flag (Char.isAlphaNum 'A' && Char.isAlphaNum '7' && not (Char.isAlphaNum '-'))
            , "us:" ++ flag (Char.toUpper 'š' == 'Š')
            , "ls:" ++ flag (Char.toLower 'Š' == 'š')
            , "uy:" ++ flag (Char.toUpper 'я' == 'Я')
            ]
        )
