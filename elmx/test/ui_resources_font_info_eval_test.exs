defmodule Elmx.UiResourcesFontInfoEvalTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../..", __DIR__)

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elmx-font-info-#{System.unique_integer([:positive])}"
      )

    src = Path.join([tmp, "src", "Pebble", "Ui"])
    File.mkdir_p!(src)

    File.write!(Path.join(tmp, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Resources as UiResources


    type alias Model =
        { fontHeight : Int }


    type Msg
        = NoOp


    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { fontHeight = (UiResources.fontInfo UiResources.Quote28).height }
        , Cmd.none
        )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    view : Model -> PebbleUi.UiNode
    view _ =
        PebbleUi.toUiNode []


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """)

    File.write!(Path.join(src, "Resources.elm"), """
    module Pebble.Ui.Resources exposing (Font(..), FontInfo, fontInfo)

    type Font
        = DefaultFont
        | Quote28


    type alias FontInfo =
        { font : Font
        , name : String
        , height : Int
        }


    fontInfo : Font -> FontInfo
    fontInfo font =
        case font of
            DefaultFont ->
                { font = DefaultFont, name = "DefaultFont", height = 14 }

            Quote28 ->
                { font = Quote28, name = "Quote28", height = 28 }
    """)

    elm_json = %{
      "type" => "application",
      "source-directories" => [
        "src",
        Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
        Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
        Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
        Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
      ],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))
    on_exit(fn -> File.rm_rf(tmp) end)
    %{project_dir: tmp}
  end

  @tag timeout: 120_000
  test "fontInfo returns a record so init can read .height", %{project_dir: dir} do
    revision = "font-info-#{System.unique_integer([:positive])}"

    assert {:ok, %Elmx.CompileResult{} = result} =
             Elmx.compile_in_memory(dir, %{
               entry_module: "Main",
               revision: revision,
               strip_dead_code: true,
               mode: :ide_runtime
             })

    assert {:ok, init} =
             Elmx.Runtime.Executor.execute_generated(result.entry_module, %{
               "current_model" => %{
                 "launch_context" => %{
                   "screen" => %{"width" => 144, "height" => 168, "shape" => "Rectangular"}
                 }
               },
               "message" => nil
             })

    runtime_model =
      get_in(init, [:model_patch, "runtime_model"]) ||
        get_in(init, ["model_patch", "runtime_model"])

    height = runtime_model["fontHeight"] || runtime_model[:fontHeight]
    assert height == 28
  end
end
