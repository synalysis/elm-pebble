defmodule Elmc.Backend.CCodegen.StaticStringFoldTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.StaticString
  alias Elmc.Test.CCodegenExtract

  @source_fixture Path.expand("../../fixtures/simple_project", __DIR__)
  @project_dir Path.expand("../../tmp/static_string_fold_project", __DIR__)
  @out_dir Path.expand("../../tmp/static_string_fold_codegen", __DIR__)

  test "fold_append_literals merges adjacent literal segments" do
    expr =
      %{
        op: :call,
        name: "__append__",
        args: [
          %{op: :string_literal, value: "2048"},
          %{
            op: :call,
            name: "__append__",
            args: [
              %{op: :string_literal, value: "  "},
              %{
                op: :call,
                name: "__append__",
                args: [
                  %{op: :string_literal, value: "Best "},
                  %{op: :var, name: "score"}
                ]
              }
            ]
          }
        ]
      }

    assert %{
             op: :call,
             name: "__append__",
             args: [
               %{op: :string_literal, value: "2048  Best "},
               %{op: :var, name: "score"}
             ]
           } = StaticString.fold_append_literals(expr)
  end

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
               direct_render_only: true
             })

    :ok
  end

  test "direct render folds literal string chains into one text prefix" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_text_prefix_and_nonzero_int(scene_cmd.text, \"2048  Best \","
    refute view_body =~ "native_string_buf_"
    refute view_body =~ "const char *native_string_buf_24_left = \"  \";"
  end

  defp source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources

    type alias Model =
        { best : Int
        , displayShape : Platform.DisplayShape
        }

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
        ( { best = 42
          , displayShape = context.screen.shape
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
        if Platform.displayShapeIsRound model.displayShape then
            Ui.toUiNode
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 0, y = 0, w = 100, h = 20 }
                    ("2048" ++ "  " ++ "Best " ++ String.fromInt model.best)
                ]
        else
            Ui.toUiNode
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 0, y = 0, w = 100, h = 20 }
                    ("2048" ++ "  " ++ "Best " ++ String.fromInt model.best)
                ]
    """
  end
end
