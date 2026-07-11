defmodule Elmc.PlanDirectCallAbiTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.{FunctionCallAbi, GeneratedSource, IRQueries}
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  test "watchface_yes plan call_fn uses argv for wrapper callees and direct for worker view entry" do
    out_dir = Path.expand("tmp/plan_direct_call_abi_yes", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("watchface_yes",
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               out_dir: out_dir
             )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_view")

    assert view_body =~ "plan block"
    assert view_body =~ "elmc_fn_Main_faceOps(&owned[0], model)"
    refute view_body =~ "elmc_fn_Main_faceOps(&owned[1], plan_argv_"
  end

  test "game_elmtris plan-primary helpers use direct ABI not argv wrappers" do
    out_dir = Path.expand("tmp/plan_direct_call_abi_elmtris", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("game_elmtris",
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               out_dir: out_dir
             )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "static elmc_int_t elmc_fn_Main_boardRows(void);"
    assert generated_c =~ "static RC elmc_fn_Main_cellAt(ElmcValue **out, elmc_int_t x, elmc_int_t y, ElmcValue *board);"

    cell_at_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_cellAt")
    refute cell_at_body =~ "argc > 0"
    refute cell_at_body =~ "plan_argv"

    clear_lines_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_clearLines")
    refute clear_lines_body =~ "plan_argv"
    assert clear_lines_body =~ "elmc_fn_Main_clearLines_native"

    refute generated_c =~ ~r/elmc_fn_Main_\w+\(&owned\[[0-9]+\], \)/
    refute generated_c =~ "plan_primary_boxed"
    assert generated_c =~ "elmc_fn_Main_cellAt_native"
  end

  test "direct_plan_call_abi distinguishes wrapper and direct plan targets" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes",
        plan_ir_mode: :primary,
        plan_ir_strict: false
      )

    ir = result.ir
    opts = %{plan_ir_mode: :primary, entry_module: "Main", strip_dead_code: true}
    decl_map = IRQueries.function_decl_map(ir)
    GeneratedSource.prepare_emit_session!(ir, opts)

    view = Map.fetch!(decl_map, {"Main", "view"})
    face_ops = Map.fetch!(decl_map, {"Main", "faceOps"})

    assert FunctionCallAbi.direct_plan_call_abi?(view, "Main", decl_map, false)
    refute FunctionCallAbi.argv_abi?(view, "Main", decl_map)

    refute FunctionCallAbi.direct_plan_call_abi?(face_ops, "Main", decl_map, true)
    assert FunctionCallAbi.direct_plan_call_abi?(face_ops, "Main", decl_map)
    refute FunctionCallAbi.argv_abi?(face_ops, "Main", decl_map)
  end

  test "game_2048 plan-primary moveBoard callees are emitted with direct ABI" do
    out_dir = Path.expand("tmp/plan_direct_call_abi_2048", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("game_2048",
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               out_dir: out_dir
             )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    for helper <- ~w(orient collapseRows restore) do
      refute generated_c =~ "static RC elmc_fn_Main_#{helper}(ElmcValue **out"
    end

    move_board_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_moveBoard")
    assert move_board_body =~ "elmc_fn_Main_moveBoard_native"
    refute move_board_body =~ "elmc_fn_Main_orient(&owned["
    refute move_board_body =~ "plan_argv"
  end

  test "companion worker header prototypes match plan-primary direct entry ABI" do
    out_dir = Path.expand("tmp/plan_direct_call_abi_companion", __DIR__)
    File.rm_rf!(out_dir)

    project_dir = Path.expand("fixtures/companion_weather_worker", __DIR__)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               direct_render_only: true,
               prune_runtime: true,
               plan_ir_mode: :primary,
               plan_ir_strict: true
             })

    generated_h = File.read!(Path.join(out_dir, "c/elmc_generated.h"))
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_h =~ "RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model);"
    refute generated_h =~ "elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc)"

    update_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_update")
    assert update_body =~ "plan block"
    refute update_body =~ "argc > 0"
  end
end
