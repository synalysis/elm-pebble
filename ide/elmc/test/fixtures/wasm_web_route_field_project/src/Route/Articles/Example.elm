module Route.Articles.Example exposing (route)


type alias Route =
    { data : String -> String }


route : Route
route =
    { data = identity }
