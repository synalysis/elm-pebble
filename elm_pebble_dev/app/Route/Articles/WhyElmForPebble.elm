module Route.Articles.WhyElmForPebble exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, a, div, h1, h2, li, p, section, span, text, ul)
import Html.Attributes exposing (href)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, emerald, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s700, s8, s800, s900, s950, slate, white)
import UrlPath
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask FatalError Data
data =
    BackendTask.succeed {}


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head _ =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Elm Pebble"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "Elm Pebble"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Why Elm is a strong fit for writing Pebble watchfaces, apps, and browser interfaces, especially for developers who are new to Elm or considering learning it."
        , locale = Nothing
        , title = "Why Elm fits Pebble watchfaces and apps"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "Why Elm fits Pebble | Elm Pebble"
    , body =
        [ div
            [ classes
                [ Tw.min_h_screen
                , Tw.bg_color (gray s100)
                , Tw.text_color (slate s900)
                , Tw.antialiased
                , dark
                    [ Tw.bg_color (slate s950)
                    , Tw.text_color (gray s100)
                    ]
                ]
            ]
            [ div
                [ classes
                    [ Tw.mx_auto
                    , Tw.w_full
                    , Tw.px s6
                    , Tw.py s12
                    , Tw.leading_relaxed
                    , Tw.raw "max-w-3xl"
                    , md [ Tw.px s10, Tw.py s16 ]
                    ]
                ]
                [ hero
                , sectionBlock "Pebble apps reward boring reliability"
                    [ paragraph "A watchface is tiny, but it is always in front of you. It wakes up often, reacts to time and system events, talks to the phone, and redraws on a very small screen. The code is usually not large, but the state can become surprisingly fiddly."
                    , paragraph "Elm is a good match because it makes state changes explicit. Time ticks, battery changes, button presses, and companion messages all become named messages that flow through one update function. That structure keeps a small watch app understandable even after you add weather, settings, vibration, resources, and phone communication."
                    ]
                , sectionBlock "The useful Elm idea in one minute"
                    [ paragraph "If you have not used Elm before, think of it as a small, strongly typed language built around a simple loop: keep a model, receive a message, produce a new model, and describe what should be shown."
                    , bulletList
                        [ "Model: the current state of the app."
                        , "Msg: the list of things that can happen."
                        , "update: the state machine that reacts to messages."
                        , "view: a pure description of the UI for the current model."
                        , "Cmd and Sub: the controlled way to talk to the outside world."
                        ]
                    , paragraph "That shape is especially nice on Pebble because the watch platform itself is event-driven. Elm does not hide that. It gives those events names and types."
                    ]
                , sectionBlock "Why this helps on a watch"
                    [ bulletList
                        [ "No null surprises: optional values use Maybe, so loading states for time, battery, weather, and settings are visible in the type."
                        , "No forgotten cases: when you add a new protocol message or app event, Elm pushes you to handle it wherever it matters."
                        , "Pure rendering: the screen is drawn from the model, so layout code is easier to reason about and test mentally."
                        , "Typed phone messages: the watch and companion app can share a protocol instead of passing loosely shaped strings around."
                        , "Small refactors feel safer: changing a data type gives useful compiler errors instead of quiet runtime drift."
                        ]
                    ]
                , sectionBlock "Why it is appealing if you are considering learning Elm"
                    [ paragraph "Pebble projects are a friendly place to learn Elm because the scope is small. You are not starting with a giant web application, routing, forms, CSS architecture, or a company-wide frontend stack. You can learn the core Elm pattern by building something you can actually wear."
                    , paragraph "The feedback loop is concrete: change a color, move text, add an event, send a message to the phone, and see the result on a watchface. That makes the language feel less abstract than learning it from a todo app."
                    , paragraph "Those same skills transfer directly to Elm in the browser. Browser Elm apps use the same model, message, update, view, command, and subscription ideas. The UI target changes from Pebble drawing operations to HTML, but the way you structure state and events stays familiar."
                    , paragraphWithLinks
                        [ text "If you are deciding whether to learn Elm, start with the original "
                        , externalLink "https://elm-lang.org/" "Elm website"
                        , text " and then work through "
                        , externalLink "https://guide.elm-lang.org/" "the excellent Elm Guide"
                        , text ". The Pebble examples here make the same ideas concrete on a tiny device."
                        ]
                    , bulletList
                        [ "You learn algebraic data types by modeling real watch and phone messages."
                        , "You learn pure functions by formatting time, dates, weather, and drawing operations."
                        , "You learn commands and subscriptions through real device events."
                        , "You learn the compiler by letting it guide changes across the watch, companion, shared protocol, and browser UI code."
                        ]
                    ]
                , sectionBlock "The browser benefit"
                    [ paragraph "Learning Elm for Pebble is not a dead-end niche skill. Elm was designed for building browser applications, and elm-pebble keeps the same language habits: precise types, explicit messages, pure views, and controlled side effects."
                    , paragraph "After building a watchface, a browser app will feel like the same architecture with a larger screen and different rendering primitives. Instead of returning Pebble UI nodes, view returns HTML. Instead of Pebble events, subscriptions might listen for time, websockets, or browser events. Instead of a companion protocol, you might model API responses or page-level messages."
                    , paragraph "That means a small Pebble project can be a practical way to learn Elm before using it for dashboards, internal tools, interactive pages, or other browser interfaces where predictable state matters."
                    ]
                , sectionBlock "What Elm does not magically solve"
                    [ paragraph "Elm does not remove the Pebble platform. You still need to understand screen size, resources, battery limits, AppMessage payloads, and what belongs on the phone versus on the watch. Elm also asks you to model your states up front, which can feel slower at first if you are used to sketching with mutable objects."
                    , paragraph "The payoff comes when the project grows past the first sketch. The same explicit model that felt a little formal at the beginning becomes the map you use to change the app without guessing where state is hiding."
                    ]
                , sectionBlock "A good mental model"
                    [ paragraph "Treat Elm as the contract for your watch app. The model says what the app knows. The messages say what can happen. The update function says how facts change. The view says what the watch should draw. The protocol says what the phone and watch are allowed to tell each other."
                    , paragraph "For Pebble, that is a practical fit: small hardware, clear events, typed messages, and a UI that should always reflect the current state."
                    ]
                , backLink
                ]
            ]
        ]
    }


