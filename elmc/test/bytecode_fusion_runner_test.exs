defmodule Elmc.BytecodeFusionRunnerTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Bytecode.FusionRunner
  alias Elmc.Backend.Plan.Types.FunctionPlan

  test "tuple2 case table fusion returns static offset pairs" do
    plan = %FunctionPlan{
      module: "Main",
      name: "pieceOffsets",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :tuple2_case_table,
      fusion_data: %{
        outer_mod: 7,
        rows: [
          %{
            kind: 0,
            rotations: [
              %{rot: 0, pairs: [[0, 0], [1, 0], [2, 0], [3, 0]]},
              %{rot: 1, pairs: [[1, 0], [2, 0], [3, 0], [0, 0]]}
            ]
          }
        ]
      }
    }

    assert {:ok, pairs} = FusionRunner.run(plan, params: [0, 0])
    assert pairs == [{:tuple2, 0, 0}, {:tuple2, 1, 0}, {:tuple2, 2, 0}, {:tuple2, 3, 0}]

    assert {:ok, rotated} = FusionRunner.run(plan, params: [0, 1])
    assert rotated == [{:tuple2, 1, 0}, {:tuple2, 2, 0}, {:tuple2, 3, 0}, {:tuple2, 0, 0}]
  end

  test "filter_map_row_drop fusion clears full rows and prepends zero rows" do
    plan = %FunctionPlan{
      module: "Main",
      name: "clearLines",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :filter_map_row_drop,
      fusion_data: %{rows: 3, cols: 2}
    }

    board = [1, 1, 0, 0, 1, 1]

    assert {:ok, {:tuple2, cleared_board, 2}} = FusionRunner.run(plan, params: [board])
    assert cleared_board == [0, 0, 0, 0, 0, 0]
  end

  test "foldl_offset_patch fusion stamps piece cells via nested offsets table" do
    offsets_plan = %FunctionPlan{
      module: "Main",
      name: "pieceOffsets",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :tuple2_case_table,
      fusion_data: %{
        outer_mod: 7,
        rows: [
          %{
            kind: 0,
            rotations: [%{rot: 0, pairs: [[0, 0], [1, 0]]}]
          }
        ]
      }
    }

    plan = %FunctionPlan{
      module: "Main",
      name: "stampPiece",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :foldl_offset_patch,
      fusion_data: %{
        cols: 4,
        rows: 2,
        offsets: {"Main", "pieceOffsets"},
        piece_fields: %{kind: 0, rot: 1, x: 2, y: 3}
      }
    }

    piece = {:record, [0, 0, 1, 0]}
    board = List.duplicate(0, 8)
    plans = %{{"Main", "pieceOffsets"} => offsets_plan}

    assert {:ok, stamped} = FusionRunner.run(plan, params: [piece, board], plans: plans)
    assert Enum.at(stamped, 1) == 1
    assert Enum.at(stamped, 2) == 1
  end

  test "reverse_foldl_occupied fusion collects nonzero flat indices" do
    plan = %FunctionPlan{
      module: "Main",
      name: "lockedSlotsFromBoard",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :reverse_foldl_occupied,
      fusion_data: %{count: 6}
    }

    board = [0, 2, 0, 0, 3, 1]

    assert {:ok, slots} = FusionRunner.run(plan, params: [board])
    assert slots == [1, 4, 5]
  end

  test "list_indexed_replace fusion patches flat list cell" do
    plan = %FunctionPlan{
      module: "Main",
      name: "setCell",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :list_indexed_replace,
      fusion_data: %{}
    }

    cells = [0, 0, 0, 0]

    assert {:ok, updated} = FusionRunner.run(plan, params: [2, 4, cells])
    assert updated == [0, 0, 4, 0]
  end

  test "list_int_search fusion finds nth zero index" do
    help_plan = %FunctionPlan{
      module: "Main",
      name: "nthEmptyIndexHelp",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :list_int_search,
      fusion_data: %{mode: :help, not_found: -1}
    }

    delegate_plan = %FunctionPlan{
      help_plan
      | name: "nthEmptyIndex",
        fusion_data: %{mode: :delegate, help: {"Main", "nthEmptyIndexHelp"}}
    }

    cells = [1, 0, 0, 3, 0]
    plans = %{{"Main", "nthEmptyIndexHelp"} => help_plan}

    assert {:ok, 1} = FusionRunner.run(help_plan, params: [0, 0, cells])
    assert {:ok, 2} = FusionRunner.run(help_plan, params: [1, 0, cells])
    assert {:ok, 4} = FusionRunner.run(help_plan, params: [2, 0, cells])
    assert {:ok, 1} = FusionRunner.run(delegate_plan, params: [0, cells], plans: plans)
    assert {:ok, 2} = FusionRunner.run(delegate_plan, params: [1, cells], plans: plans)
  end

  test "spawn_tile_chain fusion runs chained tile spawns on empty board" do
    plan = %FunctionPlan{
      module: "Main",
      name: "initialBoard",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :spawn_tile_chain,
      fusion_data: %{count: 4, passes: 2, board: :zeros}
    }

    assert {:ok, {:tuple2, cells, seed}} = FusionRunner.run(plan, params: [12345])
    assert length(cells) == 4
    assert Enum.count(cells, &(&1 != 0)) == 2
    assert is_integer(seed)
  end

  test "union_int_lut fusion maps union tags to wire ints" do
    plan = %FunctionPlan{
      module: "Companion.Internal",
      name: "watchToPhoneTag",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :union_int_lut,
      fusion_data: %{lut: %{1 => 2, 2 => 3, 3 => 4}, exhaustive: true}
    }

    assert {:ok, 2} = FusionRunner.run(plan, params: [1])
    assert {:ok, 4} = FusionRunner.run(plan, params: [3])
    assert :unsupported = FusionRunner.run(plan, params: [99])
  end

  test "list_map_static_index_at fusion gathers static indices from flat list" do
    plan = %FunctionPlan{
      module: "Main",
      name: "transpose",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :list_map_static_index_at,
      fusion_data: %{default: 0, indices: [0, 4, 1, 5]}
    }

    cells = [2, 0, 0, 0, 3, 0, 0, 0]

    assert {:ok, picked} = FusionRunner.run(plan, params: [cells])
    assert picked == [2, 3, 0, 0]
  end

  test "int_string_lut fusion maps int keys to string labels" do
    plan = %FunctionPlan{
      module: "Main",
      name: "monthString",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :int_string_lut,
      fusion_data: %{lut: %{1 => "Jan", 2 => "Feb", 3 => "Mar"}, default: "Dec"}
    }

    assert {:ok, "Jan"} = FusionRunner.run(plan, params: [1])
    assert {:ok, "Mar"} = FusionRunner.run(plan, params: [3])
    assert {:ok, "Dec"} = FusionRunner.run(plan, params: [12])
    assert :unsupported = FusionRunner.run(%{plan | fusion_data: %{lut: %{1 => "Jan"}}}, params: [99])
  end

  test "union_string_lut fusion maps union tags to strings" do
    plan = %FunctionPlan{
      module: "Main",
      name: "directionString",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :union_string_lut,
      fusion_data: %{lut: %{1 => "N", 2 => "E"}}
    }

    assert {:ok, "N"} = FusionRunner.run(plan, params: [1])
    assert {:ok, "E"} = FusionRunner.run(plan, params: [2])
  end

  test "maybe_int_string fusion formats default append and threshold case" do
    default_plan = %FunctionPlan{
      module: "Main",
      name: "batteryPercentString",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :maybe_int_string,
      fusion_data: %{mode: :default_append, field: 4, default: 0, suffix: "%"}
    }

    model = {:record, List.duplicate(nil, 20) |> List.replace_at(4, {:just, 85})}

    assert {:ok, "85%"} = FusionRunner.run(default_plan, params: [model])
    assert {:ok, "0%"} = FusionRunner.run(default_plan, params: [{:record, List.duplicate(nil, 20)}])

    case_plan = %FunctionPlan{
      module: "Main",
      name: "stepsString",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :maybe_int_string,
      fusion_data: %{
        mode: :maybe_case,
        field: 17,
        nothing: "--",
        format: %{kind: :threshold, threshold: 10_000, divisor: 1000, suffix: "k"}
      }
    }

    assert {:ok, "--"} =
             FusionRunner.run(case_plan, params: [{:record, List.duplicate(nil, 20)}])

    assert {:ok, "5000"} =
             FusionRunner.run(case_plan, params: [{:record, List.duplicate(nil, 20) |> List.replace_at(17, {:just, 5000})}])

    assert {:ok, "15k"} =
             FusionRunner.run(case_plan, params: [{:record, List.duplicate(nil, 20) |> List.replace_at(17, {:just, 15_000})}])
  end

  test "maybe_with_default_pick_slot fusion delegates to slots and pick callees" do
    slots_plan = %FunctionPlan{
      module: "Main",
      name: "bottomRightSlots",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :tuple2_case_table,
      fusion_data: %{outer_mod: 1, rows: []}
    }

    pick_plan = %FunctionPlan{
      module: "Main",
      name: "pickSlot",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :union_int_lut,
      fusion_data: %{lut: %{0 => 7}}
    }

    plan = %FunctionPlan{
      module: "Main",
      name: "pickBottomRight",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :maybe_with_default_pick_slot,
      fusion_data: %{
        default: 2,
        pick: {"Main", "pickSlot"},
        slots: {"Main", "bottomRightSlots"}
      }
    }

    model = {:record, []}
    plans = %{{"Main", "bottomRightSlots"} => slots_plan, {"Main", "pickSlot"} => pick_plan}

    assert {:ok, 7} = FusionRunner.run(plan, params: [model], plans: plans)

    missing_pick_plans = Map.delete(plans, {"Main", "pickSlot"})
    assert {:ok, 2} = FusionRunner.run(plan, params: [model], plans: missing_pick_plans)
  end

  test "union_case_four_perm fusion applies row-major direction permutes" do
    width = 4
    rows = 4
    tags = [0, 1, 2, 3]
    cells = Enum.to_list(0..15)

    plan = %FunctionPlan{
      module: "Main",
      name: "orient",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :union_case_four_perm,
      fusion_data: %{width: width, rows: rows, mode: :forward, tags: tags}
    }

    assert {:ok, left} = FusionRunner.run(plan, params: [0, cells])
    assert left == cells

    assert {:ok, right} = FusionRunner.run(plan, params: [1, cells])
    assert right == [3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12]

    assert {:ok, up} = FusionRunner.run(plan, params: [2, cells])
    assert up == [0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15]

    restore_plan = %{plan | name: "restore", fusion_data: %{width: width, rows: rows, mode: :inverse, tags: tags}}
    assert {:ok, restored} = FusionRunner.run(restore_plan, params: [2, up])
    assert restored == cells
  end

  test "union_int_suffix fusion formats direct union and scaled maybe-map branches" do
    direct_plan = %FunctionPlan{
      module: "Main",
      name: "windSpeedString",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :union_int_suffix,
      fusion_data: %{
        mode: :direct,
        branches: [
          %{tag: 1, prefix: "", suffix: "m/s", expr: %{kind: :var}},
          %{tag: 2, prefix: "", suffix: "mph", expr: %{kind: :var}}
        ]
      }
    }

    assert {:ok, "5m/s"} = FusionRunner.run(direct_plan, params: [{:union, 1, 5}])
    assert {:ok, "10mph"} = FusionRunner.run(direct_plan, params: [{:union, 2, 10}])

    temp_plan = %FunctionPlan{
      module: "Main",
      name: "temperatureString",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :union_int_suffix,
      fusion_data: %{
        mode: :maybe_map_field,
        nothing: "--",
        outer_field: 11,
        inner_field: 0,
        branches: [
          %{tag: 1, prefix: "", suffix: "C", expr: %{kind: :scaled, offset: 5, divisor: 10}},
          %{tag: 2, prefix: "", suffix: "F", expr: %{kind: :scaled, offset: 5, divisor: 10}}
        ]
      }
    }

    model = {:record, List.duplicate(nil, 20)}

    assert {:ok, "--"} = FusionRunner.run(temp_plan, params: [model])

    weather = {:record, [{:union, 1, 235}, 0, 0, 0, 0]}

    assert {:ok, "24C"} =
             FusionRunner.run(temp_plan, params: [{:record, List.replace_at(List.duplicate(nil, 20), 11, {:just, weather})}])
  end

  test "row_slice_adjacent_merge fusion collapses equal adjacent tiles per row" do
    plan = %FunctionPlan{
      module: "Main",
      name: "collapseRows",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :row_slice_adjacent_merge,
      fusion_data: %{width: 4, rows: 4}
    }

    cells = List.duplicate(0, 16) |> List.replace_at(0, 2) |> List.replace_at(1, 2)

    assert {:ok, {:record, [collapsed, 4]}} = FusionRunner.run(plan, params: [cells])
    assert length(collapsed) == 16
    assert Enum.at(collapsed, 0) == 4
    assert Enum.all?(Enum.drop(collapsed, 1), &(&1 == 0))
  end

  test "list_concat_reversed_row_slices fusion reverses each row slice" do
    plan = %FunctionPlan{
      module: "Main",
      name: "reverseRows",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :list_concat_reversed_row_slices,
      fusion_data: %{width: 4, rows: 4}
    }

    cells = Enum.to_list(0..15)

    assert {:ok, reversed} = FusionRunner.run(plan, params: [cells])
    assert reversed == [3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12]
  end

  test "permute_merge_inverse_pipeline fusion runs orient collapse restore spawn update" do
    plan = %FunctionPlan{
      module: "Main",
      name: "moveBoard",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: :permute_merge_inverse_pipeline,
      fusion_data: %{
        width: 4,
        rows: 4,
        tags: [1, 2, 3, 4],
        storage_key: 2048,
        fields: %{cells: 0, seed: 3, score: 1, best: 2, turn: 4}
      }
    }

    empty_cells = List.duplicate(0, 16)
    empty_model = {:record, [empty_cells, 0, 0, 99_001, 0, 144, 168, 0]}

    assert {:ok, {:tuple2, ^empty_model, 0}} =
             FusionRunner.run(plan, params: [1, empty_model])

    merge_cells = List.duplicate(0, 16) |> List.replace_at(0, 2) |> List.replace_at(1, 2)
    merge_model = {:record, [merge_cells, 0, 0, 99_001, 0, 144, 168, 0]}

    assert {:ok, {:tuple2, {:record, fields}, {:pebble_cmd, :cmd1_string, 26, [2048, "4"]}}} =
             FusionRunner.run(plan, params: [1, merge_model])

    assert Enum.at(fields, 1) == 4
    assert Enum.at(fields, 2) == 4
    assert Enum.at(fields, 4) == 1
    assert Enum.at(fields, 3) != 99_001
    updated_cells = Enum.at(fields, 0)
    assert Enum.at(updated_cells, 0) == 4
    assert Enum.count(updated_cells, &(&1 != 0)) == 2

    kept_best_model = {:record, [merge_cells, 0, 4, 99_001, 0, 144, 168, 0]}

    assert {:ok, {:tuple2, {:record, kept_fields}, 0}} =
             FusionRunner.run(plan, params: [1, kept_best_model])

    assert Enum.at(kept_fields, 2) == 4
  end
end
