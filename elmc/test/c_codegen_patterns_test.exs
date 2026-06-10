defmodule Elmc.CCodegenPatternsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.RecordCompile

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

    assert generated_c =~
             ~r/scene_cmd\.p0 = 1;\s*\n\s*scene_cmd\.p1 = direct_native_let_textX_\d+;/

    refute generated_c =~ ~r/scene_cmd\.p1 = elmc_as_int\(tmp_\d+\)/
  end

  test "List.all with (/=) 0 uses cursor loop instead of elmc_list_all closure" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_hof_cursor_"
    assert generated_c =~ "elmc_fn_Main_rowHasValue"
    refute generated_c =~ "elmc_list_all("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "typed List Int equality uses integer-list helper" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    same : List Int -> List Int -> Bool
    same left right =
        let
            copied =
                left
        in
        copied == right

    adjacent : List Int -> Bool
    adjacent values =
        case values of
            a :: b :: _ ->
                a == b

            _ ->
                False

    init _ = ( { ok = same [ 1, 2, 3 ] [ 1, 2, 3 ] && adjacent [ 4, 4 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.toUiNode [ Ui.clear Color.white ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_int_eq", __DIR__)
    out_dir = Path.expand("tmp/list_int_eq_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    assert generated_c =~ "elmc_list_equal_int("
    refute generated_c =~ "elmc_value_equal("
    assert runtime_c =~ "int elmc_list_equal_int(ElmcValue *left, ElmcValue *right)"
  end

  test "List.concat of compiled list segments omits redundant nil fallbacks" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    rows : List Int -> List Int
    rows cells =
        [ List.reverse (List.take 2 cells)
        , List.reverse (List.drop 2 cells)
        , List.reverse cells
        ]
            |> List.concat

    init _ = ( { cells = rows [ 1, 2, 3, 4 ] }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.windowStack []
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    suffix = System.unique_integer([:positive])
    project_dir = Path.expand("tmp/list_concat_segments_no_nil_fallback_#{suffix}", __DIR__)
    out_dir = Path.expand("tmp/list_concat_segments_no_nil_fallback_codegen_#{suffix}", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_rows")
      |> List.last()
      |> String.split("\n}\n\nElmcValue *elmc_fn_Main_init", parts: 2)
      |> hd()

    assert body =~ "elmc_list_reverse("
    assert body =~ "elmc_list_take_int(2, cells)"
    assert body =~ "elmc_list_drop_int(2, cells)"
    refute body =~ "elmc_list_take("
    refute body =~ "elmc_list_drop("
    assert body =~ "list_concat_segments_"
    assert body =~ "elmc_list_concat_array("
    refute body =~ "list_concat_node_"
    refute body =~ "elmc_list_concat("
    refute body =~ "? tmp_"
    refute body =~ "? elmc_"
    refute body =~ "elmc_release(elmc_list_nil())"

    take_body =
      runtime_c
      |> String.split("ElmcValue *elmc_list_take_int", parts: 2)
      |> List.last()
      |> String.split("\n}\n\nElmcValue *elmc_list_drop", parts: 2)
      |> hd()

    drop_body =
      runtime_c
      |> String.split("ElmcValue *elmc_list_drop_int", parts: 2)
      |> List.last()
      |> String.split("\n}\n\nElmcValue *elmc_list_partition", parts: 2)
      |> hd()

    concat_body =
      runtime_c
      |> String.split("ElmcValue *elmc_list_concat(ElmcValue *lists)", parts: 2)
      |> List.last()
      |> String.split("\n}\n\nElmcValue *elmc_list_concat_array", parts: 2)
      |> hd()

    refute take_body =~ "elmc_list_reverse_copy"
    refute drop_body =~ "elmc_list_reverse_copy"
    refute concat_body =~ "elmc_list_reverse_copy"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_foldl_i_"
    assert generated_c =~ "elmc_fn_Main_collect"
    refute generated_c =~ "elmc_list_foldl("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "record literal reads score from bound merge var instead of constant zero" do
    fields = [
      %{name: "cells", expr: %{op: :field_access, arg: "merged", field: "cells"}},
      %{name: "score", expr: %{op: :field_access, arg: "merged", field: "score"}}
    ]

    env = %{
      "merged" => "tmp_4",
      :__module__ => "Main",
      :__record_shapes__ => %{"merged" => ["cells", "score"]},
      :__program_decls__ => %{}
    }

    {code, _out, _counter} =
      RecordCompile.compile(%{op: :record_literal, fields: fields}, env, 0)

    assert code =~ ~r/elmc_record_get(?:_index)?\(tmp_4, (?:1 \/\* score \*\/|"score")\)/
    refute code =~ "elmc_record_get(tmp_8, \"score\")"
    refute code =~ "elmc_int_zero();  ElmcValue *tmp_"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_filter_cursor_"
    assert generated_c =~ "elmc_fn_Main_nonzero"
    assert generated_c =~ "elmc_as_int(list_filter_head_"
    refute generated_c =~ "elmc_value_equal(tmp_"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "list_filter_map_i_"
    assert generated_c =~ "elmc_fn_Main_keepSmall"
    refute generated_c =~ "elmc_list_filter_map("
    refute generated_c =~ "elmc_closure_new(elmc_lambda_"
  end

  test "List.repeat with literal zero count uses malloc-free zero list helper" do
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_blankRow"
    assert generated_c =~ "ELMC_ZERO_N = 4"
    assert generated_c =~ "elmc_zero_list_tmp_"
    refute generated_c =~ "list_repeat_i_"
    refute generated_c =~ "elmc_list_repeat_count("
    refute generated_c =~ "elmc_list_repeat("
  end

  test "List.repeat with literal nonzero int uses static int array" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    row : List Int
    row =
        List.repeat 4 2

    init _ = ( { row = row }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.row)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/list_repeat_static_int", __DIR__)
    out_dir = Path.expand("tmp/list_repeat_static_int_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_row"
    assert generated_c =~ "static const elmc_int_t list_repeat_int_values_"
    assert generated_c =~ "{ 2, 2, 2, 2 }"
    assert generated_c =~ "elmc_list_from_int_array"
    refute generated_c =~ "list_repeat_i_"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "/* List.length */"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_collapseRows"
    assert generated_c =~ "elmc_list_concat_array("
    assert generated_c =~ "ElmcValue *elmc_fn_Main_collapseRow(ElmcValue *row)"

    assert generated_c =~
             ~r/elmc_fn_Main_collapseRow[\s\S]*?elmc_record_get(?:_index)?\(tmp_\d+, (?:1 \/\* score \*\/|"score")\)/

    collapse_row_body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_collapseRow(ElmcValue *row) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("static ElmcValue *elmc_fn_Main_collapseRows", parts: 2)
      |> hd()

    assert Regex.scan(~r/elmc_record_get\((tmp_\d+), "cells"\)/, collapse_row_body)
           |> Enum.frequencies()
           |> Enum.all?(fn {_tmp, count} -> count == 1 end)

    refute collapse_row_body =~ ~r/elmc_retain\(tmp_\d+_cells\)/

    refute generated_c =~ "elmc_record_get(tmp_8, \"score\")"
    refute generated_c =~ "elmc_int_zero();  ElmcValue *tmp_9_score"
    assert generated_c =~ "elmc_retain(row)"
    refute generated_c =~ "row ? elmc_retain(row)"

    refute generated_c =~
             ~r/list_concat_node_\d+ = elmc_list_cons\(tmp_\d+ \? elmc_retain\(tmp_\d+\)/

    refute generated_c =~ ~r/elmc_release\(list_concat_node_\d+\);/
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_mergeRows"
    assert generated_c =~ "elmc_list_concat_array("
    refute generated_c =~ "list_concat_node_"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_update", parts: 2)
      |> hd()

    assert init_body =~ "elmc_record_new_values_ints"
    refute init_body =~ "static const int rec_field_ids_"
    refute init_body =~ "static const char * const rec_names_"
    refute init_body =~ "elmc_record_new_static_ints"
    refute init_body =~ "elmc_record_new_ints"
    refute init_body =~ "elmc_record_new_take"

    assert length(Regex.scan(~r/elmc_record_get_index\(context, 3 \/\* screen \*\/\)/, init_body)) ==
             1

    assert init_body =~ "ELMC_RECORD_GET_INDEX_INT(tmp_1_screen, 1 /* height */)"
    assert init_body =~ "ELMC_RECORD_GET_INDEX_INT(tmp_1_screen, 3 /* width */)"

    assert init_body =~
             "elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_CURRENTDATETIME)"

    refute init_body =~ "elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME)"
    refute init_body =~ "elmc_new_int(23)"
    refute init_body =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
    assert init_body =~ "ElmcValue *tmp_1_screen = elmc_record_get_index(context, 3 /* screen */)"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_update", parts: 2)
      |> hd()

    assert length(Regex.scan(~r/ElmcValue \*tmp_1 = elmc_int_zero\(\);/, init_body)) == 1
    refute length(Regex.scan(~r/ElmcValue \*tmp_2 = elmc_int_zero\(\);/, init_body)) > 0
    assert init_body =~ "elmc_record_new_values_take"
    refute init_body =~ "static const int rec_field_ids_"
    refute init_body =~ "static const char * const rec_names_"
    refute init_body =~ "elmc_record_new_static_take"
    refute init_body =~ "elmc_record_new_take"
  end

  test "boxed record literal reuses nested field-access prefixes like context.screen" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { displayShape : Int
        , screenH : Int
        , screenW : Int
        }

    type Msg
        = Noop

    init context =
        ( { displayShape = context.screen.shape
          , screenH = context.screen.height
          , screenW = context.screen.width
          }
        , Cmd.none
        )

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

    project_dir = Path.expand("tmp/record_screen_cse_codegen", __DIR__)
    out_dir = Path.expand("tmp/record_screen_cse_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert length(Regex.scan(~r/elmc_record_get\(context, "screen"\)/, init_body)) == 1

    assert init_body =~ "ElmcValue *tmp_1_screen = elmc_record_get(context, \"screen\")"
    assert init_body =~ ~s/elmc_record_get(tmp_1_screen, "shape")/
    assert init_body =~ ~s/elmc_record_get(tmp_1_screen, "height")/
    assert init_body =~ ~s/elmc_record_get(tmp_1_screen, "width")/
    assert init_body =~ "ElmcValue *tmp_2_shape = elmc_record_get(tmp_1_screen, \"shape\")"
    assert init_body =~ "ElmcValue *tmp_3_height = elmc_record_get(tmp_1_screen, \"height\")"
    assert init_body =~ "ElmcValue *tmp_4_width = elmc_record_get(tmp_1_screen, \"width\")"
  end

  test "direct-only boxed helpers bind args without argc checks when wrappers are pruned" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as UiResources

    type alias Model =
        { items : List Int }

    type Msg
        = Noop

    directHelper items =
        List.append items items

    closureHelper items =
        List.append items items

    apply f x =
        f x

    init _ =
        ( { items = [] }, Cmd.none )

    update _ model =
        ( { model | items = directHelper model.items }, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.windowStack
            [ Ui.text
                UiResources.DefaultFont
                Ui.defaultTextOptions
                { x = 0, y = 0, w = 1, h = 1 }
                (String.fromInt (List.length (apply closureHelper model.items)))
            ]

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/direct_boxed_helper_codegen", __DIR__)
    out_dir = Path.expand("tmp/direct_boxed_helper_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    direct_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_directHelper(ElmcValue *items) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_closureHelper", parts: 2)
      |> hd()

    closure_body =
      generated_c
      |> String.split(
        "ElmcValue *elmc_fn_Main_closureHelper(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_apply", parts: 2)
      |> hd()

    update_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_subscriptions", parts: 2)
      |> hd()

    assert direct_body =~ "direct_call_abi"
    assert generated_c =~ "ElmcValue *elmc_fn_Main_directHelper(ElmcValue *items)"
    refute direct_body =~ "argc > 0"
    refute direct_body =~ "args[0]"

    assert closure_body =~ "ElmcValue *items = (argc > 0) ? args[0] : NULL;"
    refute closure_body =~ "direct_call_abi"

    assert update_body =~ "ElmcValue *model = (argc > 1) ? args[1] : NULL;"
  end

  test "borrowed call operands pass function params directly without retain temps" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { seed : Int }

    type Msg
        = Noop

    callee seed board =
        ( seed, board )

    forward seed =
        callee seed seed

    init _ =
        ( { seed = 0 }, Cmd.none )

    update _ model =
        ( Tuple.first (forward model.seed), Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.windowStack []

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/borrowed_call_operand_codegen", __DIR__)
    out_dir = Path.expand("tmp/borrowed_call_operand_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    forward_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_forward(ElmcValue *seed) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_init", parts: 2)
      |> hd()

    assert generated_c =~ "ElmcValue *elmc_fn_Main_forward(ElmcValue *seed)"
    assert forward_body =~ "elmc_fn_Main_callee(seed, seed)"
    refute forward_body =~ "call_args_"
    refute forward_body =~ "elmc_retain(seed)"
    refute Regex.match?(~r/ElmcValue \*tmp_\d+ = elmc_retain\(seed\);/, forward_body)
  end

  test "borrow_arg callees pass let-bound locals without retain temps" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { seed : Int
        , cells : List Int
        }

    type Msg
        = Noop

    setCell : Int -> Int -> List Int -> List Int
    setCell index newValue cells =
        List.indexedMap
            (\\i value ->
                if i == index then
                    newValue
                else
                    value
            )
            cells

    spawnTile seed cells =
        let
            tileIndex =
                3

            tileValue =
                2
        in
        setCell tileIndex tileValue cells

    init _ =
        ( { seed = 0, cells = [] }, Cmd.none )

    update _ model =
        ( { model | cells = spawnTile model.seed model.cells }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.windowStack []

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/borrow_local_call_operand_codegen", __DIR__)
    out_dir = Path.expand("tmp/borrow_local_call_operand_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    spawn_body =
      generated_c
      |> String.split(
        "static ElmcValue *elmc_fn_Main_spawnTile(ElmcValue *seed, ElmcValue *cells) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("static ElmcValue *elmc_fn_Main_setCell", parts: 2)
      |> hd()

    assert spawn_body =~ "elmc_fn_Main_setCell(tmp_"
    refute Regex.match?(~r/elmc_retain\(tmp_\d+\)/, spawn_body)

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_retain\(tmp_\d+\);/,
             spawn_body
           )

    set_cell_body =
      generated_c
      |> String.split(
        "static ElmcValue *elmc_fn_Main_setCell(ElmcValue *index, ElmcValue *newValue, ElmcValue *cells) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("static ElmcValue *elmc_fn_Main_spawnTile", parts: 2)
      |> hd()

    assert set_cell_body =~ "elmc_list_replace_nth_int(cells,"
    refute set_cell_body =~ "elmc_retain(cells)"
    refute set_cell_body =~ "elmc_release(cells)"
  end

  test "if branches assign tuple results directly without alias temps" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { seed : Int
        , cells : List Int
        }

    type Msg
        = Noop

    setCell index newValue cells =
        List.indexedMap
            (\\i value ->
                if i == index then
                    newValue
                else
                    value
            )
            cells

    pickTile seed cells emptyCount =
        if emptyCount == 0 then
            ( cells, seed )
        else
            ( setCell 3 2 cells, seed )

    init _ =
        ( { seed = 0, cells = [] }, Cmd.none )

    update _ model =
        let
            ( nextCells, _ ) =
                pickTile model.seed model.cells 1
        in
        ( { model | cells = nextCells }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.windowStack []

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/if_branch_direct_assign_codegen", __DIR__)
    out_dir = Path.expand("tmp/if_branch_direct_assign_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true,
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    pick_body =
      generated_c
      |> String.split(
        "static ElmcValue *elmc_fn_Main_pickTile(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_init", parts: 2)
      |> hd()

    assert pick_body =~ "= elmc_tuple2_take("
    refute Regex.match?(~r/tmp_\d+ = tmp_\d+;/, pick_body)

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_tuple2_take\([^;]+\);\s+tmp_\d+ = tmp_\d+;/,
             pick_body
           )
  end

  test "retaining runtime calls borrow env-bound vars without retain temps" do
    alias Elmc.Backend.CCodegen.Host

    env =
      %{"head" => "tmp_head"}
      |> Map.put(:__module__, "Main")

    expr = %{
      op: :runtime_call,
      function: "elmc_list_cons",
      args: [%{op: :var, name: "head"}, %{op: :int_literal, value: 0}]
    }

    {code, _out, _counter} = Host.compile_expr(expr, env, 2)
    source = IO.iodata_to_binary(code)

    assert source =~ "elmc_list_cons(tmp_head, tmp_"
    refute source =~ "elmc_retain(tmp_head)"
    refute source =~ "elmc_release(tmp_head)"
    assert source =~ "elmc_release(tmp_"
  end

  test "zero-arity direct helpers called with an arg use closure apply" do
    env =
      %{"seed" => "tmp_seed"}
      |> Map.put(:__module__, "Random")
      |> Map.put(:__function_arities__, %{{"Random", "next"} => 0})
      |> Map.put(:__direct_call_targets__, MapSet.new([{"Random", "next"}]))
      |> Map.put(:__program_decls__, %{})

    {code, _out, _counter} =
      FunctionCallCompile.compile(
        "Random",
        "next",
        [%{op: :var, name: "seed"}],
        env,
        1
      )

    source = IO.iodata_to_binary(code)

    assert source =~ "elmc_fn_Random_next()"
    assert source =~ "elmc_closure_call("
    refute source =~ "elmc_fn_Random_next(call_args_"
    refute source =~ "elmc_fn_Random_next(tmp_seed"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    pebble_h = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert init_body =~
             "elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_TIMEUPDATE)"

    refute init_body =~ "elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME)"
    refute init_body =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
    refute pebble_h =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
  end

  test "union constructor int literals use generated Elm-name macros" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type Direction
        = Left
        | Right
        | Up
        | Down

    type Msg
        = Noop

    move : Direction -> Int -> Int
    move direction value =
        case direction of
            Left ->
                value + 1

            Right ->
                value - 1

            Up ->
                value + 2

            Down ->
                value - 2

    init _ =
        ( 0, Cmd.none )

    update _ model =
        ( move Left model + move Up model, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        Ui.windowStack []

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/union_constructor_macro_codegen", __DIR__)
    out_dir = Path.expand("tmp/union_constructor_macro_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "#define ELMC_UNION_LEFT 1"
    assert generated_c =~ "#define ELMC_UNION_MAIN_LEFT 1"
    assert generated_c =~ "#define ELMC_UNION_MAIN_UP 3"
    assert generated_c =~ "elmc_new_int(ELMC_UNION_LEFT)"
    assert generated_c =~ "elmc_new_int(ELMC_UNION_MAIN_UP)"
    assert generated_c =~ "case ELMC_UNION_LEFT:"
    assert generated_c =~ "case ELMC_UNION_RIGHT:"
    assert generated_c =~ "case ELMC_UNION_MAIN_UP:"
    assert generated_c =~ "case ELMC_UNION_MAIN_DOWN:"
    refute generated_c =~ "elmc_new_int(1);\n\n  ElmcValue *tmp_"
    refute generated_c =~ "elmc_new_int(3);\n\n  ElmcValue *tmp_"
  end

  test "storage write string uses compact string command instead of padded tuple chain" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Storage as Storage
    import Pebble.Ui as Ui

    type Msg
        = Noop

    init _ =
        ( 0, Storage.writeString 2048 (String.fromInt 42) )

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

    project_dir = Path.expand("tmp/storage_write_string_cmd_codegen", __DIR__)
    out_dir = Path.expand("tmp/storage_write_string_cmd_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_update", parts: 2)
      |> hd()

    assert init_body =~
             "elmc_cmd1_string(ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING, 2048, native_string_"

    refute init_body =~ "elmc_new_int(ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING)"
    refute init_body =~ "elmc_tuple2_ints(0, 0)"
  end

  test "direct render text append unrolls literal prefix before dynamic suffix" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { best : Int }

    type Msg
        = Noop

    init _ =
        ( { best = 42 }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.toUiNode
            [ Ui.clear Color.white
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 0, y = 0, w = 100, h = 20 } ("Best " ++ String.fromInt model.best)
            ]

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/direct_text_literal_prefix_append", __DIR__)
    out_dir = Path.expand("tmp/direct_text_literal_prefix_append_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "scene_cmd.text[0] = 'B';"
    assert generated_c =~ "scene_cmd.text[4] = ' ';"
    assert generated_c =~ "int direct_text_i = 5;"
    assert generated_c =~ "const char *direct_text_right = native_string_"
    refute generated_c =~ "const char *direct_text = \"Best \";"
  end

  test "direct render eliminates inverse condition inside known branch" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources

    type alias Model =
        { value : Int }

    type Msg
        = Noop

    init _ =
        ( { value = 2 }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        Ui.toUiNode
            [ if model.value /= 0 then
                Ui.text Resources.DefaultFont
                    Ui.defaultTextOptions
                    { x = 0, y = 0, w = 100, h = 20 }
                    (if model.value == 0 then
                        "."

                     else
                        String.fromInt model.value
                    )

              else
                Ui.clear Color.white
            ]

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/direct_render_known_inverse_cond", __DIR__)
    out_dir = Path.expand("tmp/direct_render_known_inverse_cond_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ ~r/if \(elmc_as_int\(tmp_\d+\) != 0\)/
    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT)"
    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR)"
    refute generated_c =~ "if (ELMC_RECORD_GET_INDEX_INT(model, 0 /* value */) == 0)"
    refute generated_c =~ "if (0)"
    refute generated_c =~ "elmc_new_string(\".\")"
    refute generated_c =~ "scene_cmd.text[0] = '.';"
  end

  test "affine direct render skips unreachable zero label inside nonzero text guard" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources

    type alias Model =
        { cells : List Int }

    type Msg
        = Noop

    init _ =
        ( { cells = [ 0, 2, 4 ] }, Cmd.none )

    update _ model =
        ( model, Cmd.none )

    subscriptions _ =
        Sub.none

    drawCell : Int -> Int -> Ui.RenderOp
    drawCell index value =
        let
            x =
                index * 10

            label =
                if value == 0 then
                    "."

                else
                    String.fromInt value
        in
        Ui.text Resources.DefaultFont
            Ui.defaultTextOptions
            { x = x, y = 0, w = 10, h = 10 }
            label

    view model =
        model.cells
            |> List.indexedMap drawCell
            |> Ui.toUiNode

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/direct_affine_text_nonzero_guard", __DIR__)
    out_dir = Path.expand("tmp/direct_affine_text_nonzero_guard_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ ~r/if \(elmc_as_int\(direct_node_\d+->head\) != 0\)/
    refute generated_c =~ ~r/if \(elmc_as_int\(direct_node_\d+->head\) == 0\)/
    refute generated_c =~ "scene_cmd.text[0] = '.';"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert update_body =~ "elmc_record_update_index(model, 1 /* timeString */, tmp_2)"
    refute update_body =~ "elmc_retain(model)"
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subscriptions_body =
      generated_c
      |> String.split(
        "ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
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

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subscriptions_body =
      generated_c
      |> String.split(
        "ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {",
        parts: 2
      )
      |> Enum.at(1, "")
      |> String.split("}\n", parts: 2)
      |> hd()

    assert subscriptions_body =~
             "elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED)"
  end

  test "zero-arity direct helpers stay direct when only closure-applied from lambdas" do
    alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
    alias Elmc.Backend.CCodegen.Host
    alias Elmc.Backend.CCodegen.IRQueries
    alias ElmEx.Frontend.Bridge
    alias ElmEx.IR.Lowerer

    random_source = """
    module Random exposing (int)

    type Generator a
        = Generator (Int -> ( a, Int ))

    int low high =
        Generator
            (\\seed ->
                let
                    ( raw, _ ) =
                        next seed
                in
                ( low + raw, seed )
            )

    next =
        \\seed -> ( seed, seed )
    """

    main_source = """
    module Main exposing (main)

    import Random

    main =
        Random.int 0 1
    """

    project_dir = Path.expand("tmp/random_zero_arity_wrapper_targets", __DIR__)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Random.elm"), random_source)
    File.write!(Path.join(project_dir, "src/Main.elm"), main_source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    {:ok, project_data} = Bridge.load_project(project_dir)
    {:ok, ir0} = Lowerer.lower_project(project_data)
    ir = ElmEx.IR.DeadCode.strip(ir0, "Main")

    opts = %{entry_module: "Main", prune_native_wrappers: true}
    decl_map = IRQueries.function_decl_map(ir)
    direct = Host.direct_command_targets(ir, opts, decl_map)
    wrapper = GenericTargets.wrapper_targets(ir, opts, decl_map, direct)

    refute MapSet.member?(wrapper, {"Random", "next"})
  end

  test "list int add-fold helpers emit native cursor loops and native call sites" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/list_int_reduce_project", __DIR__)
    out_dir = Path.expand("tmp/list_int_reduce_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (main)

      countEmpty : List Int -> Int
      countEmpty cells =
          case cells of
              [] ->
                  0

              value :: rest ->
                  (if value == 0 then
                      1

                   else
                      0
                  )
                      + countEmpty rest

      countZeros : List Int -> Int
      countZeros xs =
          case xs of
              [] ->
                  0

              n :: tail ->
                  (if n == 0 then 1 else 0) + countZeros tail

      useCounts : List Int -> Int
      useCounts cells =
          let
              emptyCount =
                  countEmpty cells

              zeroCount =
                  countZeros cells
          in
          emptyCount + zeroCount

      main =
          useCounts []
      """
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             "static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells)"

    assert generated_c =~
             "static elmc_int_t elmc_fn_Main_countZeros_native(ElmcValue * const xs)"

    assert generated_c =~ "list_reduce_cursor_"
    assert generated_c =~ ~r/elmc_as_int\(list_reduce_node_\d+->head\)/
    refute generated_c =~ "elmc_fn_Main_countEmpty(cells)"
    refute generated_c =~ "elmc_fn_Main_countZeros(xs)"

    [use_counts_body | _] =
      String.split(generated_c, "elmc_fn_Main_useCounts", parts: 2)

    refute use_counts_body =~ "elmc_new_int(elmc_fn_Main_countEmpty_native"
    assert generated_c =~ "elmc_fn_Main_countEmpty_native(cells)"
    assert generated_c =~ "elmc_fn_Main_countZeros_native(xs)"
  end

  test "list int search helpers emit native cursor loops and native call sites" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/list_int_search_project", __DIR__)
    out_dir = Path.expand("tmp/list_int_search_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (main)

      nthEmptyIndex : Int -> List Int -> Int
      nthEmptyIndex target cells =
          nthEmptyIndexHelp target 0 cells

      nthEmptyIndexHelp : Int -> Int -> List Int -> Int
      nthEmptyIndexHelp target index cells =
          case cells of
              [] ->
                  -1

              value :: rest ->
                  if value == 0 then
                      if target == 0 then
                          index
                      else
                          nthEmptyIndexHelp (target - 1) (index + 1) rest
                  else
                      nthEmptyIndexHelp target (index + 1) rest

      useIndex : Int -> List Int -> Int
      useIndex seed cells =
          nthEmptyIndex (seed + 1) cells

      main =
          useIndex 0 []
      """
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             "static elmc_int_t elmc_fn_Main_nthEmptyIndexHelp_native(const elmc_int_t target, const elmc_int_t index, ElmcValue * const cells)"

    assert generated_c =~
             "static elmc_int_t elmc_fn_Main_nthEmptyIndex_native(const elmc_int_t target, ElmcValue * const cells)"

    assert generated_c =~ "list_search_cursor_"
    assert generated_c =~ ~r/elmc_as_int\(list_search_node_\d+->head\)/
    refute generated_c =~ "elmc_fn_Main_nthEmptyIndexHelp(target"
    assert generated_c =~ "elmc_fn_Main_nthEmptyIndexHelp_native("
    assert generated_c =~ "elmc_fn_Main_nthEmptyIndex_native("
  end

  test "game-2048 direct view scene paints 16 board rects after init and random seed" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    elm_2048 = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/game_2048_scene_host", __DIR__)
    out_dir = Path.expand("tmp/game_2048_scene_host_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(elm_2048))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

    generated_h = File.read!(Path.join(out_dir, "c/elmc_generated.h"))
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_h =~ "elmc_fn_Main_init("
    assert generated_h =~ "elmc_fn_Main_update("
    refute generated_h =~ "elmc_fn_Main_spawnTileWithSeed("
    assert generated_c =~ "static ElmcValue *elmc_fn_Main_spawnTileWithSeed("
    assert generated_c =~ "while (direct_rc == 0 && direct_cursor_"
    assert generated_c =~ "ELMC_RENDER_OP_RECT"

    harness_path = Path.join(out_dir, "c/game_2048_scene_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *aplite_launch_context(void) {
        ElmcValue *reason = elmc_new_int(2);
        ElmcValue *watch_model = elmc_new_string("");
        ElmcValue *watch_profile_id = elmc_new_string("aplite");
        ElmcValue *width = elmc_new_int(144);
        ElmcValue *height = elmc_new_int(168);
        ElmcValue *shape = elmc_new_int(1);
        ElmcValue *color_mode = elmc_new_string("BlackWhite");
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, shape, width};
        ElmcValue *screen = elmc_record_new_take(4, screen_names, screen_values);
        ElmcValue *has_microphone = elmc_new_int(0);
        ElmcValue *has_compass = elmc_new_int(0);
        ElmcValue *supports_health = elmc_new_int(0);
        const char *names[] = {
          "has_compass", "has_microphone", "reason", "screen",
          "supports_health", "watchModel", "watchProfileId"
        };
        ElmcValue *values[] = {
          has_compass, has_microphone, reason, screen,
          supports_health, watch_model, watch_profile_id
        };
        return elmc_record_new_take(7, names, values);
      }

      static int count_kind(ElmcPebbleApp *app, int kind) {
        int count = 0;
        ElmcPebbleDrawCmd cmd;
        elmc_pebble_scene_reset_draw_cursor(app);
        for (int i = 0; i < 256; i++) {
          if (elmc_pebble_scene_commands_next(app, &cmd, 1) <= 0) break;
          if (cmd.kind == kind) count++;
        }
        return count;
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = aplite_launch_context();
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_RANDOMGENERATED, 12345) != 0) return 3;
        app.scene.dirty = 1;
        if (elmc_pebble_ensure_scene(&app) != 0) return 4;

        int rects = count_kind(&app, ELMC_PEBBLE_DRAW_RECT);
        int texts = count_kind(&app, ELMC_PEBBLE_DRAW_TEXT);
        if (rects < 16) {
          fprintf(stderr, "expected >=16 rects, got %d (texts=%d)\\n", rects, texts);
          elmc_pebble_deinit(&app);
          return 5;
        }

        elmc_pebble_deinit(&app);
        printf("ok rects=%d texts=%d\\n", rects, texts);
        return 0;
      }
      """
    )

    cc = System.get_env("CC") || "cc"
    binary_path = Path.join(out_dir, "game_2048_scene_harness")

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
    assert String.contains?(run_out, "ok rects=")
  end

  test "special value commands do not keep discarded Random generator functions" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Random

    type Msg
        = RandomGenerated Int

    init _ =
        ( 0, Random.generate RandomGenerated (Random.int 1 16) )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view model =
        Ui.rect { x = 0, y = 0, w = 10, h = 10 } Color.black

    main =
        Platform.worker { init = init, update = update, subscriptions = subscriptions, view = view }
    """

    generated_c = compile_generated_c!("special_random_prune", source, direct_render_only: true)

    assert generated_c =~ "ELMC_PEBBLE_CMD_RANDOM_GENERATE"
    refute generated_c =~ "elmc_fn_Random_int"
    refute generated_c =~ "elmc_fn_Random_next"
    refute generated_c =~ "elmc_lambda_"
    assert generated_c =~ "#define ELMC_COLOR_BLACK"
    refute generated_c =~ "#define ELMC_COLOR_MELON"
  end

  test "direct render folds nonzero literal div and mod guards" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources

    init _ =
        ( { x = 17 }, Platform.Cmd.none )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view model =
        Ui.text Resources.DefaultFont
            Ui.defaultTextOptions
            { x = modBy 4 model.x, y = model.x // 4, w = 30, h = 20 }
            (String.fromInt model.x)

    main =
        Platform.worker { init = init, update = update, subscriptions = subscriptions, view = view }
    """

    generated_c = compile_generated_c!("direct_literal_div_mod", source, direct_render_only: true)

    refute generated_c =~ "direct_den_"
    refute generated_c =~ "direct_mod_base_"
    assert generated_c =~ " / 4"
    assert generated_c =~ " % 4"
  end

  defp compile_generated_c!(name, source, opts) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{name}_project", __DIR__)
    out_dir = Path.expand("tmp/#{name}_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, _result} =
             Elmc.compile(
               project_dir,
               Map.merge(
                 %{
                   out_dir: out_dir,
                   entry_module: "Main",
                   strip_dead_code: true,
                   prune_native_wrappers: true
                 },
                 Map.new(opts)
               )
             )

    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end
end
