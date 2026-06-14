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

  test "game-2048 emptyBoard uses direct zero-arity RC call without argc wrapper" do
    generated_c = compile_2048_generated!()

    assert generated_c =~ "RC elmc_fn_Main_emptyBoard(ElmcValue **out)"
    refute generated_c =~ "elmc_fn_Main_emptyBoard(&__z, NULL, 0)"
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
