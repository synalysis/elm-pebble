defmodule Elmc.RcRequiredAllocAnalysisTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.{Host, IRQueries, RcRequired}
  alias Elmc.Test.CCodegenExtract

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)
  @game_2048_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)
  @watchface_yes_template Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)

  defp prepare_yes_watchface_project!(project_dir) do
    File.rm_rf!(project_dir)
    File.cp_r!(@watchface_yes_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "protocol/src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3", "elm/time" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )
  end

  defp compile_2048_generated!(opts \\ []) do
    defaults = [
      direct_render_only: true,
      strip_dead_code: true,
      prune_native_wrappers: true,
      pebble_int32: true,
      prune_runtime: true
    ]

    project_dir = Path.expand("tmp/rc_required_2048_project", __DIR__)
    out_dir = Path.expand("tmp/rc_required_2048_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@game_2048_main))
    File.write!(Path.join(project_dir, "elm.json"), File.read!(@fixture_elm_json))

    compile_opts =
      %{
        out_dir: out_dir,
        entry_module: "Main"
      }
      |> Map.merge(Map.new(Keyword.merge(defaults, opts)))

    assert {:ok, _} = Elmc.compile(project_dir, compile_opts)

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
    project_dir = Path.expand("tmp/rc_required_yes_ir", __DIR__)
    prepare_yes_watchface_project!(project_dir)

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               entry_module: "Main",
               out_dir: Path.expand("tmp/rc_required_yes_ir_out", __DIR__)
             })

    decl_map = IRQueries.function_decl_map(ir)
    required = RcRequired.analyze(decl_map, direct_render_only: true)

    assert MapSet.member?(required, {"Yes.Render", "angleFromMinute"})
    assert MapSet.member?(required, {"Main", "homeMinuteOfDay"})
  end

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
               strip_dead_code: false
             })

    decl_map = IRQueries.function_decl_map(ir)
    required = RcRequired.analyze(decl_map, direct_render_only: true)

    assert MapSet.member?(required, {"Main", "toDownloadedPiece"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_toDownloadedPiece")

    assert generated_c =~ "RC elmc_fn_Main_toDownloadedPiece("
    assert body =~ "CATCH_BEGIN"
    assert body =~ "CHECK_RC(Rc)"
    assert body =~ "Rc = elmc_fn_Main_o_native("
    refute body =~ "ELMC_RC_LOG_FAIL(__call_rc, \"elmc_fn_Main_o_native\""
  end

  test "watchface-yes defaultSunWindow uses RC ABI with CHECK_RC allocators" do
    project_dir = Path.expand("tmp/rc_required_yes_project", __DIR__)
    out_dir = Path.expand("tmp/rc_required_yes_codegen", __DIR__)
    File.rm_rf!(out_dir)
    prepare_yes_watchface_project!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Yes_Render_defaultSunWindow")

    assert generated_c =~ "RC elmc_fn_Yes_Render_defaultSunWindow("
    assert body =~ "CATCH_BEGIN"
    assert body =~ "CHECK_RC(Rc)"
    assert body =~ "Rc = elmc_new_int(&"
    assert body =~ "Rc = elmc_record_new_values_take(out,"
    refute body =~ "_take_value"
    refute body =~ "elmc_new_int_take"

    refute generated_c =~ "static RC elmc_fn_Yes_Render_angleFromMinute("

    square_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Layout_centerSquare_native")
    assert square_body =~ "ElmcValue *owned["
    assert square_body =~ "Rc = elmc_new_int(&owned["
    assert square_body =~ "elmc_release_array_lifo(owned, DIM(owned));"
    refute square_body =~ "tmp_1_boxed_int"
    refute square_body =~ "if (owned[0])"
    refute square_body =~ "if (owned[1])"
    refute square_body =~ "if (owned[2])"

    draw_dial_body =
      CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert draw_dial_body =~ "elmc_angle_from_minute"
    assert draw_dial_body =~ "elmc_fn_Yes_Layout_centerSquare_native(&owned["
    assert draw_dial_body =~ "elmc_maybe_with_default"
    assert draw_dial_body =~ "elmc_polar_point_x("

    refute generated_c =~ "static RC elmc_fn_Yes_Render_drawScaleTick_commands_append("

    show_corners_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_showCorners_native")

    refute show_corners_body =~ "!(tmp_"
    assert show_corners_body =~ "ELMC_FIELD_MAIN_MODEL_SUN"
  end

  test "watchface-yes allocating helpers use RC ABI with CHECK_RC allocators" do
    project_dir = Path.expand("tmp/rc_required_yes_battery_project", __DIR__)
    out_dir = Path.expand("tmp/rc_required_yes_battery_codegen", __DIR__)
    File.rm_rf!(out_dir)
    prepare_yes_watchface_project!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_batteryAlert")

    assert generated_c =~ "RC elmc_fn_Main_batteryAlert("
    assert body =~ "CHECK_RC(Rc)"
    assert body =~ "elmc_value_equal("
    refute body =~ "elmc_new_int_take("
    refute body =~ "elmc_new_bool_take("
    refute body =~ "ELMC_RELEASE(owned["
    refute body =~ "__cmp_"
    refute body =~ "owned[1] = tmp_"
  end

  test "watchface-yes calendarDayKey never emits raw ELMC_FN_OUT" do
    project_dir = Path.expand("tmp/rc_required_yes_calendar_project", __DIR__)
    out_dir = Path.expand("tmp/rc_required_yes_calendar_codegen", __DIR__)
    File.rm_rf!(out_dir)
    prepare_yes_watchface_project!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_calendarDayKey")
    wrapper = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_calendarDayKey")

    refute body =~ "ELMC_FN_OUT"
    refute body =~ "ELMC_TAG_FLOAT"
    refute body =~ "elmc_record_get("
    assert body =~ "ELMC_RECORD_GET_INDEX_INT(now, ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_YEAR)"
    assert body =~ "* 10000"
    assert wrapper =~ "elmc_new_int(out, elmc_fn_Main_calendarDayKey_native(now))"
    refute wrapper =~ "CATCH_BEGIN"
  end

  test "watchface-yes partial and lambda closures survive direct-render registry reset" do
    project_dir = Path.expand("tmp/rc_required_yes_closures_project", __DIR__)
    out_dir = Path.expand("tmp/rc_required_yes_closures_codegen", __DIR__)
    File.rm_rf!(out_dir)
    prepare_yes_watchface_project!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "static ElmcValue *elmc_partial_ref_1("
    assert generated_c =~ "elmc_closure_new"
  end

  test "watchface-yes int-list loop heads are declared once per iteration" do
    project_dir = Path.expand("tmp/list_map_head_decl_project", __DIR__)
    out_dir = Path.expand("tmp/list_map_head_decl_codegen", __DIR__)
    File.rm_rf!(out_dir)
    prepare_yes_watchface_project!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               strip_dead_code: true
             })

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
