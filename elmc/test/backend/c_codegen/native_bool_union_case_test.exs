defmodule Elmc.Backend.CCodegen.NativeBoolUnionCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

  @source_fixture Path.expand("../../fixtures/simple_project", __DIR__)
  @project_dir Path.expand("../../tmp/native_bool_union_case_project", __DIR__)
  @out_dir Path.expand("../../tmp/native_bool_union_case_codegen", __DIR__)

  setup do
    File.rm_rf!(@project_dir)
    File.rm_rf!(@out_dir)
    File.mkdir_p!(Path.dirname(@project_dir))
    File.cp_r!(@source_fixture, @project_dir)

    File.write!(
      Path.join(@project_dir, "src/Main.elm"),
      """
      module Main exposing (main)

      import Pebble.Platform as Platform
      import Pebble.Ui as Ui

      type alias Model =
          { displayShape : Platform.DisplayShape
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
              { x = 1, y = 2, cell = 10, gap = 2 }
          else
              { x = 3, y = 4, cell = 11, gap = 3 }

      view : Model -> Ui.UiNode
      view model =
          let
              layout =
                  boardLayout model
          in
          Ui.toUiNode
              [ Ui.fillRect { x = layout.x, y = layout.y, w = layout.cell, h = layout.cell } Color.black
              ]
      """
    )

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

  test "displayShapeIsRound if in view uses PBL_ROUND preprocessor branches" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "#if defined(PBL_ROUND)"
    refute view_body =~ "native_union_subject_"
    refute view_body =~ "if (native_b_"
    refute view_body =~ "tmp_2 = elmc_new_int(1)"
  end

  test "boardLayout uses PBL_ROUND preprocessor branches without runtime shape check" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "#if defined(PBL_ROUND)"
    assert view_body =~ "direct_native_record_branch__then_cell_0 = 10"
    assert view_body =~ "direct_native_record_branch__else_cell_0 = 11"
    refute view_body =~ "native_union_subject_"
    refute view_body =~ "if (native_b_"
  end

  test "lte-style bool conditions compile to native bool without boxed temps" do
    project_dir = Path.expand("../../tmp/native_bool_lte_project", __DIR__)
    out_dir = Path.expand("../../tmp/native_bool_lte_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp_r!(@source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (main)

      import Json.Decode as Decode
      import Pebble.Platform as Platform
      import Pebble.Ui as Ui

      type alias Model = { n : Int }
      type Msg = Noop

      randomIndex : Int -> Int -> Int
      randomIndex maxExclusive seed =
          if maxExclusive <= 0 then
              0
          else
              modBy maxExclusive seed

      init _ = ( { n = randomIndex 10 0 }, Cmd.none )
      update _ m = ( m, Cmd.none )
      subscriptions _ = Sub.none
      view _ = Ui.windowStack []
      main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
      """
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_body =
      generated_c
      |> String.split(
        "static elmc_int_t elmc_fn_Main_randomIndex_native(const elmc_int_t maxExclusive, const elmc_int_t seed) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_init", parts: 2)
      |> hd()

    assert native_body =~ "bool native_bool_if_"
    assert native_body =~ "if ((maxExclusive < 0))"
    assert native_body =~ "native_bool_if_"
    assert native_body =~ " = true;"
    assert native_body =~ "(maxExclusive == 0)"
    refute native_body =~ "elmc_new_int(1)"
    refute native_body =~ "elmc_as_int(tmp_"
    refute Regex.match?(~r/ElmcValue \*tmp_\d+;\s+if \(\(maxExclusive < 0\)\)/, native_body)
  end
end
