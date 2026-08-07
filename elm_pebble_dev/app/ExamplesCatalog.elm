module ExamplesCatalog exposing (Example, all, featured, ideTemplateUrl)


{-| Showcase templates for the marketing gallery and home teaser.
-}
type alias Example =
    { title : String
    , blurb : String
    , category : String
    , image : String
    , templateKey : String
    , featured : Bool
    }


ideTemplateUrl : String -> String
ideTemplateUrl templateKey =
    "https://ide.elm-pebble.dev/projects?template=" ++ templateKey ++ "&new=1"


featured : List Example
featured =
    List.filter .featured all


all : List Example
all =
    [ { title = "YES"
      , blurb = "Solar dial, moon phase, and companion weather on a dense round face."
      , category = "Watchface"
      , image = "/images/examples/watchface-yes.png"
      , templateKey = "watchface-yes"
      , featured = True
      }
    , { title = "Tangram Time"
      , blurb = "Geometric art that still tells time — a favorite showpiece."
      , category = "Watchface"
      , image = "/images/examples/watchface-tangram-time.png"
      , templateKey = "watchface-tangram-time"
      , featured = True
      }
    , { title = "Digital"
      , blurb = "A clean starting face: time, layout, and colors you can reshape quickly."
      , category = "Watchface"
      , image = "/images/examples/watchface-digital.png"
      , templateKey = "watchface-digital"
      , featured = True
      }
    , { title = "Analog"
      , blurb = "Classic hands with typed state for ticks, battery, and style tweaks."
      , category = "Watchface"
      , image = "/images/examples/watchface-analog.png"
      , templateKey = "watchface-analog"
      , featured = False
      }
    , { title = "Weather animated"
      , blurb = "Companion weather plus vector weather icons on the wrist."
      , category = "Watchface"
      , image = "/images/examples/watchface-weather-animated.png"
      , templateKey = "watchface-weather-animated"
      , featured = True
      }
    , { title = "Tutorial complete"
      , blurb = "The weather watchface walked through step by step in the tutorial."
      , category = "Watchface"
      , image = "/images/examples/watchface-tutorial-complete.png"
      , templateKey = "watchface-tutorial-complete"
      , featured = False
      }
    , { title = "2048"
      , blurb = "A full game loop on the watch — buttons, board state, and scoring."
      , category = "Game"
      , image = "/images/examples/game-2048.png"
      , templateKey = "game-2048"
      , featured = True
      }
    , { title = "Elmtris"
      , blurb = "Tetris-style play with piece motion, lines, and a small playfield."
      , category = "Game"
      , image = "/images/examples/game-elmtris.png"
      , templateKey = "game-elmtris"
      , featured = False
      }
    , { title = "Tiny Bird"
      , blurb = "A flappy-style side scroller for button timing and frame updates."
      , category = "Game"
      , image = "/images/examples/game-tiny-bird.png"
      , templateKey = "game-tiny-bird"
      , featured = False
      }
    ]
