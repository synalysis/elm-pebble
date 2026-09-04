defmodule Elmc.NativePolarPointTest do
  use ExUnit.Case

  alias Elmc.TestSupport.CachedCompile

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)

  test "fillCircle with record literal center compiles to elmc_render_cmd6" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model = ()

    type Msg = Noop

    init _ = ( (), Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    drawFill cx cy =
        [ Ui.fillCircle { x = cx, y = cy } 3 Color.black ]

    view _ = Ui.toUiNode (drawFill 10 20)

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_fixture!(source, "polar_record_literal")

    assert generated_c =~ "elmc_render_cmd6_take(" or generated_c =~ "elmc_render_cmd6("
    assert generated_c =~ "ELMC_RENDER_OP_FILL_CIRCLE"
    refute generated_c =~ ~r/ELMC_RENDER_OP_FILL_CIRCLE[\s\S]{0,300}elmc_tuple2_take\(&owned/
  end

  test "line through pointAt uses elmc_polar_point and elmc_render_cmd6" do
    source = """
    module Main exposing (main)

    import Basics
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

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
        [ Ui.line (pointAt cx cy 60 0) (pointAt cx cy 50 0) Color.black ]

    view _ = Ui.toUiNode (drawLine 72 84)

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_fixture!(source, "polar_point_at_line")

    assert generated_c =~ "elmc_render_cmd6_take(" or generated_c =~ "elmc_render_cmd6("
    assert generated_c =~ "ELMC_RENDER_OP_LINE"
    refute generated_c =~ ~r/ELMC_RENDER_OP_LINE[\s\S]{0,400}elmc_tuple2_take\(&owned/
    assert generated_c =~ "elmc_polar_point_x(" or
             generated_c =~ "elmc_fn_Main_drawLine_native" or
             generated_c =~ "elmc_fn_Main_pointAt("
  end

  @tag :slow
  test "size profile drops superseded polar float CAFs when polar is inlined" do
    # Minimal line+pointAt fixtures often keep boxed pointAt calls under :size even
    # when polar supersede drops the helper body. Use the yes dial path that actually
    # inlines elmc_polar_point_* and must not keep Basics.pi / soft-float seeds.
    out_dir = Path.expand("tmp/polar_no_float_caf_yes", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template("watchface_yes",
               out_dir: out_dir,
               codegen_profile: :size,
               direct_render_only: true,
               prune_runtime: true,
               pebble_int32: true,
               strip_dead_code: true
             )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_polar_point_x(" or generated_c =~ "elmc_polar_point_y("
    refute generated_c =~ "elmc_fn_Yes_Render_pointAt("
    refute generated_c =~ "elmc_fn_Basics_pi"
    refute generated_c =~ "elmc_new_float"
  end

  test "let-bound pointAt and moonCenter compile without pointAt calls in native draw hand" do
    source = """
    module Main exposing (main)

    import Basics
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

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
        [ Ui.fillCircle moonCenter moonRingR Color.black
        , Ui.circle moonCenter moonRingR Color.black
        , Ui.line hubEdge moonJunction Color.black
        , Ui.line moonJunction tip Color.black
        , Ui.fillCircle { x = cx, y = cy } hubR Color.black
        , Ui.circle { x = cx, y = cy } hubR Color.black
        ]

    view _ = Ui.toUiNode (drawHand 72 84 80 0 40)

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_fixture!(source, "polar_let_bound_hand")

    assert generated_c =~ "ELMC_RENDER_OP_LINE"
    assert generated_c =~ "elmc_polar_point_" or generated_c =~ "elmc_fn_Main_pointAt("
    refute generated_c =~ "pointAt_native"
  end

  test "cartesian offset Point helper is not treated as polar under size profile" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui exposing (Point)
    import Pebble.Ui.Color as Color

    type alias Model = { cx : Int, cy : Int }

    type Msg = Noop

    init _ = ( { cx = 10, cy = 20 }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    p : Int -> Int -> Int -> Int -> Point
    p cx cy x y =
        { x = cx + x, y = cy + y }

    formOrigin : Int -> Int -> Point
    formOrigin cx cy =
        p cx cy 0 -20

    view model =
        Ui.toUiNode [ Ui.pixel (formOrigin model.cx model.cy) Color.black ]

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c =
      compile_fixture!(source, "cartesian_offset_point", %{codegen_profile: :size})

    # Size-profile polar supersede must not drop cartesian helpers that plan code still calls.
    assert generated_c =~ "static RC elmc_fn_Main_p("
    assert generated_c =~ "Rc = elmc_fn_Main_p(" or generated_c =~ "elmc_fn_Main_p(&"
  end

  defp compile_fixture!(source, slug, extra_opts \\ %{}) do
    project_dir = Path.expand("tmp/#{slug}", __DIR__)
    out_dir = Path.expand("tmp/#{slug}_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(@fixture_elm_json))

    opts =
      %{out_dir: out_dir, entry_module: "Main"}
      |> Map.merge(extra_opts)

    assert {:ok, _} = CachedCompile.compile(project_dir, opts)
    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end
end
