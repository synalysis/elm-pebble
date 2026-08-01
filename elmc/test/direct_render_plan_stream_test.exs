defmodule Elmc.DirectRenderPlanStreamTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.SnippetProject

  test "simple view list lowers through plan stream SSA with scene writer push" do
    out_dir =
      SnippetProject.compile_main!(simple_view_source(),
        name: "direct_plan_stream_simple_view",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_simple_view_codegen", __DIR__)
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_draw_cmd_init"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_render_cmd6_take"
    refute view_body =~ "ELMC_TAG_LIST"
  end

  test "direct render keeps native Basics.min and font literals unboxed in view_commands_append" do
    out_dir =
      SnippetProject.compile_main!(native_min_view_source(),
        name: "direct_plan_stream_native_min",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_native_min_codegen", __DIR__)
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    refute view_body =~ ~r/elmc_new_int\(&owned\[\d+\], 1\)/
    assert view_body =~ "scene_cmd.p0 = 1"
    refute view_body =~ ~r/elmc_as_int_number\(owned\[\d+\]\)/
  end

  defp native_min_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { screenW : Int
        , screenH : Int
        }


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
        ( { screenW = 144, screenH = 168 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            minDim =
                Basics.min model.screenW model.screenH

            bounds =
                { x = 0, y = 0, w = minDim, h = 18 }
        in
        Ui.toUiNode
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds "Hi"
            ]
    """
  end

  defp simple_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


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
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            [ Ui.clear Color.black
            , Ui.fillCircle { x = 20, y = 30 } 12 Color.white
            ]
    """
  end
end
