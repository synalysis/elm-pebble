defmodule Elmc.NativePolarPointTest do
  use ExUnit.Case

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)

  test "fillCircle with record literal center compiles to elmc_render_cmd6" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model = ()

    type Msg = Noop

    init _ = ( (), Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    drawFill cx cy =
        [ Ui.fillCircle { x = cx, y = cy } 3 1 ]

    view _ = Ui.toUiNode (drawFill 10 20)

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_fixture!(source, "polar_record_literal")

    assert generated_c =~ "elmc_render_cmd6(ELMC_RENDER_OP_FILL_CIRCLE"
    refute generated_c =~ ~r/ELMC_RENDER_OP_FILL_CIRCLE[\s\S]{0,300}elmc_tuple2_take\(&owned/
  end

  test "line through pointAt uses elmc_polar_point and elmc_render_cmd6" do
    source = """
    module Main exposing (main)

    import Basics
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model = ()

    type Msg = Noop

    init _ = ( (), Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    pointAt cx cy radius angle =
        let
            theta = toFloat angle * 2 * Basics.pi / 65536
        in
        { x = cx + round (sin theta * toFloat radius)
        , y = cy - round (cos theta * toFloat radius)
        }

    drawLine cx cy =
        [ Ui.line (pointAt cx cy 60 0) (pointAt cx cy 50 0) 1 ]

    view _ = Ui.toUiNode (drawLine 72 84)

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_fixture!(source, "polar_point_at_line")

    assert generated_c =~ "elmc_render_cmd6(ELMC_RENDER_OP_LINE"
    refute generated_c =~ ~r/ELMC_RENDER_OP_LINE[\s\S]{0,400}elmc_tuple2_take\(&owned/
    assert generated_c =~ "elmc_polar_point_x(" or generated_c =~ "elmc_fn_Main_drawLine_native"
  end

  test "let-bound pointAt and moonCenter compile without pointAt calls in native draw hand" do
    source = """
    module Main exposing (main)

    import Basics
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model = ()

    type Msg = Noop

    init _ = ( (), Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    pointAt : Int -> Int -> Int -> Int -> Ui.Point
    pointAt cx cy radius angle =
        let
            theta = toFloat angle * 2 * Basics.pi / 65536
        in
        { x = cx + round (sin theta * toFloat radius)
        , y = cy - round (cos theta * toFloat radius)
        }

    drawHand cx cy radius nowMin moonCy =
        let
            handAngle = 0
            hubR = 4
            moonRingR = 8
            handLen = 50
            tip = pointAt cx cy handLen handAngle
            moonJunction = pointAt cx moonCy moonRingR handAngle
            hubEdge = pointAt cx cy hubR handAngle
            moonCenter = { x = cx, y = moonCy }
        in
        [ Ui.fillCircle moonCenter moonRingR 1
        , Ui.circle moonCenter moonRingR 1
        , Ui.line hubEdge moonJunction 1
        , Ui.line moonJunction tip 1
        , Ui.fillCircle { x = cx, y = cy } hubR 1
        , Ui.circle { x = cx, y = cy } hubR 1
        ]

    view _ = Ui.toUiNode (drawHand 72 84 80 0 40)

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_fixture!(source, "polar_let_bound_hand")

    assert [_, draw_hand_body] =
             Regex.run(
               ~r/static RC elmc_fn_Main_drawHand\(ElmcValue \*\*out, ElmcValue \*\* const args, const int argc\) \{([\s\S]*?)\n\}/,
               generated_c
             )

    assert draw_hand_body =~ "elmc_render_cmd6(ELMC_RENDER_OP_LINE"
    assert draw_hand_body =~ "elmc_polar_point_"
    refute draw_hand_body =~ "pointAt_native"
    refute draw_hand_body =~ "elmc_record_new_values_take"
    refute draw_hand_body =~ "elmc_retain(cx)"
  end

  defp compile_fixture!(source, slug) do
    project_dir = Path.expand("tmp/#{slug}", __DIR__)
    out_dir = Path.expand("tmp/#{slug}_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(@fixture_elm_json))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end
end
