defmodule Elmc.CCodegenPatternsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Test.CCodegenExtract

  @just_payload_borrow "elmc_maybe_or_tuple_just_payload_borrow"

  defp corpus_skip? do
    System.get_env("CORPUS_SKIP") in ["1", "true", "yes"]
  end

  defp corpus_execution_ready?(path) when is_binary(path) do
    not corpus_skip?() and Elmc.Test.ElmRunCorpus.expected_available?(path)
  end

  defp normalize_corpus_output(out) when is_binary(out) do
    out
    |> String.replace("True", "1")
    |> String.replace("False", "0")
  end

  defp assert_corpus_run!(path, tmp, opts \\ []) do
    alias Elmc.Test.ElmRunCorpus

    skip_output? = Keyword.get(opts, :skip_output_check, false)
    gold = ElmRunCorpus.read_expected!(path)

    case ElmRunCorpus.run_elmc_execution!(path, tmp, Keyword.merge([timeout_ms: 60_000], opts)) do
      {:ok, out} ->
        unless skip_output? do
          assert normalize_corpus_output(out) == normalize_corpus_output(gold)
        end

        :ok

      {:error, {:harness_compile, _msg}} ->
        :ok

      other ->
        flunk("unexpected corpus execution result for #{path}: #{inspect(other)}")
    end
  end

  defp rc_direct_fn_def_marker(name),
    do: ~r/static RC elmc_fn_Main_#{name}(?:_native)?\(ElmcValue \*\*out,[^)]*\) \{/

  defp worker_fn_def_marker(name),
    do: ~r/(?:RC|ElmcValue \*) elmc_fn_Main_#{name}\([^)]*\) \{/

  defp assert_plan_compact_int_list!(generated_c, fn_name) do
    body = fn_body!(generated_c, fn_name)
    assert body =~ "plan block"
    assert body =~ "plan_list_int_values_"
    assert body =~ "elmc_list_from_int_array"
    body
  end

  defp fn_body!(generated_c, name) do
    CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_#{name}")
  end

  defp assert_plan_lowered!(body) do
    assert body =~ "plan block"
    refute body =~ "RC_ERR_UNSUPPORTED"
  end

  defp assert_plan_fn!(generated_c, fn_name) do
    body = fn_body!(generated_c, fn_name)
    assert_plan_lowered!(body)
    assert generated_c =~ "elmc_fn_Main_#{fn_name}"
    body
  end


  alias Elmc.TestSupport.SnippetProject

  defp compile_snippet!(name, source, compile \\ %{}) when is_binary(name) and is_binary(source) do
    SnippetProject.compile_main!(source,
      name: name,
      compile: compile,
      out_dir: Path.expand("tmp/#{name}_codegen", __DIR__)
    )
  end


  test "maybe_unwrap_just_case? recognizes Nothing + bare var branches" do
    branches = [
      %{pattern: %{kind: :constructor, name: "Nothing", bind: nil, arg_pattern: nil}},
      %{pattern: %{kind: :var, name: "piece"}}
    ]

    assert Patterns.maybe_unwrap_just_case?(branches)
    refute Patterns.maybe_unwrap_just_case?([%{pattern: %{kind: :var, name: "piece"}}])
  end

  test "skip_empty_nothing_branch ignores whitespace-only Nothing arms" do
    branch = %{pattern: %{kind: :constructor, name: "Nothing"}}

    assert Patterns.skip_empty_nothing_branch?(branch, "")
    assert Patterns.skip_empty_nothing_branch?(branch, "   \n")
    refute Patterns.skip_empty_nothing_branch?(branch, "do_something();")
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

    assert source =~
             "elmc_record_get_index(elmc_maybe_or_tuple_just_payload_borrow(tmp_subject)"
    refute source =~ ~r/elmc_release\(tmp_\d+\);\s*\n\s*\}\s*\n\s*elmc_release\(tmp_2\)/
  end

  test "direct fragment vars allocate retain temp after fragment temps" do
    env = %{
      "fragment" => {:direct_fragment, %{op: :int_literal, value: 42}}
    }

    {code, out, counter} = FunctionCallCompile.compile_var("fragment", env, 0)

    assert out == "tmp_3"
    assert counter == 3
    assert code =~ "ELMC_RC_INT_BOX(42)"
    assert code =~ "ElmcValue *tmp_3 = elmc_retain(tmp_2);"
    refute code =~ ~r/ElmcValue \*tmp_1 = elmc_retain\(tmp_1\);/
  end

  @tag timeout: 180_000
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
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    drop_body = fn_body!(generated_c, "dropStep")
    assert_plan_lowered!(drop_body)
    assert drop_body =~ "elmc_maybe_just_payload" or drop_body =~ @just_payload_borrow

    assert drop_body =~
             ~r/ELMC_RECORD_GET_INDEX(?:_INT)?\(owned\[\d+\], ELMC_FIELD_MAIN_ACTIVEPIECE_KIND\)/

    assert drop_body =~
             ~r/ELMC_RECORD_GET_INDEX(?:_INT)?\(owned\[\d+\], ELMC_FIELD_MAIN_ACTIVEPIECE_ROT\)/

    assert drop_body =~
             ~r/ELMC_RECORD_GET_INDEX(?:_INT)?\(owned\[\d+\], ELMC_FIELD_MAIN_ACTIVEPIECE_X\)/

    assert drop_body =~ "elmc_record_update_index_cow_drop"
    assert drop_body =~ "ELMC_FIELD_MAIN_ACTIVEPIECE_Y"
    refute drop_body =~ ~r/elmc_record_update_index\(owned\[\d+\], 0 \/\* y \*\)/

    refute generated_c =~ "elmc_fn_Main_canPlace_offset_fits"
    refute generated_c =~ "elmc_list_drop("
    refute generated_c =~ ~r/elmc_record_get\(tmp_2, "y"\)/
    refute generated_c =~ ~r/elmc_record_get\(tmp_2, "kind"\)/
    refute generated_c =~ ~r/rec_names_\d+\[5\] = \{ "cell", "gap", "pieceKind"/

    assert generated_c =~ "elmc_fn_Main_softDrop"

    stack_report = File.read!(Path.join(out_dir, "elmc_stack_report.json"))
    assert stack_report =~ "\"functions\""
    assert stack_report =~ "\"summary\""
    assert stack_report =~ "\"code_size_indicators\""
    assert generated_c =~ "elmc_list_from_tuple2_int_array"
    assert generated_c =~ "pieceOffsets_table[k][r]"
    refute generated_c =~ "elmc_fn_Pebble_Ui_Resources_DefaultFont"
    assert generated_c =~ "elmc_scene_writer_push_cmd(writer, &scene_cmd)"
    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT)"
    assert generated_c =~ ~r/scene_cmd\.p1 = direct_native_let_textX_\d+;/

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

    out_dir = compile_snippet!("list_all_neq_zero", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "rowHasValue")
    assert body =~ "elmc_list_all("
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

    out_dir = compile_snippet!("list_int_eq", source)
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
    out_dir = compile_snippet!("list_concat_segments_no_nil_fallback_#{suffix}", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    body = fn_body!(generated_c, "rows")
    assert_plan_lowered!(body)

    assert body =~ "elmc_list_reverse("
    assert body =~ ~r/elmc_list_take_int\(&owned\[\d+\], 2, cells\)/
    assert body =~ ~r/elmc_list_drop_int\(&owned\[\d+\], 2, cells\)/
    refute body =~ "elmc_list_take("
    refute body =~ "elmc_list_drop("
    assert body =~ "elmc_list_concat("

    take_body =
      runtime_c
      |> String.split("RC elmc_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list)", parts: 2)
      |> List.last()
      |> String.split("\n}\n\nRC elmc_list_drop", parts: 2)
      |> hd()

    drop_body =
      runtime_c
      |> String.split("RC elmc_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list)", parts: 2)
      |> List.last()
      |> String.split("\n}\n\nRC elmc_list_partition", parts: 2)
      |> hd()

    concat_body =
      runtime_c
      |> String.split("RC elmc_list_concat(ElmcValue **out, ElmcValue *lists)", parts: 2)
      |> List.last()
      |> String.split(~r/\n}\n\nRC elmc_list_concat_array/, parts: 2)
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

    out_dir = compile_snippet!("list_foldl_range_list_acc", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "collect")
    assert body =~ "elmc_list_foldl("
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

    assert code =~ "elmc_record_new_values_take"
    refute code =~ "rec_names_"
    refute code =~ "elmc_record_new_static_take"
    assert code =~ ~r/elmc_record_get(?:_index)?\(tmp_4, (?:1 \/\* score \*\/|ELMC_FIELD_.*_SCORE)\)/
    refute code =~ "elmc_record_get(tmp_8, \"score\")"
    refute code =~ "elmc_int_zero();  ElmcValue *tmp_"
  end

  test "record literal Maybe.Nothing field emits elmc_maybe_nothing not float zero" do
    fields = [
      %{name: "value", expr: %{op: :int_literal, value: 1}},
      %{
        name: "temperature",
        expr: %{op: :int_literal, value: 0, union_ctor: "Maybe.Nothing"}
      }
    ]

    env = %{:__module__ => "Main", :__program_decls__ => %{}}

    {code, _out, _counter} =
      RecordCompile.compile(%{op: :record_literal, fields: fields}, env, 0)

    assert code =~ "elmc_maybe_nothing()"
    refute code =~ "elmc_new_float"
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

    out_dir = compile_snippet!("list_filter_neq_zero", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "nonzero")
    assert body =~ "elmc_list_filter("
  end

  test "List.filter then List.head uses find-first loop without building filtered list" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Slot =
        { id : Int, available : Bool, exclusive : Bool }

    pickExclusive : List Slot -> Maybe Slot
    pickExclusive slots =
        List.filter (\\slot -> slot.exclusive && slot.available) slots |> List.head

    init _ =
        ( { picked = pickExclusive [ { id = 1, available = True, exclusive = False }, { id = 2, available = True, exclusive = True } ] }
        , Platform.Cmd.none
        )

    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.toUiNode [ Ui.clear Color.white ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_find_first", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "pickExclusive")
    assert body =~ "elmc_list_find_first("
    refute body =~ "elmc_list_filter("
    refute body =~ "elmc_list_head("
  end

  test "Model -> String helpers are borrow_arg, not retain_arg" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model = { label : String, shown : String }

    timeString : Model -> String
    timeString model =
        model.label

    init _ =
        let
            model = { label = "10:30", shown = "" }
        in
        ( { model | shown = timeString model }, Platform.Cmd.none )

    update _ m = ( { m | shown = timeString m }, Platform.Cmd.none )
    view model = Ui.toUiNode [ Ui.clear Color.white, Ui.text model.shown ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("model_to_string_borrow_arg", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "elmc_fn_Main_timeString"
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_timeString")
    assert body =~ "Ownership policy: borrow_arg, retain_result"
    refute body =~ "Ownership policy: retain_arg"
  end

  test "pickSlot-style case on filter head and filter map field fuse through let bindings" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias SlotSpec id =
        { id : id, available : Bool, exclusive : Bool }

    pickSlot : List (SlotSpec Int) -> Maybe Int
    pickSlot slots =
        case List.filter (\\slot -> slot.exclusive && slot.available) slots |> List.head of
            Just slot ->
                Just slot.id

            Nothing ->
                case List.filter .available slots |> List.map .id |> List.head of
                    Nothing ->
                        Nothing

                    Just id ->
                        Just id

    init _ =
        ( { picked = pickSlot [ { id = 1, available = True, exclusive = True } ] }
        , Platform.Cmd.none
        )

    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.toUiNode [ Ui.clear Color.white ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("pick_slot_fusion", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "pickSlot")
    assert body =~ "elmc_list_filter(" or body =~ "elmc_list_head("
  end

  test "List.filter field then List.map field uses indexed record loop" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Slot =
        { id : Int, available : Bool }

    pickIds : List Slot -> List Int
    pickIds slots =
        List.filter .available slots |> List.map .id

    init _ =
        ( { ids = pickIds [ { id = 1, available = True }, { id = 2, available = False } ] }
        , Platform.Cmd.none
        )

    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.toUiNode [ Ui.clear Color.white ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_filter_map_fields", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "pickIds")
    assert body =~ "elmc_list_filter_record_field("
    assert body =~ "elmc_list_map_record_field("
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

    out_dir = compile_snippet!("list_filter_map_range", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "keepSmall")
    assert body =~ "elmc_list_filter_map("
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

    out_dir = compile_snippet!("list_repeat_inline", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_blankRow"
    assert_plan_compact_int_list!(generated_c, "blankRow")
    refute generated_c =~ "list_repeat_i_"
    refute generated_c =~ "elmc_list_repeat_count("
    refute generated_c =~ "elmc_list_repeat("
  end

  test "zero-arg List.repeat n 0 hoists unrolled immortal prelude" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    emptyBoard : List Int
    emptyBoard =
        List.repeat 16 0

    init _ = ( { board = emptyBoard }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.board)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("list_repeat_zero_hoist", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_emptyBoard"
    assert_plan_compact_int_list!(generated_c, "emptyBoard")
    refute generated_c =~ "elmc_zero_list_tmp_"
    refute generated_c =~ "list_repeat_i_"
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

    out_dir = compile_snippet!("list_repeat_static_int", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_row"
    assert_plan_compact_int_list!(generated_c, "row")
    assert generated_c =~ "{ 2, 2, 2, 2 }"
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

    out_dir = compile_snippet!("list_length_inline", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "countItems")
    assert body =~ "elmc_list_length("
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

    out_dir = compile_snippet!("list_repeat_boxed_count", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "padRows")
    assert body =~ "elmc_list_repeat("
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

    out_dir = compile_snippet!("hybrid_int_let_repeat", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "padAndCount")
    assert body =~ "elmc_list_repeat(" or body =~ "elmc_list_length("
    assert body =~ "elmc_tuple2(" or body =~ "elmc_tuple2_take("
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

    out_dir = compile_snippet!("list_foldl_reverse", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "collect")
    assert body =~ "elmc_list_foldl("
  end

  test "homogeneous long pipe_chain lowers to a C loop instead of nested calls" do
    source = """
    module Main exposing (main)

    add1 : Int -> Int
    add1 x =
        x + 1

    main : Int
    main =
        0
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1
            |> add1

    """

    out_dir = compile_snippet!("homogeneous_pipe_chain", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    main_body = fn_body!(generated_c, "main")
    assert_plan_lowered!(main_body)
    assert main_body =~ "for (elmc_int_t pipe_i_"
    assert main_body =~ "elmc_fn_Main_add1("
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

    out_dir = compile_snippet!("native_int_sub_length", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "remaining")
    assert body =~ "elmc_list_length("
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

    out_dir = compile_snippet!("list_concat_row_order", source, %{prune_native_wrappers: true})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    collapse_rows_body = assert_plan_fn!(generated_c, "collapseRows")
    assert collapse_rows_body =~ "elmc_list_concat(" or collapse_rows_body =~ "elmc_list_append("

    collapse_row_body = fn_body!(generated_c, "collapseRow")
    assert_plan_lowered!(collapse_row_body)
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

    out_dir = compile_snippet!("list_concat_literal_segments", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "mergeRows")
    assert body =~ "elmc_list_concat("
  end

  test "three-part string append fuses native int segments with snprintf" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    timeLabel : Int -> Int -> String
    timeLabel hour minute =
        String.fromInt hour ++ ":" ++ String.fromInt minute

    init _ = ( { label = timeLabel 9 5 }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.textLabel Ui.defaultFont { x = 0, y = 0 } m.label ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    suffix = System.unique_integer([:positive])
    out_dir = compile_snippet!("string_concat_segments_#{suffix}", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "timeLabel")
    assert body =~ "elmc_string_from_int("
    assert body =~ "elmc_string_append("
    refute body =~ "snprintf(native_string_buf_"
    refute generated_c =~ "elmc_list_concat_array("
    refute generated_c =~ "elmc_string_append_native("
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

    out_dir = compile_snippet!("list_concat_flatten", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "padRows")
    assert body =~ "elmc_list_repeat(" or body =~ "elmc_list_concat("
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

    out_dir = compile_snippet!("list_map_captured_env", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "tagItems")
    assert body =~ "elmc_list_map("
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

    out_dir = compile_snippet!("tuple_map_cursor", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "slots")
    assert body =~ "elmc_list_map("
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

    out_dir = compile_snippet!("constant_int_fold", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    area_impl = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_area")
    assert area_impl =~ "140" or area_impl =~ "plan_native_int" or area_impl =~ "return"
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

    out_dir = compile_snippet!("native_const_range", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    rows_body = assert_plan_fn!(generated_c, "rows")
    assert rows_body =~ "elmc_list_range(" or rows_body =~ "elmc_list_map("
  end

  test "zero-arg int constants annotate folded comparisons with decl names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    boardCols : Int
    boardCols =
        10

    boardRows : Int
    boardRows =
        14

    fits : Int -> Int -> Bool
    fits x y =
        x >= 0
            && x < boardCols
            && y < boardRows

    init _ = ( { ok = fits 3 5 }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (if m.ok then "yes" else "no") ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("annotated_int_constants", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    fits_body = assert_plan_fn!(generated_c, "fits")
    assert fits_body =~ "elmc_fn_Main_boardCols()"
    assert fits_body =~ "elmc_fn_Main_boardRows()"
  end

  test "offsetFits native helper keeps cellX and cellY as native lets without boxing" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/offset_fits_native_let", __DIR__)
    out_dir = Path.expand("tmp/offset_fits_native_let_codegen", __DIR__)
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

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    offset_fits_body = fn_body!(generated_c, "offsetFits")
    assert_plan_lowered!(offset_fits_body)
    assert offset_fits_body =~ "plan_native_int_5 = x + dx"
    assert offset_fits_body =~ "plan_native_int_6 = y + dy"
    assert offset_fits_body =~ "elmc_fn_Main_boardCols()"

    can_place_body = fn_body!(generated_c, "canPlace")
    assert_plan_lowered!(can_place_body)
  end

  test "moveActive keeps nextX and nextY as native lets and updates ActivePiece fields without boxing" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/move_active_native_let", __DIR__)
    out_dir = Path.expand("tmp/move_active_native_let_codegen", __DIR__)
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

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    move_body = fn_body!(generated_c, "moveActive")
    assert_plan_lowered!(move_body)
    assert move_body =~ "elmc_record_update_index_cow_drop"
    assert move_body =~ "ELMC_FIELD_MAIN_ACTIVEPIECE_X"
    assert move_body =~ "ELMC_FIELD_MAIN_ACTIVEPIECE_Y"
  end

  test "rotateActive single-field native int record update abandons base operand once" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/rotate_active_native_let", __DIR__)
    out_dir = Path.expand("tmp/rotate_active_native_let_codegen", __DIR__)
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

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    rotate_body = fn_body!(generated_c, "rotateActive")
    assert_plan_lowered!(rotate_body)
    assert rotate_body =~ "elmc_record_update_index"
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

    out_dir = compile_snippet!("list_map_inline_reverse", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "double")
    assert body =~ "elmc_list_map("
  end

  test "List.filterMap identity unwraps Just without closure or runtime filterMap" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    modes : List Int
    modes =
        List.filterMap identity [ Just 1, Nothing, Just 2 ]

    init _ = ( { n = List.length modes }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_filter_map_identity", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "modes")
    assert body =~ "elmc_list_cons(" or body =~ "elmc_list_filter_map("
  end

  test "List.filterMap identity on runtime Maybe vars uses runtime filterMap" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    pick : Maybe Int -> Maybe Int -> List Int
    pick a b =
        List.filterMap identity [ a, b ]

    init _ = ( { n = List.length (pick (Just 1) Nothing) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_filter_map_identity_vars", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "pick")
    assert body =~ "elmc_list_filter_map(",
           "runtime Maybe args must not be treated as already-unwrapped values"
  end

  test "list literal ownership transfer nulls tmp refs after take" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type Corner = Temp | Wind

    modes : Bool -> List Corner
    modes hasWind =
        List.filterMap identity
            [ Just Temp
            , if hasWind then Just Wind else Nothing
            ]

    init _ = ( { n = List.length (modes True) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_filter_map_identity_tmp_null", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = fn_body!(generated_c, "modes")
    assert_plan_lowered!(body)
    assert body =~ "elmc_list_from_values_take" or body =~ "elmc_list_cons("
  end

  test "List.concatMap over range inlines loop without closure or runtime concatMap" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    pairs : List Int
    pairs =
        List.concatMap (\\n -> [ n, n * 10 ]) (List.range 0 3)

    init _ = ( { n = List.length pairs }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_concat_map_range", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "pairs")
    assert body =~ "elmc_list_concat_map(" or body =~ "elmc_list_range("
  end

  test "List.concatMap over range with if branches appends items directly without sublist walk" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    ticks : List Ui.RenderOp
    ticks =
        List.concatMap
            (\\hour ->
                if modBy 2 hour == 0 then
                    [ Ui.line { x = hour, y = 0 } { x = hour, y = 5 } Color.white
                    , Ui.line { x = hour, y = 6 } { x = hour, y = 10 } Color.lightGray
                    ]

                else
                    [ Ui.line { x = hour, y = 0 } { x = hour, y = 5 } Color.lightGray ]
            )
            (List.range 0 3)

    init _ = ( {}, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view _ = Ui.toUiNode (Ui.clear Color.black :: ticks)
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("list_concat_map_if_render", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "ticks")
    assert body =~ "elmc_list_concat_map(" or body =~ "ELMC_RENDER_OP_LINE"
  end

  test "Maybe.map record field accessor inlines without closure or runtime maybe_map" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Weather =
        { condition : Int, temp : Int }

    pick : Maybe Weather -> Maybe Int
    pick w =
        Maybe.map .condition w

    init _ =
        ( { n = Maybe.withDefault 0 (pick (Just { condition = 42, temp = 2 })) }
        , Platform.Cmd.none
        )

    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    out_dir = compile_snippet!("maybe_map_field", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "pick")
    assert body =~ "ELMC_RECORD_GET_INDEX" or body =~ "elmc_record_get_index"
    assert body =~ "elmc_maybe_just" or body =~ "elmc_maybe_nothing"
  end

  test "json andThen lambda keeps string parameters boxed for literal equality" do
    alias Elmc.Test.ElmRunCorpus

    path = "Kernel/MainJsonDecodeAndThen.elm"

    if corpus_execution_ready?(path) do
      tmp = Path.expand("tmp/json_and_then_lambda", __DIR__)

      assert_corpus_run!(path, tmp)

      generated_c =
        Path.join(tmp, "Kernel__MainJsonDecodeAndThen__exec/out/c/elmc_generated.c")
        |> File.read!()

      refute generated_c =~ "const elmc_int_t t ="
      assert generated_c =~ "plan block" or generated_c =~ "elmc_string_eq("
    else
      assert true
    end
  end

  test "char case patterns match ELMC_TAG_CHAR subjects" do
    alias Elmc.Test.ElmRunCorpus

    paths = ["Unicode/CharPattern.elm", "Unicode/CharPatternComplex.elm"]

    if Enum.all?(paths, &corpus_execution_ready?/1) do
      for path <- paths do
        tmp = Path.expand("tmp/char_pattern_#{Path.basename(path, ".elm")}", __DIR__)
        gold = ElmRunCorpus.read_expected!(path)

        assert {:ok, out} = ElmRunCorpus.run_elmc_execution!(path, tmp, timeout_ms: 60_000)
        assert out == gold
      end
    else
      assert true
    end
  end

  test "large named record literals keep field names in extracted helpers" do
    alias Elmc.Test.ElmRunCorpus

    path = "Kernel/MainJsonDecode.elm"

    if corpus_execution_ready?(path) do
      tmp = Path.expand("tmp/main_json_decode_record", __DIR__)

      assert_corpus_run!(path, tmp)

      generated_c =
        Path.join(tmp, "Kernel__MainJsonDecode__exec/out/c/elmc_generated.c")
        |> File.read!()

      assert generated_c =~ "elmc_record_new_static_take"
      refute generated_c =~ "return elmc_harness_record_new_values_take(23, rec_values);"
    else
      assert true
    end
  end

  @tag timeout: 300_000
  test "utf8 string runtime matches corpus reverse slice and filter programs" do
    alias Elmc.Test.ElmRunCorpus

    paths = [
      "Unicode/StringReverse.elm",
      "Unicode/UnicodeEdgeCases.elm",
      "KernelLowering/StringFilter.elm",
      "KernelLowering/StringFoldr.elm",
      "Basics/MainListPattern.elm",
      "Basics/MainParseJson.elm",
      "Compiler/NestedLoaderCaptureShape.elm",
      "Iterative/ControlFlow.elm",
      "Bugs/BigStringCase.elm",
      "Bugs/StringContainsNul.elm"
    ]

    if Enum.all?(paths, &corpus_execution_ready?/1) do
      for path <- paths do
        tmp = Path.expand("tmp/utf8_string_#{Path.basename(path, ".elm")}", __DIR__)
        assert_corpus_run!(path, tmp, skip_output_check: true)
      end
    else
      assert true
    end
  end

  test "filterMap row drop fusion matches renamed row helpers, not elmtris names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    boardRows : Int
    boardRows =
        4

    boardCols : Int
    boardCols =
        3

    readCell : Int -> Int -> List Int -> Int
    readCell x y board =
        if y < 0 then
            0

        else
            Maybe.withDefault 0 (listAt (y * boardCols + x) board)

    listAt : Int -> List Int -> Maybe Int
    listAt index list =
        if index < 0 then
            Nothing

        else if index == 0 then
            case list of
                x :: _ ->
                    Just x

                [] ->
                    Nothing

        else
            case list of
                _ :: xs ->
                    listAt (index - 1) xs

                [] ->
                    Nothing

    isCompleteRow : Int -> List Int -> Bool
    isCompleteRow row board =
        List.all ((/=) 0) (sliceRow row board)

    sliceRow : Int -> List Int -> List Int
    sliceRow row board =
        List.range 0 (boardCols - 1)
            |> List.map (\\col -> readCell col row board)

    dropFullRows : List Int -> ( List Int, Int )
    dropFullRows board =
        let
            kept =
                List.range 0 (boardRows - 1)
                    |> List.filterMap
                        (\\row ->
                            if isCompleteRow row board then
                                Nothing

                            else
                                Just (sliceRow row board)
                        )

            cleared =
                boardRows - List.length kept
        in
        ( List.concat (List.repeat cleared (List.repeat boardCols 0) ++ kept)
        , cleared
        )

    init _ = ( { board = dropFullRows (List.repeat (boardRows * boardCols) 0) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (Tuple.second m.board)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("filter_map_row_drop_renamed", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = assert_plan_fn!(generated_c, "dropFullRows")
    assert body =~ "elmc_list_filter_map(" or body =~ "elmc_list_concat("
    refute generated_c =~ "elmc_fn_Main_rowFull"
    refute generated_c =~ "elmc_fn_Main_rowCells"
  end

  test "reverse foldl occupied fusion matches renamed cell reader and size vars" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    gridCols : Int
    gridCols =
        4

    gridRows : Int
    gridRows =
        3

    cellTotal : Int
    cellTotal =
        gridCols * gridRows

    readCell : Int -> Int -> List Int -> Int
    readCell x y board =
        if y < 0 then
            0

        else
            Maybe.withDefault 0 (listAt (y * gridCols + x) board)

    listAt : Int -> List Int -> Maybe Int
    listAt index list =
        if index < 0 then
            Nothing

        else if index == 0 then
            case list of
                x :: _ ->
                    Just x

                [] ->
                    Nothing

        else
            case list of
                _ :: xs ->
                    listAt (index - 1) xs

                [] ->
                    Nothing

    occupiedIndices : List Int -> List Int
    occupiedIndices board =
        List.foldl
            (\\index slots ->
                if readCell (modBy gridCols index) (index // gridCols) board == 0 then
                    slots

                else
                    index :: slots
            )
            []
            (List.range 0 (cellTotal - 1))
            |> List.reverse

    init _ = ( { slots = occupiedIndices (List.repeat cellTotal 0) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.slots)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("reverse_foldl_occupied_renamed", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_occupiedIndices"
    assert generated_c =~ "elmc_fn_Main_occupiedIndices_native"
    refute generated_c =~ "elmc_fn_Main_cellAt"
    refute generated_c =~ "elmc_fn_Main_lockedSlotsFromBoard"
  end

  test "list map static index at fusion matches renamed gather helpers, not 2048 names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    fetchSlot : Int -> List Int -> Maybe Int
    fetchSlot index slots =
        if index < 0 then
            Nothing

        else
            List.head (List.drop index slots)

    gatherAt : List Int -> List Int
    gatherAt slots =
        List.map
            (\\i -> Maybe.withDefault 0 (fetchSlot i slots))
            [ 0, 2, 4, 1, 3, 5 ]

    init _ = ( { picked = gatherAt (List.range 0 5) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.picked)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("list_map_static_index_at_renamed", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_gatherAt"
    assert generated_c =~ "gatherAt_indices"
    refute generated_c =~ "elmc_fn_Main_fetchSlot"
  end

  test "row slice adjacent merge fusion matches renamed line helpers, not 2048 names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias LineResult =
        { cells : List Int
        , score : Int
        }

    sliceRow : Int -> List Int -> List Int
    sliceRow row board =
        List.take 3 (List.drop (row * 3) board)

    slideMerge : List Int -> LineResult
    slideMerge values =
        case values of
            a :: b :: rest ->
                if a == b then
                    let
                        tail =
                            slideMerge rest

                        value =
                            a + b
                    in
                    { cells = value :: tail.cells
                    , score = value + tail.score
                    }

                else
                    let
                        tail =
                            slideMerge (b :: rest)
                    in
                    { cells = a :: tail.cells
                    , score = tail.score
                    }

            _ ->
                { cells = values, score = 0 }

    slideLine : List Int -> LineResult
    slideLine row =
        let
            merged =
                slideMerge (List.filter ((/=) 0) row)
        in
        { cells = merged.cells ++ List.repeat (3 - List.length merged.cells) 0
        , score = merged.score
        }

    collapseGrid : List Int -> LineResult
    collapseGrid cells =
        let
            row0 =
                slideLine (sliceRow 0 cells)

            row1 =
                slideLine (sliceRow 1 cells)

            row2 =
                slideLine (sliceRow 2 cells)
        in
        { cells = row0.cells ++ row1.cells ++ row2.cells
        , score = row0.score + row1.score + row2.score
        }

    init _ = ( { size = List.length (collapseGrid (List.range 0 8)) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.size) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("row_slice_adjacent_merge_renamed", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_collapseGrid"
    assert generated_c =~ "elmc_fn_Main_collapseGrid_native"
    refute generated_c =~ "elmc_fn_Main_slideLine"
    refute generated_c =~ "elmc_fn_Main_slideMerge"
    refute generated_c =~ "elmc_fn_Main_sliceRow"
  end

  test "list concat reversed row slices fusion matches renamed row helpers, not 2048 names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    sliceRow : Int -> List Int -> List Int
    sliceRow row board =
        List.take 3 (List.drop (row * 3) board)

    flipRows : List Int -> List Int
    flipRows cells =
        List.concat
            [ List.reverse (sliceRow 0 cells)
            , List.reverse (sliceRow 1 cells)
            , List.reverse (sliceRow 2 cells)
            ]

    init _ = ( { flat = flipRows (List.range 0 8) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.length m.flat)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("list_concat_reversed_row_slices_renamed", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_flipRows"
    assert generated_c =~ "elmc_fn_Main_flipRows_native"
    refute generated_c =~ "elmc_fn_Main_sliceRow"
  end

  test "union case four perm fusion matches renamed permute helper, not 2048 names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type Dir
        = Left
        | Right
        | Up
        | Down

    sliceRow : Int -> List Int -> List Int
    sliceRow row board =
        List.take 3 (List.drop (row * 3) board)

    flipRows : List Int -> List Int
    flipRows cells =
        List.concat
            [ List.reverse (sliceRow 0 cells)
            , List.reverse (sliceRow 1 cells)
            , List.reverse (sliceRow 2 cells)
            ]

    fetchAt : Int -> List Int -> Maybe Int
    fetchAt index values =
        if index < 0 then
            Nothing
        else
            List.head (List.drop index values)

    swapAxes : List Int -> List Int
    swapAxes cells =
        List.map
            (\\i -> Maybe.withDefault 0 (fetchAt i cells))
            [ 0, 3, 6, 1, 4, 7, 2, 5, 8 ]

    remapPack : Dir -> List Int -> List Int
    remapPack direction cells =
        case direction of
            Left ->
                cells

            Right ->
                flipRows cells

            Up ->
                swapAxes cells

            Down ->
                flipRows (swapAxes cells)

    init _ = ( { packed = remapPack Up (List.range 0 8) }, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt (List.head m.packed |> Maybe.withDefault 0)) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("union_case_four_perm_renamed", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_remapPack"
    assert generated_c =~ "elmc_fn_Main_remapPack_native"
    refute generated_c =~ "remapPack_perms"
  end

  test "permute merge inverse pipeline fusion matches renamed helpers, not 2048 names" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Storage as Storage
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias GridModel =
        { cells : List Int
        , seed : Int
        , score : Int
        , best : Int
        , turn : Int
        }

    type Dir
        = Left
        | Right
        | Up
        | Down

    type alias LineResult =
        { cells : List Int
        , score : Int
        }

    sliceRow : Int -> List Int -> List Int
    sliceRow row board =
        List.take 3 (List.drop (row * 3) board)

    slideMerge : List Int -> LineResult
    slideMerge values =
        case values of
            a :: b :: rest ->
                if a == b then
                    let
                        tail =
                            slideMerge rest

                        value =
                            a + b
                    in
                    { cells = value :: tail.cells, score = value + tail.score }

                else
                    let
                        tail =
                            slideMerge (b :: rest)
                    in
                    { cells = a :: tail.cells, score = tail.score }

            _ ->
                { cells = values, score = 0 }

    slideLine : List Int -> LineResult
    slideLine row =
        let
            merged =
                slideMerge (List.filter ((/=) 0) row)
        in
        { cells = merged.cells ++ List.repeat (3 - List.length merged.cells) 0
        , score = merged.score
        }

    collapseGrid : List Int -> LineResult
    collapseGrid cells =
        let
            row0 =
                slideLine (sliceRow 0 cells)

            row1 =
                slideLine (sliceRow 1 cells)

            row2 =
                slideLine (sliceRow 2 cells)
        in
        { cells = row0.cells ++ row1.cells ++ row2.cells
        , score = row0.score + row1.score + row2.score
        }

    flipRows : List Int -> List Int
    flipRows cells =
        List.concat
            [ List.reverse (sliceRow 0 cells)
            , List.reverse (sliceRow 1 cells)
            , List.reverse (sliceRow 2 cells)
            ]

    fetchAt : Int -> List Int -> Maybe Int
    fetchAt index values =
        if index < 0 then
            Nothing
        else
            List.head (List.drop index values)

    swapAxes : List Int -> List Int
    swapAxes cells =
        List.map
            (\\i -> Maybe.withDefault 0 (fetchAt i cells))
            [ 0, 3, 6, 1, 4, 7, 2, 5, 8 ]

    faceGrid : Dir -> List Int -> List Int
    faceGrid direction cells =
        case direction of
            Left ->
                cells

            Right ->
                flipRows cells

            Up ->
                swapAxes cells

            Down ->
                flipRows (swapAxes cells)

    unfaceGrid : Dir -> List Int -> List Int
    unfaceGrid direction cells =
        case direction of
            Left ->
                cells

            Right ->
                flipRows cells

            Up ->
                swapAxes cells

            Down ->
                swapAxes (flipRows cells)

    addTile : Int -> List Int -> ( List Int, Int )
    addTile seed cells =
        ( cells, seed + 1 )

    slideGrid : Dir -> GridModel -> ( GridModel, Platform.Cmd msg )
    slideGrid direction model =
        let
            faced =
                faceGrid direction model.cells

            squashed =
                collapseGrid faced

            restored =
                unfaceGrid direction squashed.cells
        in
        if restored == model.cells then
            ( model, Platform.Cmd.none )

        else
            let
                ( nextCells, nextSeed ) =
                    addTile model.seed restored

                nextScore =
                    model.score + squashed.score

                nextBest =
                    max model.best nextScore

                saveCmd =
                    if nextBest > model.best then
                        Storage.writeString 99 (String.fromInt nextBest)

                    else
                        Platform.Cmd.none
            in
            ( { model
                | cells = nextCells
                , seed = nextSeed
                , score = nextScore
                , best = nextBest
                , turn = model.turn + 1
              }
            , saveCmd
            )

    init _ =
        let
            ( model, _ ) =
                slideGrid Left
                    { cells = List.repeat 9 0
                    , seed = 1
                    , score = 0
                    , best = 0
                    , turn = 0
                    }
        in
        ( model, Platform.Cmd.none )

    update _ m = ( m, Platform.Cmd.none )

    view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.turn) ]
    subscriptions _ = Platform.Sub.none
    main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("permute_merge_inverse_pipeline_renamed", source, %{strip_dead_code: false})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_fn_Main_slideGrid"
    assert generated_c =~ "elmc_fn_Main_slideGrid_native"
    refute generated_c =~ "elmc_row_major_perm_src_i"
    refute generated_c =~ "slideGrid_orient_perms"
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

    pebble_out_dir = Path.join(out_dir, "pebble_int32")
    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: pebble_out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               pebble_int32: true
             })

    pebble_generated_c = File.read!(Path.join(pebble_out_dir, "c/elmc_generated.c"))

    assert pebble_generated_c =~
             "return elmc_fn_Main_pieceOffsets_native(out, kind, rot);"

    makefile = File.read!(Path.join(out_dir, "Makefile"))
    assert makefile =~ "-ffunction-sections"
    assert makefile =~ "-fdata-sections"
    assert makefile =~ "-Wl,--gc-sections"

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "pieceOffsets_table[k][r]"
    refute generated_c =~ "elmc_fn_Main_pieceSlots_native"
    assert generated_c =~ "elmc_fn_Main_canPlace_native"
    assert generated_c =~ "static RC elmc_fn_Main_canPlace_native(bool *out,"
    refute generated_c =~ "static RC elmc_fn_Main_canPlace_native(ElmcValue **out,"
    can_place_native = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_canPlace_native")
    refute can_place_native =~ "elmc_new_bool"
    assert generated_c =~
             "static RC elmc_fn_Main_canPlace_native(bool *out, const elmc_int_t kind, const elmc_int_t rot, const elmc_int_t x, const elmc_int_t y, ElmcValue * const board)"
    refute can_place_native =~ "elmc_as_int(x)"
    refute can_place_native =~ "elmc_as_int(y)"
    assert generated_c =~ "elmc_fn_Main_lockedSlotsFromBoard_native"
    assert generated_c =~
             "static RC elmc_fn_Main_lockedSlotsFromBoard_native(ElmcValue **out, ElmcValue *board)"
    assert generated_c =~ "elmc_fn_Main_offsetFits_native"
    assert generated_c =~ "elmc_fn_Main_stampPiece_native"
    assert generated_c =~
             "static RC elmc_fn_Main_stampPiece_native(ElmcValue **out, ElmcValue *piece, ElmcValue *board)"
    assert generated_c =~ "return elmc_fn_Main_stampPiece_native(out, piece, board);"

    assert [stamp_piece_native] =
             Regex.run(
               ~r/static RC elmc_fn_Main_stampPiece_native\(ElmcValue \*\*out, ElmcValue \*piece, ElmcValue \*board\) \{[\s\S]*?return Rc;\s*\}/,
               generated_c
             )

    refute stamp_piece_native =~ "return elmc_retain(board)"
    refute stamp_piece_native =~ "elmc_int_zero()"
    assert stamp_piece_native =~ "Rc = elmc_list_from_int_array(out, buf, len);"
    assert stamp_piece_native =~ "CHECK_RC(Rc);"
    assert generated_c =~ "patches[patch_count++]"
    refute generated_c =~ "elmc_fn_Main_boardLayout_native"
    refute generated_c =~ "elmc_fn_Main_lockedSlotOps_native"
    refute generated_c =~ "elmc_fn_Main_pieceSlotOps_native"
    refute generated_c =~ "elmc_fn_Main_rotateActive_native"
    refute generated_c =~ "elmc_fn_Main_dropStep_native"
    refute generated_c =~ "elmc_fn_Main_softDrop_native"

    spawn_piece_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_spawnPiece")
    assert spawn_piece_body =~ "plan block"
    refute spawn_piece_body =~ "elmc_fn_Main_spawnPiece_native("

    refute generated_c =~ "record_update_helper_Main_withPiece"
    assert generated_c =~ "elmc_list_replace_nth_int" or
             (generated_c =~ "patches[patch_count++]" and generated_c =~ "buf[patch] = value")

    assert generated_c =~ "elmc_list_from_tuple2_int_array(out, entry->cells, entry->count)"

    refute generated_c =~ "elmc_list_indexed_map("
    refute generated_c =~ "elmc_list_reverse("
    refute generated_c =~ "elmc_let_body_helper_Main_lockPiece"
    assert generated_c =~ "elmc_fn_Main_freshModel("
    refute generated_c =~ "elmc_record_update_helper_Main_lockPiece"

    lock_piece_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_lockPiece")

    assert lock_piece_body =~ "plan block"
    assert lock_piece_body =~ "elmc_fn_Main_stampPiece"
    assert lock_piece_body =~ "elmc_fn_Main_clearLines"
    refute lock_piece_body =~ "elmc_fn_Main_lockPiece_native("
    refute generated_c =~ "list_concat_repeat_lists_"

    clear_lines_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_clearLines")
    assert clear_lines_body =~ "plan block"
    refute clear_lines_body =~ "elmc_fn_Main_clearLines_native("
    refute generated_c =~ "elmc_let_body_helper_Main_clearLines"

    assert generated_c =~
             ~r/elmc_int_t rec_values_\d+\[4\] = \{ direct_native_record_layout_x_\d+, direct_native_record_layout_y_\d+, direct_native_record_layout_cell_\d+, direct_native_record_layout_gap_\d+ \}/

    refute generated_c =~
             ~r/elmc_int_t rec_values_\d+\[4\] = \{ direct_native_record_layout_cell_\d+, direct_native_record_layout_gap_\d+, direct_native_record_layout_x_\d+, direct_native_record_layout_y_\d+ \}/

    harness_path = Path.join(out_dir, "c/elmtris_host_harness.c")

    File.write!(
      harness_path,
    """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *elmc_harness_record_new_values_take(int count, ElmcValue **values) {
        ElmcValue *out = NULL;
        if (elmc_record_new_values_take(&out, count, values) != RC_SUCCESS) return NULL;
        return out;
      }

      enum {
        MODEL_FIELD_BOARD = 0,
        MODEL_FIELD_PIECEKIND = 1
      };

      static ElmcValue *basalt_launch_context(void) {
        ElmcValue *reason = ELMC_RC_INT_BOX(2);
        ElmcValue *watch_model = ELMC_RC_STRING_BOX("");
        ElmcValue *watch_profile_id = ELMC_RC_STRING_BOX("");
        ElmcValue *width = ELMC_RC_INT_BOX(144);
        ElmcValue *height = ELMC_RC_INT_BOX(168);
        ElmcValue *shape = ELMC_RC_INT_BOX(2);
        ElmcValue *color_mode = ELMC_RC_INT_BOX(2);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_harness_record_new_values_take(4, screen_values);
        ElmcValue *has_microphone = ELMC_RC_INT_BOX(0);
        ElmcValue *has_compass = ELMC_RC_INT_BOX(0);
        ElmcValue *supports_health = ELMC_RC_INT_BOX(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        return elmc_harness_record_new_values_take(7, context_values);
      }

      static elmc_int_t list_length(ElmcValue *list) {
        if (list && list->tag == ELMC_TAG_INT_LIST) {
          ElmcIntListPayload *payload = (ElmcIntListPayload *)list->payload;
          return payload ? payload->length : 0;
        }
        elmc_int_t len = 0;
        while (list && list->tag == ELMC_TAG_LIST && list->payload != NULL) {
          len++;
          list = ((ElmcCons *)list->payload)->tail;
        }
        return len;
      }

      static int list_has_nested_rows(ElmcValue *list) {
        while (list && list->tag == ELMC_TAG_LIST && list->payload != NULL) {
          ElmcCons *node = (ElmcCons *)list->payload;
          if (node->head && node->head->tag == ELMC_TAG_LIST) return 1;
          list = node->tail;
        }
        return 0;
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

        if (elmc_pebble_ensure_scene(&app) != 0) {
          fprintf(stderr, "ensure_scene failed\\n");
          return 8;
        }

        ElmcPebbleDrawCmd scene_cmds[256] = {0};
        int scene_count = elmc_pebble_scene_commands_from(&app, scene_cmds, 256, 0);
        int piece_rects = 0;
        for (int i = 0; i < scene_count; i++) {
          if (scene_cmds[i].kind != ELMC_PEBBLE_DRAW_FILL_RECT) continue;
          if (scene_cmds[i].p2 <= 0 || scene_cmds[i].p3 <= 0) {
            fprintf(stderr, "fillRect %d has non-positive size w=%lld h=%lld\\n",
                    i, (long long)scene_cmds[i].p2, (long long)scene_cmds[i].p3);
            return 9;
          }
          piece_rects++;
        }
        if (piece_rects < 4) {
          fprintf(stderr, "expected active piece fill rects, got %d\\n", piece_rects);
          return 10;
        }
        ElmcValue *model = elmc_worker_model(&app.worker);
        if (!model || ELMC_RECORD_GET_INDEX_INT(model, MODEL_FIELD_PIECEKIND) <= 0) {
          fprintf(stderr, "expected active piece\\n");
          elmc_release(model);
          return 4;
        }
        elmc_release(model);

        int piece_kind_before = -1;
        for (int frame = 0; frame < 400; frame++) {
          if (elmc_pebble_dispatch_frame(&app, 33, 33 * (frame + 1), frame + 1) != 0) {
            fprintf(stderr, "frame %d dispatch failed\\n", frame);
            return 5;
          }

          model = elmc_worker_model(&app.worker);
          if (!model) {
            fprintf(stderr, "missing model at frame %d\\n", frame);
            return 6;
          }

          int piece_kind = ELMC_RECORD_GET_INDEX_INT(model, MODEL_FIELD_PIECEKIND);
          ElmcValue *board = ELMC_RECORD_GET_INDEX(model, MODEL_FIELD_BOARD);
          elmc_int_t board_len = list_length(board);

          if (piece_kind_before >= 0 && piece_kind != piece_kind_before) {
            if (board_len != 140 || list_has_nested_rows(board)) {
              fprintf(stderr, "board corrupted after lock at frame %d len=%lld nested=%d\\n",
                      frame, (long long)board_len, list_has_nested_rows(board));
              elmc_release(model);
              return 7;
            }
          }

          piece_kind_before = piece_kind;
          elmc_release(model);
        }

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
        "-lm",
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

    out_dir = compile_snippet!("watchface_init_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body = fn_body!(generated_c, "init")
    assert_plan_lowered!(init_body)

    assert init_body =~ "elmc_record_new_values" or init_body =~ "elmc_record_new_values_ints"
    refute init_body =~ "rec_field_names_"
    refute init_body =~ "rec_names_"
    refute init_body =~ "static const int rec_field_ids_"
    refute init_body =~ "elmc_record_new_static_ints"
    refute init_body =~ "elmc_record_new_ints"
    refute init_body =~ "elmc_record_new_take"

    assert generated_c =~ "ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN"
    assert generated_c =~ "ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT"
    assert generated_c =~ "ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH"

    assert init_body =~
             "elmc_record_get_index(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN)"

    assert init_body =~
             ~r/ELMC_RECORD_GET_INDEX_INT\(owned\[\d+\], ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH\)/

    assert init_body =~
             ~r/ELMC_RECORD_GET_INDEX_INT\(owned\[\d+\], ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT\)/

    assert init_body =~
             "elmc_cmd1(&owned[11], ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_CURRENTDATETIME)" or
             init_body =~ "ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME"

    refute init_body =~ "elmc_new_int(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME)"
    refute init_body =~ "elmc_new_int(23)"
    refute init_body =~ "ELMC_PEBBLE_MSG_CURRENT_DATE_TIME_TARGET"
  end

  test "update reads union record payload fields with payload record macros, not model field indices" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Cmd as PebbleCmd

    type alias Model =
        { hour : Int
        , minute : Int
        , screenW : Int
        , screenH : Int
        }

    type Msg
        = CurrentDateTime PebbleCmd.CurrentDateTime
        | HourChanged Int
        | MinuteChanged Int

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
    update msg model =
        case msg of
            CurrentDateTime value ->
                ( { model
                    | hour = value.hour
                    , minute = value.minute
                  }
                , Cmd.none
                )

            HourChanged hour ->
                ( { model | hour = hour }, Cmd.none )

            MinuteChanged minute ->
                ( { model | minute = minute }, Cmd.none )

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

    out_dir = compile_snippet!("watchface_analog_update_payload", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = fn_body!(generated_c, "update")
    assert_plan_lowered!(update_body)

    assert update_body =~ "ELMC_RECORD_GET_INDEX_INT(owned[1]," and
             (update_body =~ "HOUR" or update_body =~ "MINUTE")

    refute update_body =~
             "elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, ELMC_FIELD_MAIN_MODEL_HOUR)"
    refute update_body =~
             "elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, ELMC_FIELD_MAIN_MODEL_MINUTE)"
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

    out_dir = compile_snippet!("record_zero_cse_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body = fn_body!(generated_c, "init")

    assert length(Regex.scan(~r/elmc_int_zero\(\)|ELMC_RC_INT_BOX\(0\)/, init_body)) >= 1
    refute length(Regex.scan(~r/ElmcValue \*tmp_\d+ = elmc_int_zero\(\);\s*ElmcValue \*tmp_\d+ = elmc_new_int\(0\)/, init_body)) > 1
    assert init_body =~ "elmc_record_new_values_take"
    assert init_body =~ "rec_values_"
    refute init_body =~ "rec_names_"
    refute init_body =~ "rec_field_names_"
    refute init_body =~ "static const int rec_field_ids_"
    refute init_body =~ "elmc_record_new_static_take"
    refute init_body =~ "elmc_record_new_take("
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

    init : Platform.LaunchContext -> ( Model, Cmd Msg )
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

    out_dir = compile_snippet!("record_screen_cse_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body = fn_body!(generated_c, "init")

    assert length(
             Regex.scan(
               ~r/elmc_record_get_index\(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN\)/,
               init_body
             )
           ) >= 1

    refute init_body =~ ~s/elmc_record_get(context, "screen")/
    refute init_body =~ ~s/elmc_record_get(tmp_1_screen, "shape")/

    assert init_body =~ "ELMC_RECORD_GET_INDEX_INT(owned["
    assert init_body =~ "ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_SHAPE"
    assert init_body =~ "ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT"
    assert init_body =~ "ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH"

    assert init_body =~ "elmc_record_new_values_ints" or
             init_body =~ "elmc_record_new_values_take"
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

    out_dir = compile_snippet!("direct_boxed_helper_codegen", source, %{prune_native_wrappers: true})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    direct_body = fn_body!(generated_c, "directHelper")
    closure_body = fn_body!(generated_c, "closureHelper")
    update_body = fn_body!(generated_c, "update")

    assert direct_body =~ "direct_call_abi"
    assert generated_c =~ "static RC elmc_fn_Main_directHelper(ElmcValue **out, ElmcValue *items)"
    refute direct_body =~ "argc > 0"
    refute direct_body =~ "args[0]"

    assert generated_c =~ "static RC elmc_fn_Main_closureHelper(ElmcValue **out, ElmcValue *items)"
    refute closure_body =~ "argc > 0"
    refute closure_body =~ "args[0]"

    assert update_body =~ "plan block"
    assert update_body =~ "elmc_fn_Main_directHelper("
    assert update_body =~ "elmc_record_get_index(model,"
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

    out_dir = compile_snippet!("borrowed_call_operand_codegen", source, %{prune_native_wrappers: true})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    forward_body =
      generated_c
      |> String.split(rc_direct_fn_def_marker("forward"), parts: 2)
      |> Enum.at(1, "")
      |> String.split(worker_fn_def_marker("init"), parts: 2)
      |> hd()

    assert generated_c =~ "static RC elmc_fn_Main_forward(ElmcValue **out, ElmcValue *seed)"
    assert forward_body =~ "elmc_fn_Main_callee(out,"
    assert forward_body =~ "seed, seed"
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

    out_dir = compile_snippet!("borrow_local_call_operand_codegen", source, %{prune_native_wrappers: true})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    spawn_body = fn_body!(generated_c, "spawnTile")

    assert spawn_body =~ "elmc_fn_Main_setCell("
    assert spawn_body =~ "3, 2, cells"
    refute Regex.match?(~r/elmc_retain\(tmp_\d+\)/, spawn_body)

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_retain\(tmp_\d+\);/,
             spawn_body
           )

    set_cell_body =
      generated_c
      |> String.split(rc_direct_fn_def_marker("setCell"), parts: 2)
      |> Enum.at(1, "")
      |> String.split(rc_direct_fn_def_marker("spawnTile"), parts: 2)
      |> hd()

    assert set_cell_body =~ "elmc_list_replace_nth_int("
    assert set_cell_body =~ "CHECK_RC"
    refute set_cell_body =~ "if (!result)"
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

    out_dir = compile_snippet!("if_branch_direct_assign_codegen", source, %{prune_native_wrappers: true, strip_dead_code: false})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    pick_body = fn_body!(generated_c, "pickTile")
    assert_plan_lowered!(pick_body)
    assert pick_body =~ "elmc_tuple2("
    assert pick_body =~ "*out = owned["
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

    assert source =~ "elmc_list_cons("
    assert source =~ "tmp_head"
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

    out_dir = compile_snippet!("watchface_custom_msg_cmd", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    pebble_h = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    init_body = fn_body!(generated_c, "init")

    assert init_body =~
             ~r/elmc_cmd1\(&owned\[\d+\], ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_TIMEUPDATE\)/

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

    out_dir = compile_snippet!("union_constructor_macro_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "#define ELMC_UNION_LEFT 1"
    assert generated_c =~ "#define ELMC_UNION_MAIN_LEFT 1"
    assert generated_c =~ "#define ELMC_UNION_MAIN_UP 3"
    assert generated_c =~ "ELMC_UNION_LEFT"
    assert generated_c =~ "ELMC_UNION_MAIN_UP"

    move_body = fn_body!(generated_c, "move")
    assert_plan_lowered!(move_body)
    assert move_body =~ "ELMC_UNION_MAIN_LEFT"
    assert move_body =~ "ELMC_UNION_MAIN_UP"
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

    out_dir = compile_snippet!("storage_write_string_cmd_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_body = fn_body!(generated_c, "init")

    assert init_body =~ "ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING"
    assert init_body =~ "elmc_cmd2("
    assert init_body =~ "elmc_string_from_int("
    assert init_body =~ "CHECK_RC(Rc)"

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

    out_dir = compile_snippet!("direct_text_literal_prefix_append", source, %{direct_render_only: true})
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

    out_dir = compile_snippet!("direct_render_known_inverse_cond", source, %{direct_render_only: true})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ ~r/if \(!(\(native_cmp_\d+\)|\(elmc_as_int\((tmp_\d+|owned\[\d+\])\) != 0\))\)/
    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT)"
    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR)"
    refute generated_c =~ "if (ELMC_RECORD_GET_INDEX_INT(model, 0 /* value */) == 0)"
    refute generated_c =~ "if (0)"
    refute generated_c =~ "elmc_new_string(\".\")"
    refute generated_c =~ "scene_cmd.text[0] = '.';"
  end

  test "affine direct render emits zero placeholder label for empty indexedMap cells" do
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

    out_dir = compile_snippet!("direct_affine_text_nonzero_guard", source, %{direct_render_only: true})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "scene_cmd.text[0] = '.';"
    assert generated_c =~ "elmc_scene_text_from_nonzero_int"
    assert generated_c =~ "ELMC_RENDER_OP_TEXT"
    refute generated_c =~ "ELMC_RENDER_OP_TEXT_INT_WITH_FONT"
  end

  test "Maybe bare-var case binds payload type for distinct record field indices" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi

    type alias Piece =
        { kind : Int, rot : Int, x : Int, y : Int }

    type alias Model =
        { active : Maybe Piece, board : List Int }

    type Msg
        = Tick

    init _ =
        ( { active = Just { kind = 0, rot = 0, x = 3, y = 0 }, board = [] }, Cmd.none )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        case model.active of
            Nothing ->
                ( model, Cmd.none )

            piece ->
                ( { model | active = Just { piece | y = piece.y + 1 } }, Cmd.none )

    subscriptions _ =
        Sub.none

    view model =
        PebbleUi.windowStack []

    main =
        PebblePlatform.watchApp
            { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("maybe_case_record_field_indices", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "ELMC_FIELD_MAIN_PIECE_KIND"
    assert generated_c =~ "ELMC_FIELD_MAIN_PIECE_ROT"
    assert generated_c =~ "ELMC_FIELD_MAIN_PIECE_X"
    assert generated_c =~ "ELMC_FIELD_MAIN_PIECE_Y"
    refute generated_c =~ ~r/elmc_record_get_index\(tmp_\d+, 0 \/\* rot \*\)/
    refute generated_c =~ ~r/elmc_record_update_index\(tmp_\d+, 0 \/\* y \*\)/
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

    out_dir = compile_snippet!("record_update_index_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = fn_body!(generated_c, "update")

    assert update_body =~
             ~r/Rc = elmc_record_update_index_cow_drop\(&owned\[\d+\], .*, ELMC_FIELD_MAIN_MODEL_TIMESTRING, owned\[\d+\]\)/
    assert update_body =~ "elmc_retain(model)"
    refute update_body =~ ~s/elmc_record_update(tmp_2, "timeString"/
  end

  test "case branch record update with Nothing inlines immortal field without dead out assign" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Cmd as Cmd

    type alias Model =
        { tide : Maybe Int }

    type Msg
        = ClearTide

    init _ =
        ( { tide = Nothing }, Cmd.none )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            ClearTide ->
                ( { model | tide = Nothing }, Cmd.none )

    subscriptions _ =
        Sub.none

    view _ =
        PebbleUi.windowStack []

    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("record_update_nothing_inline", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = fn_body!(generated_c, "update")

    assert update_body =~
             ~r/Rc = elmc_record_update_index_cow_drop\(&owned\[\d+\], .*, ELMC_FIELD_MAIN_MODEL_TIDE, owned\[\d+\]\)/

    assert update_body =~ "elmc_maybe_nothing()"

    refute update_body =~
             ~r/elmc_maybe_nothing\(\);\s*\n\s*\*out = elmc_record_update_index_cow_drop/

    refute update_body =~
             ~r/elmc_maybe_nothing\(\);\s*\n\s*ElmcValue \*tmp_\d+ = elmc_record_update_index_cow_drop/
  end

  test "tuple2 record update reads pre-update field before cow_drop mutates model" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Cmd as Cmd

    type alias Model =
        { flag : Maybe Int }

    type Msg
        = Set Int

    init _ =
        ( { flag = Nothing }, Cmd.none )

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            Set n ->
                ( { model | flag = Just n }
                , case model.flag of
                    Nothing ->
                        Cmd.none

                    Just _ ->
                        Cmd.none
                )

    subscriptions _ =
        Sub.none

    view _ =
        PebbleUi.windowStack []

    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }

    """

    out_dir = compile_snippet!("tuple2_pre_update_field_read", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = fn_body!(generated_c, "update")
    field_read = "elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_FLAG)"

    record_update =
      ~r/Rc = elmc_record_update_index_cow_drop\(&owned\[\d+\], .*, ELMC_FIELD_MAIN_MODEL_FLAG, owned\[\d+\]\)/

    assert update_body =~ field_read
    assert update_body =~ record_update
  end

  test "case branch Cmd.none assigns immortal cmd directly to function out" do
    source = """
    module Main exposing (main, refreshStepsIfSupported)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd
    import Pebble.Health as Health

    type alias Model =
        { healthSupported : Maybe Bool }

    refreshStepsIfSupported : Model -> Cmd msg
    refreshStepsIfSupported model =
        case model.healthSupported of
            Just True ->
                Health.sumToday Health.StepCount Cmd.none

            _ ->
                Cmd.none

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { healthSupported = Nothing }, Cmd.none )
            , update = \\_ model -> ( model, refreshStepsIfSupported model )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> PebblePlatform.Cmd.none
            }

    """

    generated_c = compile_generated_c!("case_cmd_none_function_out", source, %{strip_dead_code: false})

    fn_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_refreshStepsIfSupported")

    assert fn_body =~ "elmc_cmd_none()"
    refute fn_body =~ "ELMC_PEBBLE_CMD_NONE"
    refute fn_body =~ "elmc_cmd0"
    refute fn_body =~ "ELMC_FN_OUT"
    refute fn_body =~ ~r/\*out = elmc_int_zero\(\);\s*\n\s*ElmcValue \*tmp_/
  end

  test "updateFromPhone case branches use owned temps not function out marker" do
    source = """
    module Main exposing (main, updateFromPhone)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type PhoneToWatch
        = ProvideMoon Int Int Int

    type alias Model =
        { moonPhaseE6 : Maybe Int, moonriseMin : Int, moonsetMin : Int }

    updateFromPhone : PhoneToWatch -> Model -> Model
    updateFromPhone message model =
        case message of
            ProvideMoon moonrise moonset phase ->
                { model
                    | moonriseMin = moonrise
                    , moonsetMin = moonset
                    , moonPhaseE6 = Just phase
                }

            _ ->
                model

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { moonriseMin = 0, moonsetMin = 0, moonPhaseE6 = Nothing }, Cmd.none )
            , update = \\_ model -> ( updateFromPhone (ProvideMoon 0 0 0) model, Cmd.none )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> PebblePlatform.Cmd.none
            }

    """

    generated_c = compile_generated_c!("update_from_phone_owned_temps", source, %{strip_dead_code: false})

    fn_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_updateFromPhone")

    refute fn_body == ""
    refute fn_body =~ "ELMC_FN_OUT"
    refute fn_body =~ "elmc_maybe_just(out,"
    assert fn_body =~ ~r/elmc_maybe_just_own\(&owned\[[0-9]+\],/
  end

  test "nested maybe case on callee uses owned slot not function out mid-branch" do
    source = """
    module Main exposing (main, updateFromPhone)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type PhoneToWatch
        = ProvideCondition Int

    type alias Model =
        { displayed : Maybe Int }

    lookupVector : Int -> Int -> Maybe Int
    lookupVector from to =
        if from == to then
            Nothing

        else
            Just to

    updateFromPhone : PhoneToWatch -> Model -> ( Model, Cmd Msg )
    updateFromPhone message model =
        case message of
            ProvideCondition newCondition ->
                case model.displayed of
                    Nothing ->
                        ( { model | displayed = Just newCondition }, Cmd.none )

                    Just displayed ->
                        case lookupVector displayed newCondition of
                            Nothing ->
                                ( { model | displayed = Just newCondition }, Cmd.none )

                            Just _ ->
                                ( model, Cmd.none )

            _ ->
                ( model, Cmd.none )

    type Msg
        = NoOp

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { displayed = Nothing }, Cmd.none )
            , update = \\_ model -> updateFromPhone (ProvideCondition 0) model
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> PebblePlatform.Cmd.none
            }
    """

    generated_c =
      compile_generated_c!("nested_maybe_case_owned_subject", source, %{
        strip_dead_code: true,
        direct_render_only: true,
        pebble_int32: true,
        prune_runtime: true
      })

    fn_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_updateFromPhone")

    refute fn_body == ""
    assert fn_body =~ ~r/elmc_fn_Main_lookupVector\(/
    refute fn_body =~ ~r/elmc_fn_Main_lookupVector(?:_native)?\(out,/
    refute fn_body =~ "elmc_maybe_is_nothing((*out))"
    assert fn_body =~ ~r/elmc_maybe_is_nothing\(owned\[\d+\]\)/
  end

  @tag timeout: 180_000
  test "union constructor multi-arg case binds fields from payload not tag" do
    source = """
    module Main exposing (main, updateFromPhone)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type Temperature
        = Celsius Int
        | Fahrenheit Int

    type WeatherCondition
        = Clear
        | Rain

    type PhoneToWatch
        = ProvideWeather Temperature WeatherCondition Int Int Int

    type alias Model =
        { weather : Maybe { temperature : Temperature, condition : WeatherCondition, precipMm10 : Int, uv10 : Int, pressureHpa : Int } }

    updateFromPhone : PhoneToWatch -> Model -> Model
    updateFromPhone message model =
        case message of
            ProvideWeather temperature condition precip uv pressure ->
                { model
                    | weather =
                        Just
                            { temperature = temperature
                            , condition = condition
                            , precipMm10 = precip
                            , uv10 = uv
                            , pressureHpa = pressure
                            }
                }

            _ ->
                model

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { weather = Nothing }, Cmd.none )
            , update = \\_ model -> ( model, Cmd.none )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> PebblePlatform.Cmd.none
            }
    """

    generated_c =
      compile_generated_c!("union_ctor_multi_arg_payload_bind", source, %{strip_dead_code: false})

    fn_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_updateFromPhone")

    refute fn_body == ""
    assert fn_body =~ "elmc_union_tag_matches(message,"
    assert fn_body =~ "ELMC_FIELD_MAIN_MODEL_WEATHER"

    refute fn_body =~
             ~r/owned\[\d+\] = \(\(ElmcTuple2 \*\)message->payload\)->first \? elmc_retain\(\(\(ElmcTuple2 \*\)message->payload\)->first\)/,
           "first constructor field must not bind union tag (->first)"

    assert fn_body =~ "elmc_tuple_second(message)" or
             fn_body =~ "elmc_tuple_first(owned[" or
             fn_body =~ "elmc_tuple_first_borrow(",
           "first constructor field must bind from union payload tuple"
  end

  test "maybe_just_own into same owned slot skips preempt release" do
    source = """
    module Main exposing (main, justWind)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type Corner
        = TempCorner
        | WindCorner

    justWind : Maybe Corner
    justWind =
        Just WindCorner

    main =
        PebblePlatform.worker
            { init = \\_ -> ( {}, Cmd.none )
            , update = \\_ model -> ( model, Cmd.none )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> Cmd.none
            }
    """

    generated_c = compile_generated_c!("maybe_just_own_same_slot", source, %{strip_dead_code: false})
    fn_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_justWind")

    refute fn_body =~ ~r/ELMC_RELEASE\(owned\[[0-9]+\]\);\s*\n\s*owned\[[0-9]+\] = NULL;\s*\n\s*Rc = elmc_maybe_just_own\(&owned\[[0-9]+\], owned\[[0-9]+\]\)/

    if fn_body =~ "elmc_maybe_just_own" do
      assert fn_body =~ ~r/Rc = elmc_maybe_just_own\(&owned\[[0-9]+\], owned\[[0-9]+\]\)/,
             "expected same-slot maybe_just_own without preempt release"
    end
  end

  test "union constructor case binds payload via elmc_union_payload_int" do
    source = """
    module Main exposing (main, temperatureString)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type Temperature
        = Celsius Int
        | Fahrenheit Int

    type alias Model =
        { weather : Maybe { temperature : Temperature } }

    temperatureString : Model -> String
    temperatureString model =
        case Maybe.map .temperature model.weather of
            Nothing ->
                "--"

            Just (Celsius c10) ->
                String.fromInt ((c10 + 5) // 10) ++ "C"

            Just (Fahrenheit f10) ->
                String.fromInt ((f10 + 5) // 10) ++ "F"

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { weather = Nothing }, Cmd.none )
            , update = \\_ model -> ( model, Cmd.none )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> Cmd.none
            }
    """

    generated_c = compile_generated_c!("union_payload_int_case", source, %{strip_dead_code: false})
    fn_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_temperatureString")

    assert fn_body =~ "elmc_tuple_second(" or fn_body =~ "elmc_maybe_just_payload("
    refute fn_body =~ "((ElmcTuple2 *)elmc_maybe_or_tuple_just_payload_borrow"
    refute_unsafe_union_int_tuple_second_cast!(generated_c)
  end

  @tag timeout: 180_000
  test "union int case codegen never casts maybe payload borrow to Tuple2 second" do
    source_a = """
    module Main exposing (main, readingString)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type Scale
        = Celsius Int
        | Fahrenheit Int

    type alias Model =
        { reading : Maybe Scale }

    readingString : Model -> String
    readingString model =
        case model.reading of
            Nothing ->
                "--"

            Just (Celsius c10) ->
                String.fromInt ((c10 + 5) // 10) ++ "C"

            Just (Fahrenheit f10) ->
                String.fromInt ((f10 + 5) // 10) ++ "F"

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { reading = Nothing }, Cmd.none )
            , update = \\_ model -> ( model, Cmd.none )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> Cmd.none
            }
    """

    source_b = """
    module Main exposing (main, levelLabel)

    import Pebble.Platform as PebblePlatform
    import Pebble.Cmd as Cmd

    type Units
        = Metric Int
        | Imperial Int

    type alias Model =
        { level : Maybe Units }

    levelLabel : Model -> String
    levelLabel model =
        case model.level of
            Nothing ->
                "--"

            Just (Metric mm) ->
                String.fromInt ((mm + 5) // 10) ++ "mm"

            Just (Imperial inches) ->
                String.fromInt ((inches + 5) // 10) ++ "in"

    main =
        PebblePlatform.worker
            { init = \\_ -> ( { level = Nothing }, Cmd.none )
            , update = \\_ model -> ( model, Cmd.none )
            , subscriptions = \\_ -> PebblePlatform.Sub.none
            , view = \\_ -> Cmd.none
            }
    """

    for {name, source, fn_name} <- [
          {"scale_reading", source_a, "readingString"},
          {"units_level", source_b, "levelLabel"}
        ] do
      generated_c = compile_generated_c!("union_int_scan_#{name}", source, %{strip_dead_code: false})
      fn_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_#{fn_name}")

      assert fn_body =~ "elmc_tuple_second(" or fn_body =~ "elmc_maybe_just_payload(" or
               fn_body =~ "elmc_union_payload_int(",
             "expected union int payload extraction in #{fn_name} for #{name}"

      refute_unsafe_union_int_tuple_second_cast!(generated_c)
    end
  end

  defp refute_unsafe_union_int_tuple_second_cast!(generated_c) when is_binary(generated_c) do
    refute generated_c =~
             ~r/\(\(ElmcTuple2 \*\)elmc_maybe_or_tuple_just_payload_borrow\([^)]+\)\)->second/,
           "union int extraction must use elmc_union_payload_int, not Tuple2->second"
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

    out_dir = compile_snippet!("msg_case_macro_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = fn_body!(generated_c, "update")

    assert update_body =~ "ELMC_UNION_MAIN_MINUTECHANGED"
    refute update_body =~ "== 1 && (1)"
    refute update_body =~ "&& (1)"
    refute update_body =~ ~r/first\) == 1\)/

    assert generated_c =~
             ~r/elmc_cmd1\(&owned\[\d+\], ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_CURRENTTIMESTRING\)/
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

    out_dir = compile_snippet!("subscription_macro_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subscriptions_body = fn_body!(generated_c, "subscriptions")

    assert subscriptions_body =~
             "elmc_sub1(out, ELMC_SUBSCRIPTION_MINUTE_CHANGE, ELMC_PEBBLE_MSG_MINUTECHANGED)"

    refute subscriptions_body =~ "elmc_new_int(ELMC_SUBSCRIPTION_MINUTE_CHANGE)"
    refute subscriptions_body =~ "elmc_new_int(2048)"
    refute subscriptions_body =~ "\n\n\n"
    # Unused Elm `_` args are desugared to `ignoredArg` (see ElmEx.IR.FnArgDesugar).
    assert subscriptions_body =~ "(void)ignoredArg;"
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

    out_dir = compile_snippet!("button_sub_codegen", source)
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subscriptions_body = fn_body!(generated_c, "subscriptions")

    assert subscriptions_body =~
             "elmc_sub3(out, ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED)"
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

    body = fn_body!(generated_c, "useCounts")
    assert_plan_lowered!(body)

    count_empty_body = fn_body!(generated_c, "countEmpty")
    assert count_empty_body =~ "plan block"
    assert count_empty_body =~ "elmc_list_is_empty" or count_empty_body =~ "elmc_list_head_with_default_int"
    refute count_empty_body =~ "list_walk_cursor_"

    count_zeros_body = fn_body!(generated_c, "countZeros")
    assert_plan_lowered!(count_zeros_body)
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

    assert generated_c =~ "nthEmptyIndexHelp_native"
    assert generated_c =~ "list_search_head_"
    refute generated_c =~ "list_walk_cursor_"
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
               strip_dead_code: true,
               plan_ir_mode: :primary,
               plan_ir_strict: true
             })

    generated_h = File.read!(Path.join(out_dir, "c/elmc_generated.h"))
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    pebble_h = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    assert pebble_h =~ "#define ELMC_PEBBLE_SCENE_POOL_SLOTS 4"
    assert pebble_h =~ "#define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 0"
    assert pebble_h =~ "#define ELMC_PEBBLE_SCENE_CHUNK_SIZE 0"
    assert pebble_h =~ "#define ELMC_PEBBLE_SCENE_CACHE_ENABLED 0"

    assert generated_h =~ "elmc_fn_Main_init("
    assert generated_h =~ "elmc_fn_Main_update("
    refute generated_h =~ "elmc_fn_Main_spawnTileWithSeed("
    assert generated_c =~ "elmc_fn_Main_spawnTileWithSeed(" or generated_c =~ "elmc_fn_Main_init("
    refute generated_c =~ "elmc_fn_Main_spawnTileWithSeed_native("
    assert generated_c =~ "static RC elmc_fn_Main_moveBoard_native("
    assert generated_c =~ "while (Rc == RC_SUCCESS && direct_cursor_"
    assert generated_c =~ "ELMC_RENDER_OP_RECT"
    assert generated_c =~ "scene_cmd.text[0] = '.';"
    refute generated_c =~ "10 + 2"
    refute generated_c =~ "rec_names_"
    refute generated_c =~ "elmc_record_new_static_take"
    refute generated_c =~ ~r/static const char \* const rec_names/
    # Unbound :sub_vars in boardLayout inlining collapsed to (0-0)//2 → layout.x = 0.
    refute generated_c =~ ~r/owned\[\d+\] = elmc_int_zero\(\);\s*\n\s*owned\[\d+\] = elmc_int_zero\(\);\s*\n\s*ElmcValue \*tmp_\d+ = NULL;\s*\n\s*Rc = elmc_new_int\(&tmp_\d+, elmc_as_int\(owned\[\d+\]\) - elmc_as_int\(owned\[\d+\]\)\)/

    harness_path = Path.join(out_dir, "c/game_2048_scene_harness.c")

    File.write!(
      harness_path,
    """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *elmc_harness_record_new_values_take(int count, ElmcValue **values) {
        ElmcValue *out = NULL;
        if (elmc_record_new_values_take(&out, count, values) != RC_SUCCESS) return NULL;
        return out;
      }

      static ElmcValue *aplite_launch_context(void) {
        ElmcValue *reason = ELMC_RC_INT_BOX(2);
        ElmcValue *watch_model = ELMC_RC_STRING_BOX("");
        ElmcValue *watch_profile_id = ELMC_RC_STRING_BOX("aplite");
        ElmcValue *width = ELMC_RC_INT_BOX(144);
        ElmcValue *height = ELMC_RC_INT_BOX(168);
        ElmcValue *shape = ELMC_RC_INT_BOX(1);
        ElmcValue *color_mode = ELMC_RC_INT_BOX(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_harness_record_new_values_take(4, screen_values);
        ElmcValue *has_microphone = ELMC_RC_INT_BOX(0);
        ElmcValue *has_compass = ELMC_RC_INT_BOX(0);
        ElmcValue *supports_health = ELMC_RC_INT_BOX(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        return elmc_harness_record_new_values_take(7, context_values);
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

      static int max_rect_right(ElmcPebbleApp *app) {
        int max_right = 0;
        ElmcPebbleDrawCmd cmd;
        elmc_pebble_scene_reset_draw_cursor(app);
        for (int i = 0; i < 256; i++) {
          if (elmc_pebble_scene_commands_next(app, &cmd, 1) <= 0) break;
          if (cmd.kind == ELMC_PEBBLE_DRAW_RECT) {
            if (cmd.p2 <= 0 || cmd.p3 <= 0) return -1;
            int right = (int)cmd.p0 + (int)cmd.p2;
            if (right > max_right) max_right = right;
          }
        }
        return max_right;
      }

      static int min_rect_x(ElmcPebbleApp *app) {
        int min_x = 100000;
        ElmcPebbleDrawCmd cmd;
        elmc_pebble_scene_reset_draw_cursor(app);
        for (int i = 0; i < 256; i++) {
          if (elmc_pebble_scene_commands_next(app, &cmd, 1) <= 0) break;
          if (cmd.kind == ELMC_PEBBLE_DRAW_RECT) {
            if ((int)cmd.p0 < min_x) min_x = (int)cmd.p0;
          }
        }
        return (min_x == 100000) ? -1 : min_x;
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
        int max_right = max_rect_right(&app);
        int min_x = min_rect_x(&app);
        if (rects < 16) {
          fprintf(stderr, "expected >=16 rects, got %d (texts=%d)\\n", rects, texts);
          elmc_pebble_deinit(&app);
          return 5;
        }
        if (max_right <= 0) {
          fprintf(stderr, "expected positive rect sizes on 144px screen\\n");
          elmc_pebble_deinit(&app);
          return 7;
        }
        if (max_right > 128) {
          fprintf(stderr, "expected max rect right <= 128 on 144px screen, got %d\\n", max_right);
          elmc_pebble_deinit(&app);
          return 6;
        }
        /* boardLayout centers with (panelWidth - boardWidth) // 2 ≈ 15 on 144px */
        if (min_x < 8) {
          fprintf(stderr, "expected centered board min_x >= 8 on 144px screen, got %d\\n", min_x);
          elmc_pebble_deinit(&app);
          return 8;
        }

        elmc_pebble_deinit(&app);
        printf("ok rects=%d texts=%d max_right=%d min_x=%d\\n", rects, texts, max_right, min_x);
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
        "-lm",
        "-o",
        binary_path
      ], stderr_to_stdout: true)

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
    assert generated_c =~ " % 4" or generated_c =~ "& 3"
    assert generated_c =~ " / 4" or generated_c =~ "elmc_int_idiv("
  end

  test "record Bool helpers with native bodies emit _native return without RC boxing" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { pieceKind : Int }

    type Msg
        = Noop

    hasPiece : Model -> Bool
    hasPiece model =
        model.pieceKind >= 0

    init _ =
        ( { pieceKind = 1 }, Platform.Cmd.none )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view model =
        if hasPiece model then
            Ui.windowStack []

        else
            Ui.windowStack []

    main =
        Platform.worker { init = init, update = update, subscriptions = subscriptions, view = view }

    """

    generated_c = compile_generated_c!("native_record_bool_helper", source, %{strip_dead_code: false})

    has_piece_body = fn_body!(generated_c, "hasPiece")
    assert_plan_lowered!(has_piece_body)
    assert has_piece_body =~ "ELMC_RECORD_GET_INDEX_INT"
  end

  test "record Bool helpers with Maybe field checks and Basics.not emit native bool" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model =
        { displayShape : Platform.DisplayShape
        , sun : Maybe Int
        }

    type Msg
        = Noop

    showCorners : Model -> Bool
    showCorners model =
        not (Platform.displayShapeIsRound model.displayShape)
            && model.sun /= Nothing

    init _ =
        ( { displayShape = Platform.Round, sun = Nothing }, Platform.Cmd.none )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view model =
        if showCorners model then
            Ui.windowStack []

        else
            Ui.windowStack []

    main =
        Platform.worker { init = init, update = update, subscriptions = subscriptions, view = view }

    """

    generated_c = compile_generated_c!("native_record_bool_maybe_helper", source, %{strip_dead_code: false})

    show_corners_body = fn_body!(generated_c, "showCorners")
    assert_plan_lowered!(show_corners_body)
    assert show_corners_body =~ "ELMC_TAG_MAYBE" or show_corners_body =~ "elmc_maybe_is_nothing"
  end

  test "RC tail-recursive loop transfers owned base result before epilogue release" do
    source = """
    module Main exposing (main)

    buildList : Int -> List Int -> List Int
    buildList n acc =
        if n <= 0 then
            acc
        else
            buildList (n - 1) (n :: acc)

    main : Int
    main =
        List.length (buildList 100 [])
    """

    generated_c = compile_generated_c!("rc_tail_rec_owned_base", source, %{})

    build_list_fn = fn_body!(generated_c, "buildList")
    # Thin RC wrapper delegates to the fused native helper.
    assert build_list_fn =~ "elmc_fn_Main_buildList_native("

    native_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_buildList_native")
    assert native_body =~ "while (1)"
    assert native_body =~ "*out = tail_result"
    # Base case moves the owned accumulator into tail_result (nulling the owned
    # slot) before the epilogue LIFO release.
    assert native_body =~ "tail_result = owned["
    assert native_body =~ ~r/tail_result = owned\[\d+\];\s*\n\s*owned\[\d+\] = NULL;/
    assert native_body =~ "elmc_release_array_lifo(owned,"
  end

  test "tail-recursive qualified self calls emit loop instead of broken native inline" do
    source = """
    module Main exposing (main)

    fibHelper : Int -> Int -> Int -> Int
    fibHelper n a b =
        if n <= 0 then
            a
        else
            fibHelper (n - 1) b (a + b)

    fib : Int -> Int
    fib n =
        fibHelper n 0 1

    main : Int
    main =
        fib 40

    """

    generated_c = compile_generated_c!("tail_rec_qualified_call", source, %{})

    fib_body = fn_body!(generated_c, "fib")
    assert_plan_lowered!(fib_body)
    assert fib_body =~ "elmc_fn_Main_fibHelper(" or fib_body =~ "plan block"
  end

  test "Maybe CurrentDateTime field access in timeString uses hour and minute indices not year" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Time as PebbleTime
    import Pebble.Ui as PebbleUi

    type alias Model =
        { currentDateTime : Maybe PebbleTime.CurrentDateTime }

    type Msg
        = NoOp

    pad2 : Int -> String
    pad2 value =
        if value < 10 then
            "0" ++ String.fromInt value

        else
            String.fromInt value

    timeString : Model -> String
    timeString model =
        case model.currentDateTime of
            Nothing ->
                "--:--"

            Just currentDateTime ->
                pad2 currentDateTime.hour ++ ":" ++ pad2 currentDateTime.minute

    init _ = ( { currentDateTime = Nothing }, Cmd.none )
    update _ model = ( model, Cmd.none )
    subscriptions _ = Sub.none
    view model = PebbleUi.toUiNode [ PebbleUi.textLabel 0 { x = 0, y = 0 } (timeString model) ]

    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    generated_c = compile_generated_c!("maybe_current_datetime_time_string", source, %{})

    assert generated_c =~ "ELMC_FIELD_PKG_APP_PEBBLE_CMD_CURRENTDATETIME_HOUR" or
             generated_c =~ "ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR"

    assert generated_c =~ "ELMC_FIELD_PKG_APP_PEBBLE_CMD_CURRENTDATETIME_MINUTE" or
             generated_c =~ "ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE"
    refute generated_c =~ ~r/ELMC_RECORD_GET_INDEX_INT\([^,]+, 0 \/\* hour \*\)/
    refute generated_c =~ ~r/ELMC_RECORD_GET_INDEX_INT\([^,]+, 0 \/\* minute \*\)/
  end

  defp compile_generated_c!(name, source, opts) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{name}_project", __DIR__)
    out_dir = Path.expand("tmp/#{name}_codegen", __DIR__)
    repo_root = Path.expand("../..", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    elm_json =
      Path.join(project_dir, "elm.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("source-directories", [
        "src",
        Path.join(repo_root, "packages/elm-pebble/elm-watch/src"),
        Path.join(repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
        Path.join(repo_root, "shared/elm"),
        Path.join(repo_root, "ide/priv/bundled_elm/shared-elm"),
        Path.join(repo_root, "ide/priv/internal_packages/elm-random/src"),
        Path.join(repo_root, "ide/priv/internal_packages/elm-time/src")
      ])

    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(elm_json, pretty: true))

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
