defmodule Elmc.RcRequiredAllocAnalysisTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  alias Elmc.Backend.CCodegen.{Host, IRQueries, RcRequired}
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)
  @game_2048_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  defp compile_yes_watchface!(opts) do
    out_dir = Keyword.fetch!(opts, :out_dir)

    compile_opts =
      [
        out_dir: out_dir,
        direct_render_only: Keyword.get(opts, :direct_render_only, true),
        strip_dead_code: Keyword.get(opts, :strip_dead_code, false),
        prune_runtime: Keyword.get(opts, :prune_runtime, true),
        pebble_int32: Keyword.get(opts, :pebble_int32, true),
        keep_tmp: true
      ]
      |> Keyword.merge(Keyword.drop(opts, [:out_dir, :direct_render_only, :strip_dead_code, :prune_runtime, :pebble_int32]))

    assert {:ok, result} = TemplateCompile.compile_watch_template("watchface_yes", compile_opts)
    result
  end

  defp compile_2048_generated!(opts \\ []) do
    defaults = [
      direct_render_only: true,
      strip_dead_code: true,
      prune_native_wrappers: true,
      pebble_int32: true,
      prune_runtime: true,
      plan_ir_mode: :primary
    ]

    out_dir = Path.expand("tmp/rc_required_2048_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_opts =
      [out_dir: out_dir]
      |> Keyword.merge(Keyword.merge(defaults, opts))

    assert {:ok, _} = TemplateCompile.compile_watch_template("game_2048", compile_opts)

    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end

  test "game-2048 allocating helpers are rc_required" do
    project_dir = Path.expand("tmp/rc_required_2048_ir", __DIR__)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@game_2048_main))
    File.write!(Path.join(project_dir, "elm.json"), File.read!(@fixture_elm_json))

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               entry_module: "Main",
               out_dir: Path.expand("tmp/rc_required_2048_ir_out", __DIR__)
             })

    decl_map = IRQueries.function_decl_map(ir)
    direct_command_targets = Host.direct_command_targets(ir, %{direct_render_only: true}, decl_map)

    required =
      RcRequired.analyze(
        decl_map,
        direct_render_only: true,
        direct_command_targets: direct_command_targets
      )

    for name <- ["merge", "collapseRow", "collapseRows", "moveBoard", "update", "init"] do
      assert MapSet.member?(required, {"Main", name}),
             "expected Main.#{name} to be rc_required"
    end

    assert MapSet.member?(required, {"Main", "main"}),
           "expected Main.main to use RC ABI when it allocates cmds"

    assert MapSet.member?(required, {"Main", "view"}),
           "direct-render view entry must use RC ABI"
  end

  test "native Int boxing wrappers are rc_required" do
    out_dir = Path.expand("tmp/rc_required_yes_ir_out", __DIR__)

    assert %{ir: ir} =
             compile_yes_watchface!(out_dir: out_dir, direct_render_only: true, strip_dead_code: false)

    decl_map = IRQueries.function_decl_map(ir)
    required = RcRequired.analyze(decl_map, direct_render_only: true)

    assert MapSet.member?(required, {"Yes.Render", "angleFromMinute"})
    assert MapSet.member?(required, {"Main", "homeMinuteOfDay"})
  end

  @tag timeout: 300_000
  test "helpers that call native boxed RC constructors are rc_required" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/rc_required_native_boxed_callers_project", __DIR__)
    out_dir = Path.expand("tmp/rc_required_native_boxed_callers_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    piece_helpers = """


    type alias Point =
        { x : Int
        , y : Int
        }

    type alias PendingPiece =
        { x1 : Int
        , y1 : Int
        , x2 : Int
        , y2 : Int
        }

    type alias DownloadedPiece =
        { p1 : Point
        , p2 : Point
        }

    type alias PieceScratch =
        { downloaded : DownloadedPiece
        }

    o : Int -> Int -> Point
    o x y =
        { x = x, y = y }


    toDownloadedPiece : PendingPiece -> DownloadedPiece
    toDownloadedPiece piece =
        { p1 = o piece.x1 piece.y1
        , p2 = o piece.x2 piece.y2
        }


    finishPiece : PendingPiece -> PieceScratch -> PieceScratch
    finishPiece piece model =
        { model | downloaded = toDownloadedPiece piece }

    """

    main_source = File.read!(Path.join(project_dir, "src/Main.elm"))

    patched_main =
      (main_source <> piece_helpers)
      |> String.replace(
        "subscriptions _ =\n    PebbleEvents.batch",
        """
        subscriptions _ =
            let
                _ =
                    finishPiece { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }
                        { downloaded = { p1 = o 0 0, p2 = o 1 1 } }
            in
            PebbleEvents.batch
        """,
        global: false
      )

    File.write!(Path.join(project_dir, "src/Main.elm"), patched_main)

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               entry_module: "Main",
               out_dir: out_dir,
               strip_dead_code: false,
               plan_ir_mode: :primary,
               direct_render_only: true
             })

    decl_map = IRQueries.function_decl_map(ir)
    required = RcRequired.analyze(decl_map, direct_render_only: true)

    assert MapSet.member?(required, {"Main", "toDownloadedPiece"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_toDownloadedPiece")

    assert generated_c =~ "RC elmc_fn_Main_toDownloadedPiece("
    assert body =~ "CATCH_BEGIN"
    assert body =~ "CHECK_RC(Rc)"
    assert body =~ "Rc = elmc_fn_Main_o(&"
    refute body =~ "ELMC_RC_LOG_FAIL(__call_rc, \"elmc_fn_Main_o_native\""
  end

  test "watchface-yes defaultSunWindow uses RC ABI with CHECK_RC allocators" do
    out_dir = Path.expand("tmp/rc_required_yes_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_yes_watchface!(out_dir: out_dir)

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Yes_Render_defaultSunWindow")

    assert generated_c =~ "RC elmc_fn_Yes_Render_defaultSunWindow("
    assert body =~ "CATCH_BEGIN"
    assert body =~ "CHECK_RC(Rc)"
    assert body =~ "Rc = elmc_new_int(&"
    assert body =~ "Rc = elmc_record_new_values_take(out,"
    refute body =~ "_take_value"
    refute body =~ "Rc = ELMC_RC_INT_BOX("

    refute generated_c =~ "static RC elmc_fn_Yes_Render_angleFromMinute("

    square_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Layout_centerSquare")
    assert square_body =~ "CATCH_BEGIN"
    assert square_body =~ "CHECK_RC(Rc)"
    assert square_body =~ "Rc = elmc_record_new_values_ints(out,"
    refute square_body =~ "ElmcValue *owned["
    refute square_body =~ "Rc = elmc_new_int(&owned["
    refute square_body =~ "tmp_1_boxed_int"
    refute square_body =~ "if (owned[0])"
    refute square_body =~ "if (owned[1])"
    refute square_body =~ "if (owned[2])"

    draw_dial_body =
      CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert draw_dial_body =~ "elmc_angle_from_minute"
    assert draw_dial_body =~ "elmc_fn_Yes_Layout_centerSquare(&owned["
    assert draw_dial_body =~ "elmc_maybe_with_default"
    assert draw_dial_body =~ "elmc_polar_point_x("

    show_corners_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_showCorners")

    refute show_corners_body =~ "!(tmp_"
    assert show_corners_body =~ "ELMC_FIELD_MAIN_MODEL_SUN"
  end

  test "watchface-yes allocating helpers use RC ABI with CHECK_RC allocators" do
    out_dir = Path.expand("tmp/rc_required_yes_battery_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_yes_watchface!(out_dir: out_dir)

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_batteryAlert")

    assert generated_c =~ "RC elmc_fn_Main_batteryAlert("
    assert body =~ "CHECK_RC(Rc)"
    assert body =~ "elmc_as_int(owned[2])"
    refute body =~ "Rc = ELMC_RC_INT_BOX("
    refute body =~ "Rc = ELMC_RC_BOOL_BOX("
    refute body =~ "ELMC_RELEASE(owned["
    refute body =~ "__cmp_"
    refute body =~ "owned[1] = tmp_"
  end

  test "watchface-yes calendarDayKey never emits raw ELMC_FN_OUT" do
    out_dir = Path.expand("tmp/rc_required_yes_calendar_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_yes_watchface!(out_dir: out_dir)

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_calendarDayKey")

    assert generated_c =~ "static elmc_int_t elmc_fn_Main_calendarDayKey("
    refute body =~ "ELMC_FN_OUT"
    refute body =~ "ELMC_TAG_FLOAT"
    refute body =~ "elmc_record_get("
    assert body =~ "ELMC_RECORD_GET_INDEX_INT(now, ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_YEAR)"
    assert body =~ "* 10000"
    refute generated_c =~ "RC elmc_fn_Main_calendarDayKey("
  end

  test "watchface-yes partial and lambda closures survive direct-render registry reset" do
    out_dir = Path.expand("tmp/rc_required_yes_closures_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_yes_watchface!(out_dir: out_dir)

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_closure_new"
    assert generated_c =~ "_closure_"
  end

  test "watchface-yes int-list loop heads are declared once per iteration" do
    out_dir = Path.expand("tmp/list_map_head_decl_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_yes_watchface!(out_dir: out_dir)

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    draw_outer = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_drawOuterScale")

    refute Regex.match?(~r/ElmcValue \*list_map_head_\d+ = NULL;\s+ElmcValue \*list_map_head_\d+ = NULL;/, draw_outer)

    pick_slot = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_pickSlot")
    refute Regex.match?(~r/ElmcValue \*list_find_first_head_\d+ = NULL;\s+ElmcValue \*list_find_first_head_\d+ = NULL;/, pick_slot)
    refute Regex.match?(~r/ElmcValue \*list_filter_map_field_head_\d+ = NULL;\s+ElmcValue \*list_filter_map_field_head_\d+ = NULL;/, pick_slot)
  end

  test "game-2048 emptyBoard uses direct zero-arity RC call without argc wrapper" do
    generated_c = compile_2048_generated!()

    assert generated_c =~ "RC elmc_fn_Main_emptyBoard(ElmcValue **out)"
    refute generated_c =~ "elmc_fn_Main_emptyBoard(&__z, NULL, 0)"
  end

  test "game-2048 init uses CHECK_RC for zero-arity emptyBoard into owned slot" do
    generated_c = compile_2048_generated!()
    init_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_init")

    assert init_body =~ ~r/Rc = elmc_fn_Main_emptyBoard\(&owned\[\d+\]\);/
    assert init_body =~ "CHECK_RC(Rc);"
    refute init_body =~ "owned[0] = NULL;\n    Rc = elmc_fn_Main_emptyBoard"
    refute init_body =~ "__z"
    refute init_body =~ "({ ElmcValue *__z"
  end

  test "game-2048 init builds Model with record_new_values_take so cells stays a list" do
    generated_c = compile_2048_generated!()
    init_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_init")

    refute init_body =~ "elmc_record_new_values_ints"
    assert init_body =~ "elmc_record_new_values_take"
    refute init_body =~ ~r/elmc_as_int\(owned\[\d+\]\)/
  end

  @tag timeout: 300_000
  test "game-2048 merge uses CHECK_RC for borrowed list.cons instead of elmc_int_zero fallback" do
    generated_c = compile_2048_generated!(strip_dead_code: false, direct_render_only: false)

    merge_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_merge")

    if merge_body == "" do
      fused =
        CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_moveBoard_native")

      assert fused != ""
      assert fused =~ "CHECK_RC(Rc)"
      refute fused =~ ~r/if \(elmc_list_cons\(&[^)]+\) != RC_SUCCESS\)\s*tmp_\d+ = elmc_int_zero\(\);/
    else
      assert generated_c =~ "RC elmc_fn_Main_merge("
      refute generated_c =~ ~r/elmc_list_cons\(&[^;]+;\s*if \(elmc_list_cons\(&[^)]+\) != RC_SUCCESS\)\s*tmp_\d+ = elmc_int_zero\(\);/s
      assert merge_body =~ "CHECK_RC(Rc)"
      assert merge_body =~ "elmc_list_cons(&"
      refute merge_body =~ ~r/if \(elmc_list_cons\(&[^)]+\) != RC_SUCCESS\)\s*tmp_\d+ = elmc_int_zero\(\);/
      refute merge_body =~ ~r/ELMC_RC_LOG_FAIL\(__alloc_rc, "elmc_list_cons", "allocation failed"\);\s*return NULL;/
    end
  end
end
