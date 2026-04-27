module Route.Tutorial.WatchfaceTutorialComplete exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, code, div, h1, h2, li, p, pre, section, span, text, ul)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, emerald, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s600, s700, s8, s800, s900, s950, slate, white)
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
            , alt = "Elm Pebble watchface tutorial"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "A beginner-friendly walkthrough of the Watchface tutorial complete Elm Pebble project template, written for programmers who are new to Elm."
        , locale = Nothing
        , title = "Watchface tutorial complete code walkthrough"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "Watchface tutorial complete | Elm Pebble"
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
                , intro
                , sectionBlock "The big idea: Elm programs are loops"
                    [ paragraph "If you know React, Redux, SwiftUI, game loops, or server request handlers, the structure will feel familiar. The program keeps all important state in one value called the model. Events arrive as messages. An update function receives a message and returns the next model plus any commands that should talk to the outside world."
                    , paragraph "The watchface is not building HTML. The view function returns Pebble drawing instructions, and elm-pebble turns those instructions into native Pebble rendering code."
                    , codeBlock "Watch app: watch/src/Main.elm" "type alias Model =\n    { screenW : Int\n    , screenH : Int\n    , isRound : Bool\n    , currentDateTime : Maybe PebbleTime.CurrentDateTime\n    , batteryLevel : Maybe Int\n    , connected : Maybe Bool\n    , temperature : Maybe Temperature\n    , condition : Maybe WeatherCondition\n    , backgroundColor : Maybe PebbleColor.Color\n    , textColor : Maybe PebbleColor.Color\n    , showDate : Maybe Bool\n    }"
                    ]
                , sectionBlock "Step 1: the model is your app state"
                    [ paragraph "The model is an Elm record. A record is close to a typed object or struct: every field has a name and a type, and Elm checks that you use those fields consistently."
                    , paragraph "Several fields use Maybe. Think of Maybe as a safer nullable value: Nothing means the value has not arrived yet, and Just value means it is available. The watch starts before it has time, battery, connection, weather, or phone settings, so those values are optional."
                    , bulletList
                        [ "screenW, screenH, and isRound come from the launch context so the same code can draw on different Pebble screen shapes."
                        , "currentDateTime, batteryLevel, and connected are facts read from the watch."
                        , "temperature, condition, backgroundColor, textColor, and showDate are supplied by the phone companion protocol."
                        ]
                    ]
                , sectionBlock "Step 2: messages describe what happened"
                    [ paragraph "Msg is a custom type. In other languages you might model this with an enum, tagged union, sealed class, or discriminated union. Each variant names one thing that can happen to the program, and variants can carry data."
                    , codeBlock "Watch app: watch/src/Main.elm" "type Msg\n    = CurrentDateTime PebbleTime.CurrentDateTime\n    | FromPhone PhoneToWatch\n    | MinuteChanged Int\n    | HourChanged Int\n    | BatteryLevelChanged Int\n    | ConnectionStatusChanged Bool"
                    , paragraph "This is why Elm code often reads like a list of cases: time can arrive, the phone can send a protocol message, a minute can tick, the battery can change, or the connection state can change."
                    ]
                , sectionBlock "Step 3: init builds the first model and asks for data"
                    [ paragraph "init runs once when the watchface starts. It copies screen information out of PebblePlatform.LaunchContext, fills everything else with Nothing, then batches several startup commands."
                    , codeBlock "Watch app: watch/src/Main.elm" "init context =\n    ( { screenW = context.screen.width\n      , screenH = context.screen.height\n      , isRound = context.screen.isRound\n      , currentDateTime = Nothing\n      , batteryLevel = Nothing\n      , connected = Nothing\n      , temperature = Nothing\n      , condition = Nothing\n      , backgroundColor = Nothing\n      , textColor = Nothing\n      , showDate = Nothing\n      }\n    , Cmd.batch\n        [ PebbleTime.currentDateTime CurrentDateTime\n        , PebbleSystem.batteryLevel BatteryLevelChanged\n        , PebbleSystem.connectionStatus ConnectionStatusChanged\n        , CompanionWatch.sendWatchToPhone (RequestWeather CurrentLocation)\n        ]\n    )"
                    , paragraph "Commands are Elm's way to request side effects. The code does not directly mutate global state or block while reading the battery. It asks the Pebble runtime to do work and says which Msg constructor should wrap the result when it comes back."
                    ]
                , sectionBlock "Step 4: update is the state machine"
                    [ paragraph "update receives a message and the current model. It returns the next model and a command. Record update syntax looks like { model | batteryLevel = Just level }: copy the old record, but replace one field."
                    , bulletList
                        [ "CurrentDateTime stores the current clock value."
                        , "MinuteChanged updates only the minute, and every 30 minutes asks the phone for fresh weather."
                        , "HourChanged refreshes the full date/time so day and date rollovers stay correct."
                        , "BatteryLevelChanged stores the latest battery level, whether it came from the startup command or a later battery-change event."
                        , "ConnectionStatusChanged stores the latest connection state and vibrates twice when the phone disconnects."
                        ]
                    , codeBlock "Watch app: watch/src/Main.elm" "ConnectionStatusChanged connected ->\n    ( { model | connected = Just connected }\n    , if connected then\n        Cmd.none\n\n      else\n        PebbleVibes.doublePulse\n    )"
                    ]
                , sectionBlock "Step 5: the shared protocol is the contract"
                    [ paragraph "The finished template is split into watch, phone, and protocol packages. The protocol package is the contract both sides import. It says which values can cross the Pebble AppMessage boundary, using normal Elm custom types instead of unstructured JSON strings."
                    , codeBlock "Protocol: protocol/src/Companion/Types.elm" "type WatchToPhone\n    = RequestWeather Location\n\n\ntype PhoneToWatch\n    = ProvideTemperature Temperature\n    | ProvideCondition WeatherCondition\n    | SetBackgroundColor TutorialColor\n    | SetTextColor TutorialColor\n    | SetShowDate Bool"
                    , paragraph "Read those two types as the public API between devices. The watch is allowed to ask for weather for a Location. The phone is allowed to send back temperature, condition, and a few display settings. If you add a new setting later, this is where the new message should start."
                    , bulletList
                        [ "Location, Temperature, WeatherCondition, and TutorialColor are the shared vocabulary."
                        , "WatchToPhone describes requests sent by the watch."
                        , "PhoneToWatch describes responses and settings sent by the phone."
                        , "Companion.Internal is generated from these types and handles the wire encoding, so app code can work with typed values."
                        ]
                    ]
                , sectionBlock "Step 6: the companion app answers watch requests"
                    [ paragraph "The companion app is another Elm program, but it runs on the phone side rather than on the watch. It uses Platform.worker because it has no visual UI here: it listens for watch messages, performs HTTP requests, and sends messages back."
                    , codeBlock "Companion app: phone/src/CompanionApp.elm" "type Msg\n    = FromWatch (Result String WatchToPhone)\n    | WeatherReceived (Result Http.Error WeatherReport)\n    | DemoPosted (Result Http.Error String)"
                    , paragraph "When the watch sends RequestWeather, the phone builds an Open-Meteo URL, starts an Http.get command, and also sends a demo POST request. When the weather response arrives, it rounds the temperature and sends two typed messages back to the watch."
                    , codeBlock "Companion app: phone/src/CompanionApp.elm" "WeatherReceived result ->\n    case result of\n        Ok weather ->\n            let\n                rounded =\n                    round weather.temperature\n            in\n            ( { model | lastResponse = rounded }\n            , Cmd.batch\n                [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius rounded))\n                , CompanionPhone.sendPhoneToWatch (ProvideCondition weather.condition)\n                ]\n            )\n\n        Err _ ->\n            ( model, Cmd.none )"
                    , paragraph "The companion app subscribes with CompanionPhone.onWatchToPhone FromWatch. That means incoming phone-side AppMessage payloads enter the same Elm update loop as HTTP responses."
                    ]
                , sectionBlock "Step 7: phone messages update watch settings and weather"
                    [ paragraph "Back on the watch, CompanionWatch.onPhoneToWatch turns incoming phone messages into FromPhone values. The watch receives PhoneToWatch values, so the update code can pattern match on declared messages instead of parsing loose strings."
                    , codeBlock "Watch app: watch/src/Main.elm" "updateFromPhone message model =\n    case message of\n        ProvideTemperature temperature ->\n            ( { model | temperature = Just temperature }, Cmd.none )\n\n        ProvideCondition condition ->\n            ( { model | condition = Just condition }, Cmd.none )\n\n        SetBackgroundColor color ->\n            ( { model | backgroundColor = Just (pebbleColor color) }, Cmd.none )"
                    , paragraph "That is normal Elm style: make the allowed messages explicit, handle every case, and let the compiler complain if the protocol changes and you forget to update the watch."
                    ]
                , sectionBlock "Step 8: subscriptions keep the watchface alive"
                    [ paragraph "Subscriptions register long-running event sources. This template listens for minute ticks, hour ticks, battery changes, connection changes, and phone-to-watch messages."
                    , codeBlock "Watch app: watch/src/Main.elm" "subscriptions _ =\n    PebbleEvents.batch\n        [ PebbleEvents.onMinuteChange MinuteChanged\n        , PebbleEvents.onHourChange HourChanged\n        , PebbleSystem.onBatteryChange BatteryLevelChanged\n        , PebbleSystem.onConnectionChange ConnectionStatusChanged\n        , CompanionWatch.onPhoneToWatch FromPhone\n        ]"
                    , paragraph "Each subscription names the Msg constructor that should be used when the event fires. That keeps external events flowing through the same update function as startup responses."
                    ]
                , sectionBlock "Step 9: view computes layout, then draws"
                    [ paragraph "The view function is pure: it looks at the model and returns drawing instructions. It first calculates positions from the screen size and shape, chooses default colors, and conditionally builds small lists of render operations."
                    , bulletList
                        [ "batteryOps draws a battery outline and fill only after a battery level is known."
                        , "btIcon draws the Bluetooth icon only when connected is Just False."
                        , "dateOps draws the date only when the phone setting says to show it and the current date is available."
                        , "The final expression concatenates those lists and converts them with PebbleUi.toUiNode."
                        ]
                    , codeBlock "Watch app: watch/src/Main.elm" "[ PebbleUi.clear backgroundColor\n]\n    ++ batteryOps\n    ++ [ drawCentered model textColor timeY 56 (timeString model)\n       , drawCentered model textColor weatherY 22 (weatherString model)\n       ]\n    ++ btIcon\n    ++ dateOps\n    |> PebbleUi.toUiNode"
                    , paragraph "Because there is no hidden mutation in view, the screen is always a direct result of the current model. Change the model, and the next render describes the new screen."
                    ]
                , sectionBlock "Step 10: helpers keep display logic small"
                    [ paragraph "The rest of Main.elm is small conversion code: format the time, format the date, turn protocol colors into Pebble colors, and turn weather constructors into user-facing text."
                    , codeBlock "Watch app: watch/src/Main.elm" "timeString model =\n    case model.currentDateTime of\n        Nothing ->\n            \"--:--\"\n\n        Just currentDateTime ->\n            pad2 currentDateTime.hour ++ \":\" ++ pad2 currentDateTime.minute"
                    , paragraph "Notice the fallback. While the clock value is missing, the UI still has something predictable to draw. Once CurrentDateTime arrives, the same function formats the real value."
                    ]
                , sectionBlock "Step 11: main connects your code to Pebble"
                    [ paragraph "The last value, main, hands the core pieces to the elm-pebble platform: init for startup, update for state transitions, and subscriptions for ongoing events."
                    , codeBlock "Watch app: watch/src/Main.elm" "main : Program Decode.Value Model Msg\nmain =\n    PebblePlatform.worker\n        { init = init\n        , update = update\n        , subscriptions = subscriptions\n        }"
                    , paragraph "The view function is still the drawing contract used by the watchface tooling. The worker entry point keeps the runtime event loop explicit: initialize state, react to messages, and stay subscribed to Pebble and companion events."
                    ]
                , sectionBlock "What to change first"
                    [ paragraph "Once you understand the loop, safe experiments become obvious."
                    , bulletList
                        [ "Change the default colors in view by replacing PebbleColor.black or PebbleColor.white."
                        , "Move text by changing timeY, dateY, weatherY, or batteryY."
                        , "Change updateFromPhone if you add a new phone setting to the companion protocol."
                        , "Add a new Msg when a new Pebble event or command result needs to affect the model."
                        ]
                    , paragraph "The habit to keep: add data to the model, describe events as Msg values, update the model in update, and make view draw from the model."
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
            [ text "Tutorial" ]
        , h1
            [ classes
                [ Tw.mt s6
                , Tw.text_n3xl
                , Tw.font_black
                , Tw.tracking_tight
                , md [ Tw.text_n4xl ]
                ]
            ]
            [ text "Understanding the Watchface tutorial complete template" ]
        , p
            [ classes
                [ Tw.mt s5
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "A guided walk through the finished watchface project for programmers who are comfortable with code, but new to Elm." ]
        ]


intro : Html msg
intro =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2 [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ] [ text "What the template builds" ]
        , paragraph "The complete tutorial template is a real watchface: it shows the time, optional date, weather text, battery level, and a Bluetooth warning icon. It adapts to rectangular and round Pebble screens, asks the phone companion for weather, and vibrates when the watch disconnects."
        , paragraph "Most of the watch rendering code lives in watch/src/Main.elm. The shared protocol in protocol/src/Companion/Types.elm defines the messages that can travel between watch and phone, and phone/src/CompanionApp.elm implements the companion worker that fetches weather and replies."
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


codeBlock : String -> String -> Html msg
codeBlock source value =
    div
        [ classes [ Tw.mt s5 ] ]
        [ span
            [ classes
                [ Tw.text_sm
                , Tw.font_semibold
                , Tw.text_color (gray s600)
                , dark [ Tw.text_color (gray s400) ]
                ]
            ]
            [ text source ]
        , pre
            [ classes
                [ Tw.mt s2
                , Tw.overflow_x_auto
                , Tw.rounded_lg
                , Tw.border
                , Tw.border_color (gray s200)
                , Tw.bg_color (slate s900)
                , Tw.p s5
                , Tw.text_sm
                , Tw.text_simple white
                , dark [ Tw.border_color (slate s700) ]
                ]
            ]
            [ code [] [ text value ] ]
        ]


backLink : Html msg
backLink =
    section
        [ classes [ Tw.mt s12 ] ]
        [ p
            [ classes [ Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
            [ Route.Index
                |> Route.link
                    [ classes
                        [ Tw.font_semibold
                        , Tw.text_color (blue s600)
                        , dark [ Tw.text_color (blue s400) ]
                        ]
                    ]
                    [ text "Back to the home page" ]
            ]
        ]
