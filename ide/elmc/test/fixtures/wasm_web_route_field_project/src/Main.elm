module Main exposing (main)

import Html exposing (Html, text)
import Route.Articles.Example


main : Html String
main =
    text (Route.Articles.Example.route.data "ok")
