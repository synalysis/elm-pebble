defmodule Elmc.WatchInfoCaseColorTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.SnippetProject

  test "caseColor maps distinct watch cases to distinct palette codes" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.WatchInfo as WatchInfo


    type alias Model =
        { white : Int
        , red : Int
        , gold : Int
        , lime : Int
        , p2dWhite : Int
        }


    type Msg
        = NoOp


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { white = Color.toInt (WatchInfo.caseColor WatchInfo.TimeWhite)
          , red = Color.toInt (WatchInfo.caseColor WatchInfo.TimeRed)
          , gold = Color.toInt (WatchInfo.caseColor WatchInfo.TimeSteelGold)
          , lime = Color.toInt (WatchInfo.caseColor WatchInfo.Pebble2HrLime)
          , p2dWhite = Color.toInt (WatchInfo.caseColor WatchInfo.CoreDevicesP2DWhite)
          }
        , Cmd.none
        )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    view : Model -> Ui.UiNode
    view model =
        Ui.toUiNode
            [ Ui.clear (Color.indexed model.white)
            , Ui.fillRect { x = 0, y = 0, w = 8, h = 8 } (Color.indexed model.red)
            , Ui.fillRect { x = 8, y = 0, w = 8, h = 8 } (Color.indexed model.gold)
            , Ui.fillRect { x = 16, y = 0, w = 8, h = 8 } (Color.indexed model.lime)
            , Ui.fillRect { x = 24, y = 0, w = 8, h = 8 } (Color.indexed model.p2dWhite)
            ]


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    main : Program Decode.Value Model Msg
    main =
        Platform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    out_dir =
      SnippetProject.compile_main!(source,
        name: "watch_info_case_color",
        out_dir: Path.expand("tmp/watch_info_case_color_codegen", __DIR__)
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Pebble_WatchInfo_caseColor"
    assert generated_c =~ "elmc_dense_lut_"
    # TimeWhite / CoreDevicesP2DWhite -> white 0xFF, TimeRed -> red 0xF0
    assert generated_c =~ "ELMC_COLOR_WHITE" or generated_c =~ "255"
    assert generated_c =~ "CoreDevicesP2DWhite" or generated_c =~ "ELMC_PEBBLE_WATCH_COLOR_COREDEVICESP2DWHITE"
    assert generated_c =~ "ELMC_COLOR_RED" or generated_c =~ "240"
    # TimeSteelGold -> brass 0xE9, Pebble2HrLime -> springBud 0xEC
    assert generated_c =~ "ELMC_COLOR_BRASS" or generated_c =~ "233"
    assert generated_c =~ "ELMC_COLOR_SPRING_BUD" or generated_c =~ "236"
    refute generated_c =~ ~r/elmc_fn_Pebble_WatchInfo_caseColor[\s\S]*goto elmc_plan_block_/
  end

  test "SDK watch color/model enumerators map to Elm constructor macros" do
    body = Elmc.Backend.Pebble.SourceWriter.Prologue.WatchInfoMap.body()

    assert body =~ "int64_t elmc_pebble_watch_color_to_elm_tag(int color)"
    assert body =~ "WATCH_INFO_COLOR_COREDEVICES_P2D_WHITE"
    assert body =~ "ELMC_PEBBLE_WATCH_COLOR_COREDEVICESP2DWHITE"
    assert body =~ "WATCH_INFO_COLOR_WHITE"
    assert body =~ "ELMC_PEBBLE_WATCH_COLOR_WHITE"

    assert body =~ "int64_t elmc_pebble_watch_model_to_elm_tag(int model)"
    assert body =~ "WATCH_INFO_MODEL_COREDEVICES_P2D"
    assert body =~ "ELMC_PEBBLE_WATCH_MODEL_COREDEVICESP2D"
  end

  test "app template forwards WatchInfo enums through the generated map" do
    template =
      Path.expand("../../ide/priv/pebble_app_template/src/c/pebble_app_template.c", __DIR__)
      |> File.read!()

    assert template =~ "return elmc_pebble_watch_color_to_elm_tag((int)color);"
    assert template =~ "return elmc_pebble_watch_model_to_elm_tag((int)model);"
    assert template =~ "ELMC_PEBBLE_CATALOG_WATCH_COLOR"
    assert template =~ "WATCH_INFO_COLOR_UNKNOWN"
    refute template =~ ~r/watch_color_to_elm_tag\(WatchInfoColor color\) \{\s*\(void\)color;\s*return 0;/
  end
end
