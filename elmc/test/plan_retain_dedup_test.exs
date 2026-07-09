defmodule Elmc.PlanRetainDedupTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Optimize
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Test.CCodegenExtract

  test "dup_regs_for_owned_consume reuses canonical reg per source" do
    b0 = Builder.new("Main", "f", args: [], rc_required: true)
    {r_x, b1} = Builder.fresh_reg(b0)
    {r_y, b2} = Builder.fresh_reg(b1)

    {regs, b3} = Builder.dup_regs_for_owned_consume(b2, [r_x, r_y, r_x, r_y, r_x, r_y])

    assert length(Enum.uniq(regs)) == 2
    assert length(retain_instrs(b3)) == 0
  end

  test "boardLayout record branches avoid preemptive retains and use native int record" do
    out_dir = Path.expand("tmp/plan_board_layout_record", __DIR__)
    project_dir = Path.expand("tmp/plan_board_layout_record_project", __DIR__)
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
    body = CCodegenExtract.fn_body(c, "elmc_fn_Main_boardLayout")

    assert body =~ "elmc_record_new_values_ints"
    refute body =~ "elmc_record_new_values_take"
    refute String.match?(body, ~r/elmc_retain\(owned\[\d+\]\);\s+ElmcValue \*rec_values_/s)
  end

  test "drawCell uses static value list for context attrs and drops dead retain slots" do
    out_dir = Path.expand("tmp/plan_draw_cell_retain_dedup", __DIR__)
    project_dir = Path.expand("tmp/plan_draw_cell_retain_dedup_project", __DIR__)
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

    assert draw_body =~ "elmc_list_from_values_take"
    refute draw_body =~ "elmc_list_cons(&owned"
  end

  test "toUiNode builds singleton window and layer lists with list_from_values_take" do
    out_dir = Path.expand("tmp/plan_to_ui_node_list", __DIR__)
    project_dir = Path.expand("tmp/plan_to_ui_node_list_project", __DIR__)
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
    body = CCodegenExtract.fn_body(c, "elmc_fn_Pebble_Ui_toUiNode")

    assert body =~ "elmc_list_from_values_take"
    refute body =~ "elmc_list_cons(&owned"
    refute body =~ "elmc_list_nil()"
  end

  test "view string fusion inlines record field reads and avoids undeclared native locals" do
    out_dir = Path.expand("tmp/plan_view_string_fusion", __DIR__)
    project_dir = Path.expand("tmp/plan_view_string_fusion_project", __DIR__)
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
    view_body = CCodegenExtract.fn_body(c, "elmc_fn_Main_view")

    assert view_body =~
             ~r/snprintf\(native_string_buf_\d+, sizeof\(native_string_buf_\d+\), "Best %lld", \(long long\)\(ELMC_RECORD_GET_INDEX_INT/

    assert view_body =~
             ~r/snprintf\(native_string_buf_\d+, sizeof\(native_string_buf_\d+\), "2048  Best %lld", \(long long\)\(ELMC_RECORD_GET_INDEX_INT/

    refute view_body =~ ~r/snprintf\([^;]+plan_native_int_\d+\)/
    refute view_body =~ "elmc_string_append(&owned"
    refute view_body =~ ~r/elmc_new_string\(&owned\[\d+\], \"  \"\)/
  end

  test "optimize pass removes retain defs whose dest is never used" do
    plan = %FunctionPlan{
      module: "Main",
      name: "dead_retain",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      reg_count: 3,
      entry_block: 0,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %{
              id: 0,
              op: :call_runtime,
              dest: 1,
              args: %{builtin: :retain, args: [0]},
              effects: %{produces: {:owned, 1}, consumes: [], borrows: [0], fallible: false},
              block_id: 0,
              span: nil
            },
            %{
              id: 1,
              op: :call_runtime,
              dest: 2,
              args: %{builtin: :retain, args: [0]},
              effects: %{produces: {:owned, 2}, consumes: [], borrows: [0], fallible: false},
              block_id: 0,
              span: nil
            }
          ],
          terminator: {:ret, 2}
        }
      ],
      lambdas: [],
      lambda_arg_count: nil
    }

    optimized = Optimize.run(plan)
    [block] = optimized.blocks
    assert [%{dest: 2}] = retain_instrs_plan(block.instrs)
  end

  defp retain_instrs(b) do
    b.current_block.instrs
    |> Enum.filter(&match?(%{op: :call_runtime, args: %{builtin: :retain}}, &1))
  end

  defp retain_instrs_plan(instrs) do
    Enum.filter(instrs, &match?(%{op: :call_runtime, args: %{builtin: :retain}}, &1))
  end
end
