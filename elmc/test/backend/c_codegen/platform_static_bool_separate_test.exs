defmodule Elmc.Backend.CCodegen.PlatformStaticBoolSeparateTest do
  use ExUnit.Case, async: true

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Test.CCodegenExtract

  @source_fixture Path.expand("../../fixtures/simple_project", __DIR__)
  @project_dir Path.expand("../../tmp/platform_static_bool_separate_project", __DIR__)
  @out_dir Path.expand("../../tmp/platform_static_bool_separate_codegen", __DIR__)

  @moduletag :sequential

  setup do
    File.rm_rf(@project_dir)
    File.rm_rf(@out_dir)
    File.mkdir_p!(Path.dirname(@project_dir))
    File.cp_r!(@source_fixture, @project_dir)

    File.write!(Path.join(@project_dir, "src/Main.elm"), source())

    assert {:ok, _result} =
             CachedCompile.compile(@project_dir, %{
               out_dir: @out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    :ok
  end

  test "colorCapabilityIsColor lowers as bool, not int 0/1" do
    generated_c = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert body =~ "#if defined(PBL_COLOR)"
    assert body =~ ~r/\btrue\b/
    assert body =~ ~r/\bfalse\b/
    assert body =~ "const bool"

    refute body =~ "elmc_new_int"
    refute body =~ ~r/elmc_new_bool\([^)]*,\s*[01]\s*\)/
    refute body =~ ~r/elmc_as_bool\([^)]+\)\s*==\s*0/
    refute body =~ ~r/elmc_as_bool\([^)]+\)\s*!=\s*0/
    refute body =~ ~r/elmc_as_int\([^)]+\)\s*!=\s*0/
  end

  defp source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        { colorCapability : Platform.ColorCapability }

    type Msg
        = Noop

    backgroundColor : Platform.ColorCapability -> Color.Color
    backgroundColor colorCapability =
        if Platform.colorCapabilityIsColor colorCapability then
            Color.black

        else
            Color.white

    init context =
        ( { colorCapability = context.screen.colorMode }
        , Platform.Cmd.none
        )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view model =
        Ui.toUiNode
            [ Ui.fillRect { x = 0, y = 0, w = 8, h = 8 } (backgroundColor model.colorCapability) ]

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
