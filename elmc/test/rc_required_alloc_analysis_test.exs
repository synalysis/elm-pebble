defmodule Elmc.RcRequiredAllocAnalysisTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.{IRQueries, RcRequired}
  alias Elmc.Test.CCodegenExtract

  @fixture_elm_json Path.expand("fixtures/simple_project/elm.json", __DIR__)
  @game_2048_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

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
    required = RcRequired.analyze(decl_map, direct_render_only: true)

    for name <- ["merge", "collapseRow", "collapseRows", "moveBoard", "update", "init"] do
      assert MapSet.member?(required, {"Main", name}),
             "expected Main.#{name} to be rc_required"
    end

    for name <- ["main", "view", "boardLayout", "drawCell"] do
      refute MapSet.member?(required, {"Main", name}),
             "expected Main.#{name} to stay legacy ABI under direct-render-only"
    end
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

  test "game-2048 emptyBoard uses direct zero-arity RC call without argc wrapper" do
    generated_c = compile_2048_generated!()

    assert generated_c =~ "RC elmc_fn_Main_emptyBoard(ElmcValue **out)"
    refute generated_c =~ "elmc_fn_Main_emptyBoard(&__z, NULL, 0)"
  end

  test "game-2048 init uses CHECK_RC for zero-arity emptyBoard into owned slot" do
    generated_c = compile_2048_generated!()
    init_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_init")

    assert init_body =~ "Rc = elmc_fn_Main_emptyBoard(&owned[0]);"
    assert init_body =~ "CHECK_RC(Rc);"
    refute init_body =~ "owned[0] = NULL;\n    Rc = elmc_fn_Main_emptyBoard"
    refute init_body =~ "__z"
    refute init_body =~ "({ ElmcValue *__z"
  end

  test "game-2048 merge uses CHECK_RC for borrowed list.cons instead of elmc_int_zero fallback" do
    generated_c = compile_2048_generated!(strip_dead_code: false, direct_render_only: false)

    assert generated_c =~ "RC elmc_fn_Main_merge("
    refute generated_c =~ ~r/elmc_list_cons\(&[^;]+;\s*if \(elmc_list_cons\(&[^)]+\) != RC_SUCCESS\)\s*tmp_\d+ = elmc_int_zero\(\);/s

    merge_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_merge")

    assert merge_body =~ "CHECK_RC(Rc)"
    assert merge_body =~ "elmc_list_cons(&"
    refute merge_body =~ ~r/if \(elmc_list_cons\(&[^)]+\) != RC_SUCCESS\)\s*tmp_\d+ = elmc_int_zero\(\);/
    refute merge_body =~ ~r/ELMC_RC_LOG_FAIL\(__alloc_rc, "elmc_list_cons", "allocation failed"\);\s*return NULL;/
  end
end
