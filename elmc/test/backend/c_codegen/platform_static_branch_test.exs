defmodule Elmc.Backend.CCodegen.PlatformStaticBranchTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

  @source_fixture Path.expand("../../fixtures/simple_project", __DIR__)
  @project_dir Path.expand("../../tmp/platform_static_branch_project", __DIR__)
  @out_dir Path.expand("../../tmp/platform_static_branch_codegen", __DIR__)

  setup do
    File.rm_rf!(@project_dir)
    File.rm_rf!(@out_dir)
    File.mkdir_p!(Path.dirname(@project_dir))
    File.cp_r!(@source_fixture, @project_dir)

    File.write!(Path.join(@project_dir, "src/Main.elm"), source())

    assert {:ok, _result} =
             Elmc.compile(@project_dir, %{
               out_dir: @out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    :ok
  end

  test "displayShapeIsRound if emits PBL_ROUND preprocessor branches" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "#if defined(PBL_ROUND)"
    assert view_body =~ "#else"
    assert view_body =~ "#endif"
    assert view_body =~ "direct_native_record_branch__then_cell_0 = 20"
    assert view_body =~ "direct_native_record_branch__else_cell_0 = 28"
    refute view_body =~ "native_union_subject_"
    refute view_body =~ "if (native_b_"
  end

  test "colorCapabilityIsColor if emits PBL_COLOR preprocessor branches" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "#if defined(PBL_COLOR)"
    assert view_body =~ "ELMC_RENDER_OP_FILL_RECT"
    assert view_body =~ "ELMC_RENDER_OP_RECT"
    refute view_body =~ "if (native_b_"
    refute view_body =~ "native_union_subject_"
  end

  defp source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { displayShape : Platform.DisplayShape
        , colorCapability : Platform.ColorCapability
        , screenW : Int
        , screenH : Int
        }

    type alias BoardLayout =
        { x : Int, y : Int, cell : Int, gap : Int }

    type Msg
        = Noop

    main : Platform.Program Msg Model ()
    main =
        Platform.worker
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }

    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init context =
        ( { displayShape = context.screen.shape
          , colorCapability = context.screen.colorMode
          , screenW = context.screen.width
          , screenH = context.screen.height
          }
        , Cmd.none
        )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )

    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none

    boardLayout : Model -> BoardLayout
    boardLayout model =
        if Platform.displayShapeIsRound model.displayShape then
            { x = 0, y = 0, cell = 20, gap = 2 }
        else
            { x = 10, y = 26, cell = 28, gap = 3 }

    view : Model -> Ui.UiNode
    view model =
        let
            layout =
                boardLayout model
        in
        if Platform.colorCapabilityIsColor model.colorCapability then
            Ui.toUiNode
                [ Ui.fillRect { x = layout.x, y = layout.y, w = layout.cell, h = layout.cell } Color.black
                ]
        else
            Ui.toUiNode
                [ Ui.rect { x = layout.x, y = layout.y, w = layout.cell, h = layout.cell } Color.black
                ]
    """
  end
end
