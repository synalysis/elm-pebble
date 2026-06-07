defmodule Elmc.CCodegenPatternsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Patterns

  @just_payload_borrow "elmc_maybe_or_tuple_just_payload_borrow"

  test "maybe_unwrap_just_case? recognizes Nothing + bare var branches" do
    branches = [
      %{pattern: %{kind: :constructor, name: "Nothing", bind: nil, arg_pattern: nil}},
      %{pattern: %{kind: :var, name: "piece"}}
    ]

    assert Patterns.maybe_unwrap_just_case?(branches)
    refute Patterns.maybe_unwrap_just_case?([%{pattern: %{kind: :var, name: "piece"}}])
  end

  test "bind_pattern unwraps bare var in Nothing + var Maybe cases" do
    env = Map.put(%{}, :maybe_unwrap_just, true)

    bound =
      env
      |> Patterns.bind_pattern(%{kind: :var, name: "piece"}, "tmp_subject")
      |> Map.fetch!("piece")

    assert bound == "elmc_maybe_or_tuple_just_payload_borrow(tmp_subject)"
  end

  test "bind_pattern leaves bare var unwrapped outside Maybe Nothing + var cases" do
    bound =
      %{}
      |> Patterns.bind_pattern(%{kind: :var, name: "piece"}, "tmp_subject")
      |> Map.fetch!("piece")

    assert bound == "tmp_subject"
  end

  test "Nothing + bare var case codegen uses Just payload for field access" do
    branches = [
      %{
        pattern: %{kind: :constructor, name: "Nothing", bind: nil, arg_pattern: nil},
        expr: %{op: :int_literal, value: 0}
      },
      %{
        pattern: %{kind: :var, name: "piece"},
        expr: %{op: :field_access, arg: %{op: :var, name: "piece"}, field: "y"}
      }
    ]

    case_expr = %{op: :case, subject: "maybePiece", branches: branches}
    env = %{"maybePiece" => "tmp_subject"}

    {code, _out, _counter} = CaseCompile.dispatch(case_expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ @just_payload_borrow
    refute source =~ "elmc_record_get(tmp_subject, \"y\")"
    refute source =~ "elmc_record_get(maybePiece, \"y\")"

    assert Regex.scan(~r/elmc_maybe_or_tuple_just_payload_borrow\(tmp_subject\)/, source)
           |> length() == 1

    assert source =~ "elmc_record_get(tmp_"
    refute source =~ ~r/elmc_release\(tmp_\d+\);\s*\n\s*\}\s*\n\s*elmc_release\(tmp_2\)/
  end

  test "direct fragment vars allocate retain temp after fragment temps" do
    env = %{
      "fragment" => {:direct_fragment, %{op: :int_literal, value: 42}}
    }

    {code, out, counter} = FunctionCallCompile.compile_var("fragment", env, 0)

    assert out == "tmp_2"
    assert counter == 2
    assert code =~ "ElmcValue *tmp_1 = elmc_new_int(42);"
    assert code =~ "ElmcValue *tmp_2 = elmc_retain(tmp_1);"
    refute code =~ ~r/ElmcValue \*tmp_1 = elmc_retain\(tmp_1\);/
  end

  test "game elmtris template dropStep does not read record fields from Maybe wrapper" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/game_elmtris_maybe_case", __DIR__)
    out_dir = Path.expand("tmp/game_elmtris_maybe_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(elmtris_main))

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_dropStep"
    assert generated_c =~ @just_payload_borrow
    refute generated_c =~ "elmc_fn_Main_canPlace_offset_fits"
    refute generated_c =~ "elmc_list_drop("
    refute generated_c =~ ~r/elmc_record_get\(tmp_2, "y"\)/
    refute generated_c =~ ~r/elmc_record_get\(tmp_2, "kind"\)/
    refute generated_c =~ ~r/rec_names_\d+\[5\] = \{ "cell", "gap", "pieceKind"/

    stack_report = File.read!(Path.join(out_dir, "elmc_stack_report.json"))
    assert stack_report =~ "\"functions\""
    assert stack_report =~ "\"summary\""
    assert stack_report =~ "\"code_size_indicators\""
    assert generated_c =~ "elmc_list_from_tuple2_int_array"
    assert generated_c =~ "pieceOffsets_table[k][r]"
    refute generated_c =~ "elmc_fn_Pebble_Ui_Resources_DefaultFont"
    assert generated_c =~ "elmc_scene_writer_push_cmd(writer, &scene_cmd)"
    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT)"
    assert generated_c =~ ~r/scene_cmd\.p0 = 1;\s*\n\s*scene_cmd\.p1 = direct_native_let_textX_\d+;/
    refute generated_c =~ ~r/scene_cmd\.p1 = elmc_as_int\(tmp_\d+\)/
  end

  test "List.all with (/=) 0 uses cursor loop instead of elmc_list_all closure" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    rowHasValue : List Int -> Bool
    rowHasValue values =
        List.all ((/=) 0) values

    init _ = ( { ok = rowHasValue [ 1, 2, 0 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (if m.ok then "yes" else "no") ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_all_neq_zero", __DIR__)
    out_dir = Path.expand("tmp/list_all_neq_zero_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_hof_cursor_"
    assert generated_c =~ "elmc_fn_Main_rowHasValue"
    refute generated_c =~ "elmc_list_all("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "List.foldl over range with list acc uses cursor loop instead of elmc_list_foldl closure" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    collect : List Int -> List Int
    collect values =
        List.foldl
            (\\index picked ->
                if index == 0 then
                    picked

                else
                    index :: picked
            )
            []
            (List.range 0 3)

    init _ = ( { picked = collect [] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.picked)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_foldl_range_list_acc", __DIR__)
    out_dir = Path.expand("tmp/list_foldl_range_list_acc_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_foldl_i_"
    assert generated_c =~ "elmc_fn_Main_collect"
    refute generated_c =~ "elmc_list_foldl("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "List.filter with (/=) 0 uses cursor loop instead of elmc_list_filter closure" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    nonzero : List Int -> List Int
    nonzero values =
        List.filter ((/=) 0) values

    init _ = ( { kept = nonzero [ 0, 2, 0, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.kept)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_filter_neq_zero", __DIR__)
    out_dir = Path.expand("tmp/list_filter_neq_zero_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_filter_cursor_"
    assert generated_c =~ "elmc_fn_Main_nonzero"
    refute generated_c =~ "elmc_list_filter("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "List.filterMap over range with if then Nothing else Just uses cursor loop" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    keepSmall : List Int -> List Int
    keepSmall values =
        List.range 0 3
            |> List.filterMap
                (\\n ->
                    if n > 1 then
                        Nothing

                    else
                        Just (n * 10)
                )

    init _ = ( { kept = keepSmall [] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.kept)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_filter_map_range", __DIR__)
    out_dir = Path.expand("tmp/list_filter_map_range_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_filter_map_i_"
    assert generated_c =~ "elmc_fn_Main_keepSmall"
    refute generated_c =~ "elmc_list_filter_map("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "List.repeat with literal count inlines loop instead of elmc_list_repeat_count" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    blankRow : List Int
    blankRow =
        List.repeat 4 0

    init _ = ( { row = blankRow }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.row)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_repeat_inline", __DIR__)
    out_dir = Path.expand("tmp/list_repeat_inline_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_repeat_i_"
    assert generated_c =~ "elmc_fn_Main_blankRow"
    refute generated_c =~ "elmc_list_repeat_count("
    refute generated_c =~ "elmc_list_repeat("
  end

  test "List.length inlines cursor count instead of elmc_list_length" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    countItems : List Int -> Int
    countItems items =
        List.length items

    init _ = ( { n = countItems [ 1, 2, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_length_inline", __DIR__)
    out_dir = Path.expand("tmp/list_length_inline_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_length_cursor_"
    assert generated_c =~ "elmc_fn_Main_countItems"
    refute generated_c =~ "elmc_list_length("
  end

  test "List.repeat with boxed int count and top-level constant inlines loop" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    width : Int
    width =
        4

    padRows : List Int -> List Int
    padRows kept =
        let
            cleared =
                6 - List.length kept
        in
        List.repeat cleared (List.repeat width 0)

    init _ = ( { rows = padRows [ 1, 2, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.rows)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_repeat_boxed_count", __DIR__)
    out_dir = Path.expand("tmp/list_repeat_boxed_count_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_repeat_i_"
    assert generated_c =~ "elmc_fn_Main_padRows"
    assert generated_c =~ ~r/list_repeat_i_\d+ < \(6 - list_length_count_/
    refute generated_c =~ ~r/list_repeat_i_\d+ < elmc_as_int\(tmp_/
    refute generated_c =~ "elmc_list_repeat_count("
    refute generated_c =~ "elmc_list_repeat("
  end

  test "hybrid int let uses native List.repeat bound when count is also returned boxed" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    padAndCount : List Int -> ( List Int, Int )
    padAndCount kept =
        let
            cleared =
                6 - List.length kept
        in
        ( List.repeat cleared 0 ++ kept, cleared )

    init _ = ( { rows = padAndCount [ 1, 2, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m =
        Ui.toUiNode
            [ Ui.clear Color.white
            , Ui.text (String.fromInt (List.length (Tuple.first m.rows)))
            ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/hybrid_int_let_repeat", __DIR__)
    out_dir = Path.expand("tmp/hybrid_int_let_repeat_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_padAndCount"
    assert generated_c =~ ~r/list_repeat_i_\d+ < \(6 - list_length_count_/
    refute generated_c =~ ~r/list_repeat_i_\d+ < elmc_as_int\(tmp_/
    assert generated_c =~ "elmc_tuple2_take("
  end

  test "List.foldl over range piped to List.reverse uses descending loop without elmc_list_reverse" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    collect : List Int
    collect =
        List.foldl
            (\\index picked ->
                if index == 0 then
                    picked

                else
                    index :: picked
            )
            []
            (List.range 0 3)
            |> List.reverse

    init _ = ( { picked = collect }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.picked)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_foldl_reverse", __DIR__)
    out_dir = Path.expand("tmp/list_foldl_reverse_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_foldl_i_"
    assert generated_c =~ "elmc_fn_Main_collect"
    refute generated_c =~ "elmc_list_reverse("
    refute generated_c =~ "elmc_list_foldl("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "native int minus List.length uses cursor count without boxing length" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    height : Int
    height =
        10

    remaining : List Int -> Int
    remaining kept =
        height - List.length kept

    init _ = ( { n = remaining [ 1, 2, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/native_int_sub_length", __DIR__)
    out_dir = Path.expand("tmp/native_int_sub_length_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_length_count_"
    assert generated_c =~ "elmc_fn_Main_remaining"
    assert Regex.match?(
             ~r/elmc_fn_Main_remaining\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_new_int\(10 - list_length_count_/,
             generated_c
           )

    refute Regex.match?(
             ~r/elmc_fn_Main_remaining\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_list_length\(/,
             generated_c
           )

    refute Regex.match?(
             ~r/elmc_fn_Main_remaining\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_fn_Main_height\(/,
             generated_c
           )
  end

  test "List.concat of row segments preserves left-to-right order for collapseRows" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    collapseRows : List Int -> List Int
    collapseRows cells =
        let
            row0 =
                collapseRow (rowAt 0 cells)

            row1 =
                collapseRow (rowAt 1 cells)

            row2 =
                collapseRow (rowAt 2 cells)

            row3 =
                collapseRow (rowAt 3 cells)
        in
        row0.cells ++ row1.cells ++ row2.cells ++ row3.cells

    collapseRow : List Int -> { cells : List Int, score : Int }
    collapseRow row =
        let
            merged =
                merge (List.filter ((/=) 0) row)
        in
        { cells = merged.cells ++ List.repeat (4 - List.length merged.cells) 0
        , score = merged.score
        }

    merge : List Int -> { cells : List Int, score : Int }
    merge values =
        case values of
            a :: b :: rest ->
                if a == b then
                    let
                        tail =
                            merge rest

                        value =
                            a + b
                    in
                    { cells = value :: tail.cells
                    , score = value + tail.score
                    }

                else
                    let
                        tail =
                            merge (b :: rest)
                    in
                    { cells = a :: tail.cells
                    , score = tail.score
                    }

            _ ->
                { cells = values, score = 0 }

    rowAt : Int -> List Int -> List Int
    rowAt row cells =
        List.take 4 (List.drop (row * 4) cells)

    init _ =
        ( { board = collapseRows (setAt 1 2 (setAt 0 2 (List.repeat 16 0))) }
        , Platform.Cmd.none
        )

    setAt : Int -> Int -> List Int -> List Int
    setAt index value cells =
        List.indexedMap (\\i v -> if i == index then value else v) cells

    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.board)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_concat_row_order", __DIR__)
    out_dir = Path.expand("tmp/list_concat_row_order_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_collapseRows"
    assert generated_c =~ "elmc_list_concat("
    assert generated_c =~ "elmc_fn_Main_collapseRow"
  end

  test "List.concat of literal segments flattens without elmc_list_concat" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    mergeRows : List Int -> List Int -> List Int -> List Int
    mergeRows top mid bottom =
        List.concat [ top, mid, bottom ]

    init _ = ( { flat = mergeRows [ 1, 2 ] [ 3 ] [ 4, 5 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.flat)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_concat_literal_segments", __DIR__)
    out_dir = Path.expand("tmp/list_concat_literal_segments_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_mergeRows"
    assert generated_c =~ "elmc_list_concat("
  end

  test "List.concat of List.repeat row append flattens without elmc_list_concat" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    padRows : Int -> Int -> List (List Int) -> List Int
    padRows cleared width kept =
        List.concat (List.repeat cleared (List.repeat width 0) ++ kept)

    init _ = ( { flat = padRows 2 3 [ [ 1, 2, 3 ], [ 4, 5, 6 ] ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.flat)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_concat_flatten", __DIR__)
    out_dir = Path.expand("tmp/list_concat_flatten_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_repeat_i_"
    assert generated_c =~ "elmc_fn_Main_padRows"
    refute generated_c =~ "elmc_list_repeat_count("
    assert generated_c =~ "elmc_list_concat("
  end

  test "List.map with captured env uses cursor loop instead of elmc_list_map closure" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    tagItems : Int -> List Int -> List Int
    tagItems offset items =
        List.map (\\item -> item + offset) items

    init _ = ( { tagged = tagItems 10 [ 1, 2, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.tagged)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_map_captured_env", __DIR__)
    out_dir = Path.expand("tmp/list_map_captured_env_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_map_cursor_"
    assert generated_c =~ "elmc_fn_Main_tagItems"
    refute generated_c =~ "elmc_list_map("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "List.map over tuple2 offsets uses cursor loop instead of elmc_list_map closure" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Piece = { x : Int, y : Int, kind : Int, rot : Int }

    offsets : Int -> Int -> List ( Int, Int )
    offsets _ _ =
        [ ( 0, 0 ), ( 1, 0 ), ( 0, 1 ), ( 1, 1 ) ]

    slots : Piece -> List Int
    slots piece =
        List.map
            (\\( dx, dy ) ->
                (piece.y + dy) * 10 + (piece.x + dx)
            )
            (offsets piece.kind piece.rot)

    init _ = ( { label = slots { x = 3, y = 0, kind = 1, rot = 0 } }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.label)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/tuple_map_cursor", __DIR__)
    out_dir = Path.expand("tmp/tuple_map_cursor_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_map_cursor_"
    assert generated_c =~ "elmc_fn_Main_slots"
    refute generated_c =~ "elmc_list_map("
    refute generated_c =~ "elmc_lambda_"
  end

  test "top-level constant int functions fold to literals without runtime calls" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    width : Int
    width =
        10

    height : Int
    height =
        14

    area : Int
    area =
        width * height

    init _ = ( { n = area }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/constant_int_fold", __DIR__)
    out_dir = Path.expand("tmp/constant_int_fold_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert Regex.match?(
             ~r/elmc_fn_Main_area\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_new_int\(140\)/,
             generated_c
           )

    assert Regex.match?(
             ~r/elmc_fn_Main_init\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?(elmc_new_int\(140\)|rec_values_1\[1\] = \{ 140 \})/,
             generated_c
           )

    refute Regex.match?(
             ~r/elmc_fn_Main_area\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_fn_Main_width\(/,
             generated_c
           )
  end

  test "top-level int constants compile natively in List.range without boxing" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    boardRows : Int
    boardRows =
        14

    rows : List Int
    rows =
        List.range 0 (boardRows - 1)
            |> List.map (\\i -> i)

    init _ = ( { n = List.length rows }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/native_const_range", __DIR__)
    out_dir = Path.expand("tmp/native_const_range_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "for (elmc_int_t list_map_i_"
    assert generated_c =~ "list_map_i_1 = 13"
    refute Regex.match?(
             ~r/elmc_fn_Main_rows\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_new_int\(14\)/,
             generated_c
           )
    refute Regex.match?(
             ~r/elmc_fn_Main_rows\(ElmcValue \*\* const args, const int argc\) \{[\s\S]*?elmc_fn_Main_boardRows\(/,
             generated_c
           )
  end

  test "List.map cursor loop builds list in forward order without elmc_list_reverse" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    double : List Int -> List Int
    double values =
        List.map (\\n -> n + 1) values

    init _ = ( { xs = double [ 1, 2, 3 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.xs)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_map_inline_reverse", __DIR__)
    out_dir = Path.expand("tmp/list_map_inline_reverse_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_map_cursor_"
    assert generated_c =~ "list_fwd_head_"
    assert generated_c =~ "list_fwd_tail_"
    assert generated_c =~ "elmc_fn_Main_double"
    refute generated_c =~ "list_rev_cursor_"
    refute generated_c =~ "elmc_list_reverse("
    refute generated_c =~ "elmc_list_map("
  end

  test "game elmtris init and view run on host pebble shim with basalt launch context" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for elmtris host harness")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/game_elmtris_host", __DIR__)
    out_dir = Path.expand("tmp/game_elmtris_host_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(elmtris_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    makefile = File.read!(Path.join(out_dir, "Makefile"))
    assert makefile =~ "-ffunction-sections"
    assert makefile =~ "-fdata-sections"
    assert makefile =~ "-Wl,--gc-sections"

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "pieceOffsets_table[k][r]"
    refute generated_c =~ "elmc_fn_Main_pieceSlots_native"
    refute generated_c =~ "elmc_fn_Main_canPlace_native"
    refute generated_c =~ "elmc_fn_Main_lockedSlotsFromBoard_native"
    refute generated_c =~ "elmc_fn_Main_clearLines_native"
    refute generated_c =~ "elmc_fn_Main_canPlace_offset_fits"
    refute generated_c =~ "elmc_fn_Main_stampPiece_native"
    refute generated_c =~ "elmc_fn_Main_boardLayout_native"
    refute generated_c =~ "elmc_fn_Main_lockedSlotOps_native"
    refute generated_c =~ "elmc_fn_Main_pieceSlotOps_native"
    refute generated_c =~ "elmc_fn_Main_rotateActive_native"
    refute generated_c =~ "elmc_fn_Main_dropStep_native"
    refute generated_c =~ "elmc_fn_Main_softDrop_native"
    refute generated_c =~ "elmc_fn_Main_spawnPiece_native"
    assert generated_c =~ "elmc_list_concat("
    assert generated_c =~ "record_update_helper_Main_withPiece"
    assert generated_c =~ "elmc_list_replace_nth_int"
    assert generated_c =~
             ~r/elmc_fn_Main_pieceOffsets_native\(const elmc_int_t kind, const elmc_int_t rot\) \{\s*elmc_int_t k = kind % 7;[\s\S]*?pieceOffsets_table\[k\]\[r\];\s*return elmc_list_from_tuple2_int_array/
    refute generated_c =~ "elmc_list_indexed_map("
    refute generated_c =~ "elmc_list_reverse("
    assert generated_c =~ "elmc_let_body_helper_Main_lockPiece"
    assert generated_c =~ "elmc_fn_Main_freshModel("
    assert generated_c =~ "elmc_record_update_helper_Main_lockPiece"

    harness_path = Path.join(out_dir, "c/elmtris_host_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *basalt_launch_context(void) {
        ElmcValue *reason = elmc_new_int(2);
        ElmcValue *watch_model = elmc_new_string("");
        ElmcValue *watch_profile_id = elmc_new_string("");
        ElmcValue *width = elmc_new_int(144);
        ElmcValue *height = elmc_new_int(168);
        ElmcValue *shape = elmc_new_int(2);
        ElmcValue *color_mode = elmc_new_string("Color");
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, shape, width};
        ElmcValue *screen = elmc_record_new_take(4, screen_names, screen_values);
        ElmcValue *has_microphone = elmc_new_int(0);
        ElmcValue *has_compass = elmc_new_int(0);
        ElmcValue *supports_health = elmc_new_int(0);
        const char *names[] = {
          "hasCompass", "hasMicrophone", "reason", "screen",
          "supportsHealth", "watchModel", "watchProfileId"
        };
        ElmcValue *values[] = {
          has_compass, has_microphone, reason, screen,
          supports_health, watch_model, watch_profile_id
        };
        return elmc_record_new_take(7, names, values);
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = basalt_launch_context();
        if (elmc_pebble_init(&app, flags) != 0) {
          fprintf(stderr, "init failed\\n");
          return 2;
        }
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[128] = {0};
        int n = elmc_pebble_view_commands(&app, cmds, 128);
        if (n < 4) {
          fprintf(stderr, "expected view commands, got %d\\n", n);
          return 3;
        }
        ElmcValue *model = elmc_worker_model(&app.worker);
        if (!model || ELMC_RECORD_GET_INDEX_INT(model, 7) < 0) {
          fprintf(stderr, "expected active piece\\n");
          elmc_release(model);
          return 4;
        }
        elmc_release(model);
        elmc_pebble_deinit(&app);
        printf("ok view_commands=%d\\n", n);
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "elmtris_host_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        "-I#{Path.join(out_dir, "ports")}",
        "-I#{Path.join(out_dir, "c")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        Path.join(out_dir, "ports/elmc_ports.c"),
        Path.join(out_dir, "c/elmc_generated.c"),
        Path.join(out_dir, "c/elmc_worker.c"),
        Path.join(out_dir, "c/elmc_pebble.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0, run_out
    assert String.contains?(run_out, "ok view_commands=")
  end

  test "watchface init compiles native model ints, nested screen getters, and cmd macro" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Color as PebbleColor
    import Pebble.Cmd as PebbleCmd

    type alias Model =
        { hour : Int
        , minute : Int
        , screenW : Int
        , screenH : Int
        }

    type Msg
        = CurrentDateTime PebbleCmd.CurrentDateTime

    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init context =
        ( { hour = 12
          , minute = 0
          , screenW = context.screen.width
          , screenH = context.screen.height
          }
        , PebbleCmd.getCurrentDateTime CurrentDateTime
        )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )

    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none

    view : Model -> PebbleUi.UiNode
    view _ =
        PebbleUi.windowStack []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    project_dir = Path.expand("tmp/watchface_init_codegen", __DIR__)
    out_dir = Path.expand("tmp/watchface_init_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert init_body =~ "elmc_record_new_ints"
    refute init_body =~ "elmc_record_new_take"
    assert init_body =~ "ELMC_RECORD_GET_INDEX_INT(ELMC_RECORD_GET_INDEX(context, 3 /* screen */)"
    refute Regex.match?(~r/elmc_record_get_index\(context, 3 \/\* screen \*\/\).*\n.*elmc_record_get_index\(context, 3 \/\* screen \*\)/s, init_body)
    assert init_body =~
             "elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_CURRENTDATETIME)"
    refute init_body =~ "elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME)"
    refute init_body =~ "elmc_new_int(23)"
    refute init_body =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
    assert length(Regex.scan(~r/ElmcValue \*tmp_1 =/, init_body)) == 1
  end

  test "record literal reuses shared zero subexpression without duplicate tmp vars" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { cells : List Int, score : Int, best : Int, seed : Int, turn : Int }

    type Msg
        = Noop

    init _ =
        ( { cells = List.repeat 16 0, score = 0, best = 0, seed = 0, turn = 0 }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.windowStack []

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/record_zero_cse_codegen", __DIR__)
    out_dir = Path.expand("tmp/record_zero_cse_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert length(Regex.scan(~r/ElmcValue \*tmp_1 = elmc_int_zero\(\);/, init_body)) == 1
    refute length(Regex.scan(~r/ElmcValue \*tmp_2 = elmc_int_zero\(\);/, init_body)) > 0
  end

  test "toMsg platform cmd encodes constructor tag from call site, not convention names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Cmd as PebbleCmd

    type alias Model =
        { hour : Int, minute : Int }

    type Msg
        = TimeUpdate PebbleCmd.CurrentDateTime

    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { hour = 0, minute = 0 }, PebbleCmd.getCurrentDateTime TimeUpdate )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )

    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none

    view : Model -> PebbleUi.UiNode
    view _ =
        PebbleUi.windowStack []

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/watchface_custom_msg_cmd", __DIR__)
    out_dir = Path.expand("tmp/watchface_custom_msg_cmd_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    pebble_h = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert init_body =~ "elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_TIMEUPDATE)"
    refute init_body =~ "elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME)"
    refute init_body =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
    refute pebble_h =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
  end

  test "record update uses field index with comment when shape is known" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi

    type alias Model =
        { timeString : String, ticks : Int }

    type Msg
        = Tick String

    init _ =
        ( { timeString = "--:--", ticks = 0 }, Cmd.none )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            Tick value ->
                ( { model | timeString = value }, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        PebbleUi.windowStack []

    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/record_update_index_codegen", __DIR__)
    out_dir = Path.expand("tmp/record_update_index_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert update_body =~ "elmc_record_update_index(tmp_2, 1 /* timeString */,"
    refute update_body =~ ~s/elmc_record_update(tmp_2, "timeString"/
  end

  test "update case on Msg uses ELMC_PEBBLE_MSG macros without redundant payload guards" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Cmd as PebbleCmd

    type alias Model =
        { timeString : String }

    type Msg
        = MinuteChanged Int
        | CurrentTimeString String

    init _ =
        ( { timeString = "--:--" }, PebbleCmd.getCurrentTimeString CurrentTimeString )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            MinuteChanged _ ->
                ( model, Cmd.none )

            CurrentTimeString value ->
                ( { model | timeString = value }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        PebbleUi.windowStack []

    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/msg_case_macro_codegen", __DIR__)
    out_dir = Path.expand("tmp/msg_case_macro_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert update_body =~ "ELMC_PEBBLE_MSG_MINUTECHANGED"
    refute update_body =~ "== 1 && (1)"
    refute update_body =~ "&& (1)"
    refute update_body =~ ~r/first\) == 1\)/

    assert generated_c =~
             "elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_CURRENTTIMESTRING)"
  end

  test "single subscription uses ELMC_SUBSCRIPTION macros instead of raw ints" do
    source = """
    module Main exposing (main)

    import Pebble.Events as PebbleEvents
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi

    type alias Model =
        { minute : Int }

    type Msg
        = MinuteChanged Int

    init _ =
        ( { minute = 0 }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        PebbleEvents.onMinuteChange MinuteChanged

    view _ =
        PebbleUi.windowStack []

    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/subscription_macro_codegen", __DIR__)
    out_dir = Path.expand("tmp/subscription_macro_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subscriptions_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert subscriptions_body =~
             "elmc_sub1(ELMC_SUBSCRIPTION_MINUTE_CHANGE, ELMC_PEBBLE_MSG_MINUTECHANGED)"

    refute subscriptions_body =~ "elmc_new_int(ELMC_SUBSCRIPTION_MINUTE_CHANGE)"
    refute subscriptions_body =~ "elmc_new_int(2048)"
    refute subscriptions_body =~ "\n\n\n"
    assert subscriptions_body =~ "  ElmcValue *_ ="
    refute subscriptions_body =~ ~r/^\S/m
  end

  test "button press subscription encodes button, event, and msg tag" do
    source = """
    module Main exposing (main)

    import Pebble.Button as Button
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        {}

    type Msg
        = UpPressed

    init _ =
        ( {}, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Button.onPress Button.Up UpPressed

    view _ =
        Ui.windowStack []

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/button_sub_codegen", __DIR__)
    out_dir = Path.expand("tmp/button_sub_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subscriptions_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert subscriptions_body =~
             "elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED)"
  end
end
