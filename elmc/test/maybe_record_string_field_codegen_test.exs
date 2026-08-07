defmodule Elmc.MaybeRecordStringFieldCodegenTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  alias Elmc.TestSupport.SnippetProject

  test "Maybe record string fields with ambiguous names use get_index in direct view" do
    # `label` appears on both TickSpec and WeatherSlot. Without case payload
    # typing, direct-render falls back to elmc_record_get by name, which returns
    # int_zero on unnamed values_take records — empty text on device while the
    # debugger (elmx) still shows the string.
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { weather : Maybe WeatherSlot
        , topLeft : { value : String, caption : String }
        }


    type alias WeatherSlot =
        { label : String
        , icon : Int
        }


    type alias TickSpec =
        { minute : Int
        , outerExtra : Int
        , label : String
        }


    type Msg
        = NoOp


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { weather = Just { label = "21C", icon = 2 }
          , topLeft = { value = "88%", caption = "Battery" }
          }
        , Cmd.none
        )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> Ui.UiNode
    view model =
        Ui.toUiNode (drawCorners model)


    drawCorners : Model -> List Ui.RenderOp
    drawCorners model =
        drawWeather model.weather
            ++ [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 5, y = 5, w = 40, h = 18 } model.topLeft.value
               , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 5, y = 23, w = 44, h = 14 } model.topLeft.caption
               ]


    drawWeather : Maybe WeatherSlot -> List Ui.RenderOp
    drawWeather maybeSlot =
        case maybeSlot of
            Nothing ->
                []

            Just slot ->
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 50, y = 205, w = 45, h = 18 } slot.label
                ]


    -- Keep TickSpec reachable so `label` stays an ambiguous field name.
    tickLabel : TickSpec -> String
    tickLabel spec =
        spec.label


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    out_dir =
      SnippetProject.compile_main!(source,
        name: "maybe_weather_label_index",
        compile: %{strip_dead_code: false, direct_render_only: true}
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ ~s|elmc_record_get(elmc_maybe_or_tuple_just_payload_borrow|,
           "Maybe Just string fields must not use name lookup on the payload borrow"

    refute generated_c =~ ~s|, "label")|,
           "ambiguous record field `label` must resolve to an index, not elmc_record_get by name"

    refute generated_c =~ ~s|, "value")|,
           "anonymous topLeft.value must resolve to an index, not elmc_record_get by name"

    refute generated_c =~ ~s|, "caption")|,
           "anonymous topLeft.caption must resolve to an index, not elmc_record_get by name"

    assert String.contains?(generated_c, "WEATHERSLOT_LABEL"),
           "expected ELMC_FIELD_*_WEATHERSLOT_LABEL get_index for slot.label"
  end
end



