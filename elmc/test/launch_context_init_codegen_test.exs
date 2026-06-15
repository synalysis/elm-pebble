defmodule Elmc.LaunchContextInitCodegenTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)

  test "mixed record literal boxes launch context screen ints via ELMC_RECORD_GET_INDEX_INT" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { cells : List Int
        , screenW : Int
        , screenH : Int
        , displayShape : Platform.DisplayShape
        }

    emptyBoard : List Int
    emptyBoard =
        List.repeat 16 0

    init : Platform.LaunchContext -> ( Model, Platform.Cmd Msg )
    init context =
        ( { cells = emptyBoard
          , screenW = context.screen.width
          , screenH = context.screen.height
          , displayShape = context.screen.shape
          }
        , Platform.Cmd.none
        )

    type Msg = Noop
    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.clear Color.white |> Ui.toUiNode
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/launch_context_init_codegen", __DIR__)
    out_dir = Path.expand("tmp/launch_context_init_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(@fixture_elm_json))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true
             })

    init_body = CCodegenExtract.fn_impl_body(File.read!(Path.join(out_dir, "c/elmc_generated.c")), "elmc_fn_Main_init")

    assert init_body =~ "elmc_new_int_take(ELMC_RECORD_GET_INDEX_INT("

    assert length(
             Regex.scan(
               ~r/elmc_record_get_index\(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN\)/,
               init_body
             )
           ) == 1

    refute length(
             Regex.scan(
               ~r/ELMC_RECORD_GET_INDEX_INT\(ELMC_RECORD_GET_INDEX\(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN\)/,
               init_body
             )
           ) > 1
  end
end
