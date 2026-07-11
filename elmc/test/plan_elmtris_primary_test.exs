defmodule Elmc.PlanElmtrisPrimaryTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Loader
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow
  @template "game_elmtris"

  test "game_elmtris primary emits plan C and bytecode for all Main functions" do
    out_dir = Path.expand("tmp/plan_elmtris_primary", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             TemplateCompile.compile_watch_template(@template,
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)
    report = PrimaryCoverage.main_functions_report(decl_map, ir: result.ir)

    assert report.total == 44
    assert report.lowered == report.total,
           "expected full Main coverage, got #{report.lowered}/#{report.total}: #{inspect(Enum.take(report.failed, 6))}"

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_update")
    assert update_body =~ "plan block"
    assert update_body =~ "ELMC_UNION_MAIN_FRAMETICK"
    assert update_body =~ "switch (" or update_body =~ "elmc_union_tag_matches"
    assert update_body =~ "goto elmc_plan_block_"
    assert update_body =~ "elmc_string_to_int"
    refute update_body =~ "argc > 0"
    refute update_body =~ "args[0]"
    refute generated_c =~ "plan_primary_boxed"
    assert generated_c =~ "elmc_fn_Main_cellAt_native"

    assert generated_c =~ "RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model)"

    worker_c = File.read!(Path.join(out_dir, "c/elmc_worker.c"))
    assert worker_c =~ "elmc_fn_Main_update(&result, msg, state->model)"
    refute worker_c =~ "elmc_fn_Main_update(&result, args, 2)"

    lock_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_lockPiece")
    assert lock_body =~ "plan block"
    assert lock_body =~ "elmc_string_from_int" or lock_body =~ "elmc_string_from_native_int"

    manifest_path = Path.join(out_dir, "bytecode/elmc_bytecode.manifest.json")
    assert File.exists?(manifest_path)

    {:ok, manifest} = Loader.load_manifest(manifest_path)
    main_cov = get_in(manifest, ["plan_coverage", "main"])
    reachable_cov = get_in(manifest, ["plan_coverage", "reachable"])

    assert main_cov["total"] == 44
    assert main_cov["lowered"] == 44
    assert main_cov["failed_count"] == 0

    assert reachable_cov["total"] == 44
    assert reachable_cov["lowered"] == 44
    assert reachable_cov["failed_count"] == 0

    assert {:ok, 10} = Loader.run_manifest_entry(out_dir, {"Main", "boardCols"}, params: [])
    assert {:ok, 14} = Loader.run_manifest_entry(out_dir, {"Main", "boardRows"}, params: [])

    # pieceOffsets is fused to a static (kind, rot) lookup table — bytecode uses fusion_functions sidecar.
    assert generated_c =~ "pieceOffsets_k0_r0"
    assert generated_c =~ "elmc_fn_Main_pieceOffsets_native"

    assert {:ok, offsets} = Loader.run_manifest_entry(out_dir, {"Main", "pieceOffsets"}, params: [0, 0])
    assert is_list(offsets)
    assert length(offsets) == 4
    assert Enum.all?(offsets, &match?({:tuple2, _, _}, &1))

    assert {:ok, board} = Loader.run_manifest_entry(out_dir, {"Main", "emptyBoard"}, params: [])
    assert is_list(board)
    assert length(board) == 140

    # offsetFits/canPlace call fused pieceOffsets through manifest fusion dispatch.
    assert generated_c =~ "elmc_fn_Main_offsetFits"
    assert generated_c =~ "elmc_fn_Main_canPlace"

    assert {:ok, {:tuple2, board_out, {:tuple2, piece, seed}}} =
             Loader.run_manifest_entry(out_dir, {"Main", "spawnPiece"}, params: [board, 0])

    assert is_list(board_out)
    assert match?({:just, {:record, _}}, piece)
    assert is_integer(seed)

    {:ok, model} =
      Loader.run_manifest_entry(out_dir, {"Main", "freshModel"}, params: [0, 1, 144, 168, 0])

    assert {:ok, {:tuple2, updated, _cmd}} =
             Loader.run_manifest_entry(out_dir, {"Main", "tickGravity"}, params: [model])

    assert match?({:record, _}, updated)

    {:ok, {:record, fields_before}} = {:ok, model}
    assert Enum.at(fields_before, 11) == 0

    # FrameTick (tag 1) routes to tickGravity; frame payload is ignored.
    assert {:ok, {:tuple2, {:record, fields_after}, _cmd}} =
             Loader.run_manifest_entry(out_dir, {"Main", "update"}, params: [1, model])

    assert Enum.at(fields_after, 11) == 1

    with_piece_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_withPiece")

    refute with_piece_body =~
             ~r/elmc_maybe_just_payload\(owned\[\d+\]\);\s*\n\s*owned\[\d+\] = elmc_retain\(owned\[\d+\]\);\s*\n\s*owned\[\d+\] = NULL;\s*\n\s*owned\[\d+\] = elmc_maybe_just_payload\(owned\[\d+\]\);/,
             "withPiece must not unwrap Just payload twice on the ActivePiece record"

    assert with_piece_body =~ "ELMC_FIELD_MAIN_ACTIVEPIECE_KIND"
    assert generated_c =~ "elmc_fn_Main_dropStep"
    assert generated_c =~ "elmc_fn_Main_softDrop"
    assert generated_c =~ "elmc_fn_Main_clearLines_native"
    assert generated_c =~ "elmc_fn_Main_stampPiece"

    fusion_names =
      manifest["fusion_functions"]
      |> Enum.map(& &1["name"])
      |> MapSet.new()

    assert MapSet.member?(fusion_names, "pieceOffsets")
    assert MapSet.member?(fusion_names, "clearLines")
    assert MapSet.member?(fusion_names, "stampPiece")
    assert MapSet.member?(fusion_names, "lockedSlotsFromBoard")

    refute Enum.any?(manifest["skipped"] || [], fn entry ->
             MapSet.member?(fusion_names, entry["name"]) and entry["reason"] == "empty_plan"
           end)

    assert {:ok, view_ops} = Loader.run_manifest_entry(out_dir, {"Main", "view"}, params: [model])
    assert is_list(view_ops)
    assert length(view_ops) > 0
    assert Enum.any?(view_ops, &match?({:render_cmd, _, _}, &1))

    {:ok, model_with_piece} =
      Loader.run_manifest_entry(out_dir, {"Main", "withPiece"}, params: [
        model,
        {:just, {:record, [0, 0, 3, 0]}}
      ])

    assert {:ok, {:tuple2, {:record, locked_fields}, _cmd}} =
             Loader.run_manifest_entry(out_dir, {"Main", "lockPiece"}, params: [model_with_piece])

    board_after = Enum.at(locked_fields, 0)
    assert is_list(board_after)
    assert length(board_after) == 140
    assert Enum.count(board_after, &(&1 != 0)) >= 4

    assert {:ok, stamped} =
             Loader.run_manifest_entry(out_dir, {"Main", "stampPiece"}, params: [
               {:record, [0, 0, 3, 0]},
               board
             ])

    assert Enum.at(stamped, 3) == 1
    assert Enum.at(stamped, 4) == 1
    assert Enum.at(stamped, 5) == 1
    assert Enum.at(stamped, 6) == 1

    full_bottom =
      for i <- 0..139 do
        if i >= 130, do: 1, else: 0
      end

    assert {:ok, {:tuple2, cleared_board, lines}} =
             Loader.run_manifest_entry(out_dir, {"Main", "clearLines"}, params: [full_bottom])

    assert lines == 1
    assert length(cleared_board) == 140
    assert Enum.all?(Enum.take(cleared_board, 10), &(&1 == 0))
    assert Enum.at(cleared_board, 129) == 0

    assert {:ok, locked_slots} =
             Loader.run_manifest_entry(out_dir, {"Main", "lockedSlotsFromBoard"}, params: [stamped])

    assert locked_slots == [3, 4, 5, 6]

    # Nested int/tag case merge blocks (e.g. pieceOffsets) now reserve merge block ids.
    assert {:ok, {:tuple2, _model, _cmd}} =
             Loader.run_manifest_entry(out_dir, {"Main", "init"}, params: [{:record, [0, nil]}])
  end

  test "game_elmtris prod watch flags emit plan-primary C" do
    out_dir = Path.expand("tmp/plan_elmtris_prod_primary", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             TemplateCompile.compile_watch_template(@template,
               out_dir: out_dir,
               plan_ir_mode: :primary,
               pebble_int32: true
             )

    refute Enum.any?(result.layout_coercion_diagnostics || [], &(&1["code"] == "plan_primary_fallback"))

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    subs_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_subscriptions")

    assert subs_body =~ "elmc_sub1" or subs_body =~ "elmc_sub3",
           "plan-primary subscriptions must lower batch items to pebble_sub calls"

    assert subs_body =~ "elmc_list_from_values_take",
           "plan-primary subscriptions must return a Sub list, not Cmd.batch"

    refute subs_body =~ "elmc_cmd_batch",
           "plan-primary subscriptions must not use elmc_cmd_batch"

    update_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_update")

    assert update_body =~ "plan block"
    refute update_body =~ "argc > 0"
    assert File.exists?(Path.join(out_dir, "bytecode/elmc_bytecode.manifest.json"))
  end
end
