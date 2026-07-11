defmodule Elmc.Plan2048BytecodeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Loader
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow
  @template "game_2048"

  test "game_2048 fused setCell and nthEmptyIndex run from bytecode manifest" do
    out_dir = Path.expand("tmp/plan_2048_bytecode", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template(@template,
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    {:ok, manifest} =
      Loader.load_manifest(Path.join(out_dir, "bytecode/elmc_bytecode.manifest.json"))

    fusion_names =
      (manifest["fusion_functions"] || [])
      |> Enum.map(& &1["name"])
      |> MapSet.new()

    assert MapSet.member?(fusion_names, "setCell")
    assert MapSet.member?(fusion_names, "nthEmptyIndex")
    assert MapSet.member?(fusion_names, "initialBoard")

    assert MapSet.member?(fusion_names, "moveBoard")

    refute Enum.any?(manifest["skipped"] || [], fn entry ->
             entry["name"] in ["setCell", "nthEmptyIndex", "initialBoard", "orient", "restore", "collapseRows", "reverseRows", "moveBoard"] and
               entry["reason"] == "empty_plan"
           end)

    cells = List.duplicate(0, 16)

    assert {:ok, updated} =
             Loader.run_manifest_entry(out_dir, {"Main", "setCell"}, params: [5, 2, cells])

    assert is_list(updated)
    assert length(updated) == 16
    assert Enum.at(updated, 5) == 2

    assert {:ok, 0} =
             Loader.run_manifest_entry(out_dir, {"Main", "nthEmptyIndex"}, params: [0, updated])

    assert {:ok, 6} =
             Loader.run_manifest_entry(out_dir, {"Main", "nthEmptyIndex"}, params: [5, updated])

    assert {:ok, -1} =
             Loader.run_manifest_entry(out_dir, {"Main", "nthEmptyIndex"}, params: [99, updated])

    assert {:ok, {:tuple2, board, seed}} =
             Loader.run_manifest_entry(out_dir, {"Main", "initialBoard"}, params: [12345])

    assert is_list(board)
    assert length(board) == 16
    assert Enum.count(board, &(&1 != 0)) == 2
    assert is_integer(seed)

    cells = List.duplicate(0, 16) |> List.replace_at(0, 2) |> List.replace_at(4, 4)

    if MapSet.member?(fusion_names, "transpose") do
      assert {:ok, transposed} =
               Loader.run_manifest_entry(out_dir, {"Main", "transpose"}, params: [cells])

      assert length(transposed) == 16
      assert Enum.at(transposed, 0) == 2
      assert Enum.at(transposed, 1) == 4
    end

    cells = Enum.to_list(0..15)

    if MapSet.member?(fusion_names, "orient") do
      assert {:ok, left} = Loader.run_manifest_entry(out_dir, {"Main", "orient"}, params: [1, cells])
      assert left == cells

      assert {:ok, right} = Loader.run_manifest_entry(out_dir, {"Main", "orient"}, params: [2, cells])

      assert right == [3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12]
    end

    if MapSet.member?(fusion_names, "restore") do
      oriented = [0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15]

      assert {:ok, restored} =
               Loader.run_manifest_entry(out_dir, {"Main", "restore"}, params: [3, oriented])

      assert restored == cells
    end

    if MapSet.member?(fusion_names, "collapseRows") do
      cells = List.duplicate(0, 16) |> List.replace_at(0, 2) |> List.replace_at(1, 2)

      assert {:ok, {:record, [collapsed, score]}} =
               Loader.run_manifest_entry(out_dir, {"Main", "collapseRows"}, params: [cells])

      assert score == 4
      assert Enum.at(collapsed, 0) == 4
    end

    cells = Enum.to_list(0..15)

    if MapSet.member?(fusion_names, "reverseRows") do
      assert {:ok, reversed} = Loader.run_manifest_entry(out_dir, {"Main", "reverseRows"}, params: [cells])
      assert reversed == [3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12]
    end

    if MapSet.member?(fusion_names, "moveBoard") do
      empty_cells = List.duplicate(0, 16)
      empty_model = {:record, [empty_cells, 0, 0, 12_345, 0, 144, 168, 0]}

      assert {:ok, {:tuple2, ^empty_model, 0}} =
               Loader.run_manifest_entry(out_dir, {"Main", "moveBoard"}, params: [1, empty_model])

      merge_cells = List.duplicate(0, 16) |> List.replace_at(0, 2) |> List.replace_at(1, 2)
      merge_model = {:record, [merge_cells, 0, 0, 12_345, 0, 144, 168, 0]}

      assert {:ok, {:tuple2, {:record, fields}, {:pebble_cmd, :cmd1_string, 26, [2048, "4"]}}} =
               Loader.run_manifest_entry(out_dir, {"Main", "moveBoard"}, params: [1, merge_model])

      assert Enum.at(fields, 1) == 4
      assert Enum.at(fields, 4) == 1
      updated_cells = Enum.at(fields, 0)
      assert Enum.at(updated_cells, 0) == 4
      assert Enum.count(updated_cells, &(&1 != 0)) == 2
    end

    cells = List.duplicate(0, 16) |> List.replace_at(3, 2) |> List.replace_at(7, 4)

    assert {:ok, 14} =
             Loader.run_manifest_entry(out_dir, {"Main", "countEmpty"}, params: [cells])

    assert {:ok, {:tuple2, spawned, next_seed}} =
             Loader.run_manifest_entry(out_dir, {"Main", "spawnTileWithSeed"},
               params: [12_345, List.duplicate(0, 16)]
             )

    assert is_list(spawned)
    assert length(spawned) == 16
    assert Enum.count(spawned, &(&1 != 0)) == 1
    assert is_integer(next_seed)
  end
end