hero : Html msg
hero =
    section
        [ classes
            [ Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s8
            , Tw.shadow_lg
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ span
            [ classes
                [ Tw.inline_flex
                , Tw.rounded_lg
                , Tw.bg_color (emerald s100)
                , Tw.px s3
                , Tw.py s2
                , Tw.text_base
                , Tw.font_semibold
                , Tw.text_color (emerald s700)
                , dark
                    [ Tw.bg_color (emerald s900)
                    , Tw.text_color (emerald s200)
                    ]
                ]
            ]
            [ text "Article" ]
        , h1
            [ classes
                [ Tw.mt s6
                , Tw.text_n3xl
                , Tw.font_black
                , Tw.tracking_tight
                , md [ Tw.text_n4xl ]
                ]
            ]
            [ text "Why Elm is a good fit for Pebble watchfaces and apps" ]
        , p
            [ classes
                [ Tw.mt s5
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "For developers who have never used Elm, and for anyone wondering whether this small language is worth learning for tiny wrist-sized projects and browser apps." ]
        ]


sectionBlock : String -> List (Html msg) -> Html msg
sectionBlock heading children =
    section
        [ classes [ Tw.mt s12 ] ]
        (h2 [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ] [ text heading ]
            :: children
        )


paragraph : String -> Html msg
paragraph value =
    p
        [ classes
            [ Tw.mt s4
            , Tw.text_color (gray s700)
            , dark [ Tw.text_color (gray s300) ]
            ]
        ]
        [ text value ]


paragraphWithLinks : List (Html msg) -> Html msg
paragraphWithLinks children =
    p
        [ classes
            [ Tw.mt s4
            , Tw.text_color (gray s700)
            , dark [ Tw.text_color (gray s300) ]
            ]
        ]
        children


externalLink : String -> String -> Html msg
externalLink url label =
    a
        [ href url
        , classes
            [ Tw.font_semibold
            , Tw.text_color (blue s700)
            , dark [ Tw.text_color (blue s400) ]
            ]
        ]
        [ text label ]


bulletList : List String -> Html msg
bulletList items =
    ul
        [ classes
            [ Tw.mt s5
            , Tw.flex
            , Tw.flex_col
            , Tw.gap s3
            , Tw.list_disc
            , Tw.pl s6
            , Tw.text_color (gray s700)
            , dark [ Tw.text_color (gray s300) ]
            ]
        ]
        (List.map (\item -> li [] [ text item ]) items)


backLink : Html msg
backLink =
    section
        [ classes [ Tw.mt s12 ] ]
        [ p
            [ classes [ Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ Route.Index
                |> Route.link
                    [ classes
                        [ Tw.font_semibold
                        , Tw.text_color (blue s700)
                        , dark [ Tw.text_color (blue s400) ]
                        ]
                    ]
                    [ text "Back to the home page" ]
            ]
        ]
