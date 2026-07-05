defmodule Elmc.Backend.CCodegen.PlatformStaticBoolFoldTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

  @source_fixture Path.expand("../../fixtures/simple_project", __DIR__)
  @project_dir Path.expand("../../tmp/platform_static_bool_fold_project", __DIR__)
  @out_dir Path.expand("../../tmp/platform_static_bool_fold_codegen", __DIR__)

  @moduletag :sequential

  setup do
    File.rm_rf(@project_dir)
    File.rm_rf(@out_dir)
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

  test "showCorners-style guard keeps sun check only on non-round builds" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_showCorners_native")

    assert body =~ "#if defined(PBL_ROUND)"
    assert body =~ "bool native_bool_if_3"
    assert body =~ "#if defined(PBL_ROUND)\n    native_bool_if_3 = false;"
    assert body =~ "#else"
    assert body =~ "ELMC_TAG_MAYBE"
    refute body =~ ~r/#if defined\(PBL_ROUND\)\s*\n\s*const bool native_bool_if_3 = false;\s*\n#else[\s\S]*#else/
    refute body =~ "native_union_subject_"
  end

  test "view corner ops are emitted only for non-round builds" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "#if defined(PBL_ROUND)"
    assert view_body =~ "#else"
    assert view_body =~ "ELMC_RENDER_OP_RECT"
    refute view_body =~ ~r/#if defined\(PBL_ROUND\)\s*\n#else\s*\n\s*#endif/
    refute view_body =~ ~r/#if defined\(PBL_ROUND\)[^\n]*\n[^\n]*ELMC_RENDER_OP_RECT/
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
        , sun : Maybe Int
        }

    type Msg
        = Noop

    showCorners : Model -> Bool
    showCorners model =
        not (Platform.displayShapeIsRound model.displayShape)
            && model.sun /= Nothing

    init context =
        ( { displayShape = context.screen.shape, sun = Just 1 }
        , Platform.Cmd.none
        )

    update _ model =
        ( model
        , if showCorners model then
            Platform.Cmd.none

          else
            Platform.Cmd.none
        )

    subscriptions _ =
        Platform.Sub.none

    view model =
        Ui.toUiNode
            (if not (Platform.displayShapeIsRound model.displayShape) && model.sun /= Nothing then
                [ Ui.rect { x = 0, y = 0, w = 8, h = 8 } Color.black ]

             else
                []
            )

    main =
        Platform.worker
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }
    """
  end
end
