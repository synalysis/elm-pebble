module Main exposing (main)
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
type alias TickSpec = { value : Int, size : Int, label : Maybe String }
view _ = Ui.toUiNode (ticks { cx = 1, cy = 2, radius = 3 })
ticks layout =
  let
    shortItems = List.map (\i -> { value = i * 60, size = 10, label = Nothing }) (List.range 1 5 |> List.filter (\n -> modBy 2 n == 1))
  in List.concatMap (drawTick layout) shortItems
drawTick layout spec = [ Ui.line { x = 0, y = 0 } { x = 1, y = 1 } Color.white ]
main = Platform.application { init = \ _ -> ({}, Platform.Cmd.none), update = \ _ m -> (m, Platform.Cmd.none), subscriptions = \ _ -> Platform.Sub.none, view = view }
