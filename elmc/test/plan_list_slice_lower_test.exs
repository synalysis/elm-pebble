defmodule Elmc.PlanListSliceLowerTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract
  alias Elmc.Backend.CCodegen.GeneratedSource
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  test "rowAt lowers List.take + List.drop slice to list_slice_int" do
    source = """
    module Main exposing (rowAt)

    rowAt : Int -> List Int -> List Int
    rowAt row cells =
        List.take 4 (List.drop (row * 4) cells)
    """

    project_dir = Path.expand("tmp/plan_row_at", __DIR__)
    out_dir = Path.expand("tmp/plan_row_at_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "rowAt"})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: false)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "list_slice_int"

    assert {:ok, [0, 1, 2, 3]} =
             Elmc.Backend.Bytecode.Loader.run_manifest_entry(out_dir, {"Main", "rowAt"},
               params: [0, Enum.to_list(0..15)]
             )

    Process.put(:elmc_program_decls, decl_map)

    c = Elmc.Backend.C.Lower.Function.emit(plan, shell: false)
    refute c =~ "elmc_new_int(&owned"
    assert c =~ "row *"
    assert c =~ "elmc_list_slice_int"
  end

  test "reverseRows folds const_int literals into native-int rowAt calls" do
    source = """
    module Main exposing (reverseRows)

    reverseRows : List Int -> List Int
    reverseRows cells =
        [ List.reverse (rowAt 0 cells)
        , List.reverse (rowAt 1 cells)
        , List.reverse (rowAt 2 cells)
        , List.reverse (rowAt 3 cells)
        ]

    rowAt : Int -> List Int -> List Int
    rowAt row cells =
        List.take 4 (List.drop (row * 4) cells)
    """

    project_dir = Path.expand("tmp/plan_reverse_rows", __DIR__)
    out_dir = Path.expand("tmp/plan_reverse_rows_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "reverseRows"})
    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    Process.put(:elmc_program_decls, decl_map)

    GeneratedSource.prepare_emit_session!(result.ir, %{
      plan_ir_mode: :primary,
      entry_module: "Main",
      strip_dead_code: false
    })

    c = Elmc.Backend.C.Lower.Function.emit(plan, shell: true)

    refute c =~ ~r/elmc_new_int\([^,]+,\s*0\)/
    refute c =~ ~r/elmc_new_int\([^,]+,\s*1\)/
    refute c =~ ~r/elmc_new_int\([^,]+,\s*2\)/
    refute c =~ ~r/elmc_new_int\([^,]+,\s*3\)/
    refute c =~ "plan_argv_"
    assert c =~ "elmc_fn_Main_rowAt(&owned"
    assert c =~ ", 0,"
    assert c =~ ", 1,"
    assert c =~ ", 2,"
    assert c =~ ", 3,"
  end

  test "transpose lowers static Int list literal to elmc_list_from_int_array" do
    source = """
    module Main exposing (transpose)

    transpose : List Int -> List Int
    transpose cells =
        List.map
            (\\i -> Maybe.withDefault 0 (listAt i cells))
            [ 0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15 ]

    listAt : Int -> List a -> Maybe a
    listAt index values =
        if index < 0 then
            Nothing
        else
            List.head (List.drop index values)
    """

    project_dir = Path.expand("tmp/plan_transpose", __DIR__)
    out_dir = Path.expand("tmp/plan_transpose_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "transpose"})
    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    Process.put(:elmc_program_decls, decl_map)

    GeneratedSource.prepare_emit_session!(result.ir, %{
      plan_ir_mode: :primary,
      entry_module: "Main",
      strip_dead_code: false
    })

    c = Elmc.Backend.C.Lower.Function.emit(plan, shell: true)

    assert c =~ "elmc_list_from_int_array"
    assert c =~ "plan_list_int_values_"
    assert c =~ "0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15"
    refute c =~ ~r/elmc_new_int\([^,]+,\s*15\)/
    refute c =~ ~r/elmc_list_cons\(&owned/
  end

  test "static Float list literal lowers to elmc_list_from_float_array" do
    source = """
    module Main exposing (sumFloats)

    sumFloats : List Float -> Float
    sumFloats xs =
        List.foldl (+) 0 xs

    initList : List Float
    initList =
        [ 1.0, 2.0, 3.0, 4.0 ]
    """

    project_dir = Path.expand("tmp/plan_float_list", __DIR__)
    out_dir = Path.expand("tmp/plan_float_list_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "initList"})
    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    Process.put(:elmc_program_decls, decl_map)

    GeneratedSource.prepare_emit_session!(result.ir, %{
      plan_ir_mode: :primary,
      entry_module: "Main",
      strip_dead_code: false
    })

    c = Elmc.Backend.C.Lower.Function.emit(plan, shell: true)

    assert c =~ "elmc_list_from_float_array"
    assert c =~ "plan_list_float_values_"
    refute c =~ ~r/elmc_list_cons\(&owned/
  end

  test "static String list literal lowers to elmc_list_from_values_take" do
    source = """
    module Main exposing (joinLabels)

    joinLabels : List String -> String
    joinLabels xs =
        String.join "," xs

    initList : List String
    initList =
        [ "a", "b", "c", "d" ]
    """

    project_dir = Path.expand("tmp/plan_string_list", __DIR__)
    out_dir = Path.expand("tmp/plan_string_list_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    decl = Map.fetch!(decl_map, {"Main", "initList"})
    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    Process.put(:elmc_program_decls, decl_map)

    GeneratedSource.prepare_emit_session!(result.ir, %{
      plan_ir_mode: :primary,
      entry_module: "Main",
      strip_dead_code: false
    })

    c = Elmc.Backend.C.Lower.Function.emit(plan, shell: true)

    assert c =~ "elmc_list_from_values_take"
    assert c =~ "plan_list_items_"
    refute c =~ ~r/elmc_list_cons\(&owned/
  end

  test "subscriptions defers leaked owned cleanup to release_array_lifo" do
    out_dir = Path.expand("tmp/plan_subscriptions_lifo", __DIR__)
    project_dir = Path.expand("tmp/plan_subscriptions_lifo_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    subs_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_subscriptions")

    assert subs_body =~ "elmc_release_array_lifo(owned"
    refute subs_body =~ "elmc_release(owned["
    refute subs_body =~ ~r/elmc_new_int\(&owned\[\d+\], ELMC_BUTTON_/
    assert subs_body =~ "elmc_sub3(&owned"
    assert subs_body =~ "ELMC_BUTTON_BACK"
  end

  test "min over record Int fields and button subs stay native in plan-primary C" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/plan_native_min_project", __DIR__)
    out_dir = Path.expand("tmp/plan_native_min_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      File.read!(Path.join(project_dir, "src/Main.elm")) <>
        """


    type alias NativeMinRecordModel =
        { screenW : Int
        , screenH : Int
        }


    nativeMinRecordFields : NativeMinRecordModel -> Int
    nativeMinRecordFields model =
        min model.screenW model.screenH


    buttonSubs : List Int
    buttonSubs =
        [ 0, 1, 2, 3 ]
    """
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    min_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_nativeMinRecordFields")

    assert min_body =~ "ELMC_RECORD_GET_INDEX_INT"
    assert min_body =~ "plan_native_int_"
    refute min_body =~ "elmc_basics_min"
    refute min_body =~ "elmc_record_get_index"
  end

  test "view codegen does not reference dropped native-int regs as argN" do
    out_dir = Path.expand("tmp/plan_view_no_argn", __DIR__)
    project_dir = Path.expand("tmp/plan_view_no_argn_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_view")
    board_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_boardLayout")

    refute view_body =~ ~r/\barg\d+\b/
    refute board_body =~ ~r/\barg\d+\b/
    assert view_body =~ "plan_native_int_"
  end

  test "literal ++ fromInt string append fuses to snprintf in view" do
    out_dir = Path.expand("tmp/plan_snprintf_view", __DIR__)
    project_dir = Path.expand("tmp/plan_snprintf_view_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_view")

    assert view_body =~ ~r/snprintf\(native_string_buf_\d+, sizeof\(native_string_buf_\d+\), "Best %lld"/
    refute view_body =~ ~r/elmc_new_string\(&owned\[\d+\], "Best "\)/
    refute view_body =~ ~r/elmc_string_from_native_int\(&owned\[\d+\],/
  end

  test "retain into owned slots does not emit OOM checks" do
    out_dir = Path.expand("tmp/plan_retain_no_oom", __DIR__)
    project_dir = Path.expand("tmp/plan_retain_no_oom_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_view")

    refute view_body =~ ~r/owned\[\d+\] = elmc_retain\([^)]+\);\s*\n\s*if \(!owned\[\d+\]\)/
  end

  test "if/else int merge retained across branches stays native for br_if" do
    source = """
    module Main exposing (probe)

    probe : Bool -> Int
    probe b =
        let
            flag =
                if b then
                    1
                else
                    0
        in
        if flag == 0 then
            10
        else
            20
    """

    project_dir = Path.expand("tmp/plan_native_if_merge", __DIR__)
    out_dir = Path.expand("tmp/plan_native_if_merge_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    Process.put(:elmc_program_decls, decl_map_from_result(result))

    decl = Map.fetch!(decl_map_from_result(result), {"Main", "probe"})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map_from_result(result), rc_required: true)

    c = Elmc.Backend.C.Lower.Function.emit(plan, shell: false)

    refute c =~ ~r/elmc_new_int\(&owned\[\d+\], [01]\)/
    assert c =~ "plan_native_int_"
    assert c =~ "plan_native_int_3 = (elmc_as_bool(owned[0])) ? 1 : 0"
    assert c =~ "const bool plan_native_bool_5 = (plan_native_int_3 == 0);"
    assert c =~ "plan_native_int_8 = (plan_native_bool_5) ? 10 : 20;"
  end

  test "record literal and field access use index-only alloc and ELMC_FIELD macros" do
    source = """
    module Main exposing (layout, screenW)

    type alias Layout =
        { x : Int, y : Int, cell : Int, gap : Int }

    type alias Model =
        { screenW : Int, screenH : Int, layout : Layout }

    layout : Model -> Layout
    layout model =
        { x = 0, y = 0, cell = model.screenW, gap = 1 }

    screenW : Model -> Int
    screenW model =
        model.screenW
    """

    project_dir = Path.expand("tmp/plan_record_field_indices", __DIR__)
    out_dir = Path.expand("tmp/plan_record_field_indices_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "enum {"
    assert generated_c =~ "ELMC_FIELD_MAIN_LAYOUT_X"
    assert generated_c =~ "ELMC_FIELD_MAIN_MODEL_SCREENW"

    layout_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_layout")

    refute layout_body =~ "rec_names_"
    refute layout_body =~ "elmc_record_new_static_take"
    assert layout_body =~ "elmc_record_new_values_ints"
    refute layout_body =~ "elmc_record_new_values_take"
    refute layout_body =~ ~r/elmc_new_int\(&owned\[\d+\], [01]\)/

    screen_w_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_screenW")
    assert screen_w_body =~ "ELMC_FIELD_MAIN_MODEL_SCREENW"
    refute screen_w_body =~ ~r/ELMC_RECORD_GET_INDEX_INT\([^,]+, \d+ \/\* screenW \*\//
  end

  test "drawCell keeps modBy and layout math on native ints" do
    out_dir = Path.expand("tmp/plan_draw_cell_native", __DIR__)
    project_dir = Path.expand("tmp/plan_draw_cell_native_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    draw_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_drawCell")

    refute draw_body =~ "elmc_basics_mod_by"
    refute draw_body =~ "elmc_new_int(&owned[1], index)"
    refute draw_body =~ "ELMC_TAG_FLOAT"
    refute draw_body =~ "elmc_new_bool"
    assert draw_body =~ "const bool plan_native_bool_20 = (value == 0);"
    assert draw_body =~ "(value == 0)"
    assert draw_body =~ "if (!plan_native_bool_"
    assert draw_body =~ "if (plan_native_bool_"
    assert draw_body =~ "plan_native_int_"
    assert draw_body =~ "0 /* x */"
    assert draw_body =~ "2 /* cell */"
    assert draw_body =~ "% 4"
  end

  test "merge nested if phi bools use const native bool at assign site" do
    out_dir = Path.expand("tmp/plan_merge_native_bool", __DIR__)
    project_dir = Path.expand("tmp/plan_merge_native_bool_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    merge_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_merge")

    assert merge_body =~ "const bool plan_native_bool_1 = elmc_as_bool(elmc_list_is_empty(owned[0]));"
    refute merge_body =~ "bool plan_native_bool_1 = false;"
  end

  defp decl_map_from_result(result) do
    result.ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
    end)
    |> Map.new()
  end
end
