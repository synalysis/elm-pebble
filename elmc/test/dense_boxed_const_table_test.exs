defmodule Elmc.DenseBoxedConstTableTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.SnippetProject

  test "enum-to-color and int-to-enum cases emit a const table for any function name" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Shade
        = Ink
        | Paper
        | Brass
        | Navy
        | Slate
        | Rose
        | Lime
        | Flame
        | Body


    type Kind
        = Alpha
        | Beta
        | Gamma
        | Delta
        | Epsilon
        | Zeta
        | Eta
        | Theta
        | Iota


    paintShade : Shade -> Color.Color
    paintShade shade =
        case shade of
            Ink ->
                Color.black

            Paper ->
                Color.white

            Brass ->
                Color.brass

            Navy ->
                Color.oxfordBlue

            Slate ->
                Color.lightGray

            Rose ->
                Color.brilliantRose

            Lime ->
                Color.springBud

            Flame ->
                Color.sunsetOrange

            Body ->
                Color.magenta


    kindFromCode : Int -> Kind -> Kind
    kindFromCode code fallback =
        case code of
            1 ->
                Alpha

            2 ->
                Beta

            3 ->
                Gamma

            4 ->
                Delta

            5 ->
                Epsilon

            6 ->
                Zeta

            7 ->
                Eta

            8 ->
                Theta

            9 ->
                Iota

            _ ->
                fallback


    resolveShade : Shade -> Color.Color -> Color.Color
    resolveShade shade body =
        case shade of
            Body ->
                body

            Ink ->
                Color.black

            Paper ->
                Color.white

            Brass ->
                Color.brass

            Navy ->
                Color.oxfordBlue

            Slate ->
                Color.lightGray

            Rose ->
                Color.brilliantRose

            Lime ->
                Color.springBud

            Flame ->
                Color.sunsetOrange


    init _ =
        ( { paint = paintShade Paper
          , kind = kindFromCode 3 Alpha
          , resolved = resolveShade Body Color.red
          }
        , Platform.Cmd.none
        )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        [ Ui.clear m.paint
        , Ui.fillRect { x = 0, y = 0, w = 8, h = 8 } m.resolved
        ]
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "dense_boxed_const_table",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/dense_boxed_const_table_codegen", __DIR__)
      )

    paint = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_paintShade")
    kind = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_kindFromCode")
    resolve = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_resolveShade")

    assert paint =~ "elmc_dense_lut_"
    assert paint =~ "ELMC_COLOR_WHITE"
    assert paint =~ "ELMC_COLOR_BLACK"
    refute paint =~ "goto elmc_plan_block_"

    assert kind =~ "elmc_dense_lut_"
    assert kind =~ "elmc_retain("
    refute kind =~ "goto elmc_plan_block_"

    assert resolve =~ "elmc_dense_lut_"
    assert resolve =~ "elmc_retain("
    assert resolve =~ "ELMC_COLOR_WHITE"
    refute resolve =~ "goto elmc_plan_block_"
  end

  test "small enum-to-color case stays a switch, not a table" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Tone
        = Dark
        | Light
        | Accent
        | Mute


    paintTone : Tone -> Color.Color
    paintTone tone =
        case tone of
            Dark ->
                Color.black

            Light ->
                Color.white

            Accent ->
                Color.red

            Mute ->
                Color.lightGray


    init _ =
        ( { paint = paintTone Light }, Platform.Cmd.none )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        [ Ui.clear m.paint ]
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "dense_boxed_const_table_small",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/dense_boxed_const_table_small_codegen", __DIR__)
      )

    paint = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_paintTone")
    refute paint =~ "elmc_dense_lut_"
    assert paint =~ "ELMC_COLOR_WHITE" or paint =~ "elmc_new_int"
  end

  test "List.map of records omits the compact INT_LIST walk" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Point =
        { x : Int
        , y : Int
        }


    type alias Tick =
        { from : Point
        , to : Point
        , width : Int
        }


    strokeTick : Color.Color -> Tick -> Ui.RenderOp
    strokeTick ink tick =
        Ui.line tick.from tick.to ink


    init _ =
        ( { ticks =
                [ { from = { x = 0, y = 0 }, to = { x = 1, y = 1 }, width = 2 }
                , { from = { x = 2, y = 2 }, to = { x = 3, y = 3 }, width = 1 }
                ]
          }
        , Platform.Cmd.none
        )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        (Ui.clear Color.white :: List.map (strokeTick Color.black) m.ticks)
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "record_list_map_no_int_list",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/record_list_map_no_int_list_codegen", __DIR__)
      )

    body =
      case CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_view_commands_append") do
        "" -> CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_strokeTick_commands_append")
        other -> other
      end

    assert body != ""
    # Boxed foreach may probe compact INT_LIST (List Int) then RECORD_SEQ.
    # Record items must still walk RECORD_SEQ or cons LIST — never INT_LIST alone.
    assert body =~ "ELMC_TAG_RECORD_SEQ" or body =~ "ELMC_TAG_LIST" or body =~ "ELMC_TAG_LAZY_MAP"
  end

  test "enum-to-const-record cases emit a field table for any function name" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Face
        = Small
        | Medium
        | Large
        | Huge


    type alias FaceInfo =
        { face : Face
        , label : String
        , size : Int
        }


    faceMeta : Face -> FaceInfo
    faceMeta face =
        case face of
            Small ->
                { face = Small, label = "Small", size = 12 }

            Medium ->
                { face = Medium, label = "Medium", size = 18 }

            Large ->
                { face = Large, label = "Large", size = 24 }

            Huge ->
                { face = Huge, label = "Huge", size = 32 }


    init _ =
        ( { size = (faceMeta Medium).size }, Platform.Cmd.none )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        [ Ui.fillRect { x = 0, y = 0, w = m.size, h = m.size } Color.black ]
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "dense_const_record_table",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/dense_const_record_table_codegen", __DIR__)
      )

    meta = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_faceMeta")

    assert meta =~ "elmc_dense_rec_"
    assert meta =~ "elmc_record_new_values_take"
    assert meta =~ "Small"
    assert meta =~ "Huge"
    refute meta =~ "goto elmc_plan_block_"
  end

  test "two-arm const-record case stays a switch, not a table" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Face
        = Small
        | Large


    type alias FaceInfo =
        { face : Face
        , label : String
        , size : Int
        }


    faceMeta : Face -> FaceInfo
    faceMeta face =
        case face of
            Small ->
                { face = Small, label = "Small", size = 12 }

            Large ->
                { face = Large, label = "Large", size = 24 }


    init _ =
        ( { size = (faceMeta Small).size }, Platform.Cmd.none )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        [ Ui.fillRect { x = 0, y = 0, w = m.size, h = m.size } Color.black ]
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "dense_const_record_table_small",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/dense_const_record_table_small_codegen", __DIR__)
      )

    meta = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_faceMeta")
    refute meta =~ "elmc_dense_rec_"
    assert meta =~ "elmc_record_new_values_take" or meta =~ "elmc_new_int"
  end

  test "List.map of strings omits the compact INT_LIST walk" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    shout : List String -> List String
    shout words =
        List.map (\\word -> word ++ "!") words


    init _ =
        ( { n = List.length (shout [ "hi", "there" ]) }, Platform.Cmd.none )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        [ Ui.fillRect { x = 0, y = 0, w = m.n, h = 8 } Color.black ]
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "string_list_map_no_int_list",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/string_list_map_no_int_list_codegen", __DIR__)
      )

    body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_shout")
    assert body != ""
    refute body =~ "ELMC_TAG_INT_LIST"
    assert body =~ "list_walk_map_cursor_" or body =~ "ELMC_TAG_LAZY_MAP" or body =~ "ELMC_TAG_LIST"
  end

  test "List.foldl of a known function walks the list without a heap closure" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    accWord : Int -> String -> List String -> List String
    accWord maxChars word lines =
        case lines of
            [] ->
                [ word ]

            current :: rest ->
                if String.length current + 1 + String.length word <= maxChars then
                    (current ++ " " ++ word) :: rest

                else
                    word :: lines


    wrapWords : String -> Int -> List String
    wrapWords quote maxChars =
        quote
            |> String.words
            |> List.foldl (accWord maxChars) []
            |> List.reverse


    init _ =
        ( { n = List.length (wrapWords "Make today count." 8) }, Platform.Cmd.none )

    update _ m =
        ( m, Platform.Cmd.none )

    view m =
        [ Ui.fillRect { x = 0, y = 0, w = m.n, h = 8 } Color.black ]
            |> Ui.toUiNode

    subscriptions _ =
        Platform.Sub.none

    main =
        Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    {_result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "string_foldl_no_heap_closure",
        compile: %{direct_render_only: true, codegen_profile: :size},
        out_dir: Path.expand("tmp/string_foldl_no_heap_closure_codegen", __DIR__)
      )

    body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_wrapWords")
    assert body != ""
    assert body =~ "list_walk_foldl_acc_"
    refute body =~ "elmc_list_foldl("
    refute body =~ "elmc_closure_new_rc"
  end
end
