
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Layout =
        { cx : Int, cy : Int, radius : Int }

    type alias TickSpec =
        { value : Int, size : Int, label : Maybe String }

    type alias Model =
        {}

    type Msg
        = NoOp

    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }

    init _ =
        ( {}, Platform.Cmd.none )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view _ =
        Ui.toUiNode <|
            let
                shortItems =
                    List.map
                        (\\i -> { value = i * 60, size = 10, label = Nothing })
                        (List.range 1 5 |> List.filter (\\n -> modBy 2 n == 1))

                longItems =
                    List.map
                        (\\i -> { value = i * 120, size = 6, label = Just (String.fromInt (i * 2)) })
                        (List.range 0 2)
            in
            List.concatMap (drawTick layout) (shortItems ++ longItems)

    layout =
        { cx = 72, cy = 84, radius = 60 }

    drawTick layout spec =
        let
            x0 =
                layout.cx + layout.radius

            y0 =
                layout.cy

            x1 =
                layout.cx + layout.radius + spec.size

            y1 =
                layout.cy + spec.value // 60
        in
        case spec.label of
            Nothing ->
                [ Ui.line { x = x1, y = y1 } { x = x0, y = y0 } Color.white ]

            Just _ ->
                [ Ui.line { x = x1, y = y1 } { x = x0, y = y0 } Color.white
                , Ui.line { x = x0, y = y0 } { x = x1, y = y1 } Color.lightGray
                ]
    