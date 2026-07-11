defmodule Elmc.PlanFusionManifestAuditTest do
  @moduledoc """
  Cross-template audit: fused functions in bytecode manifests must carry runnable
  `fusion_kind` metadata (not `empty_plan` skips).
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.{FusionRunner, Loader, ManifestProgram}
  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  @expectations %{
    "game_2048" => %{
      "setCell" => "list_indexed_replace",
      "nthEmptyIndex" => "list_int_search",
      "initialBoard" => "spawn_tile_chain",
      "moveBoard" => "permute_merge_inverse_pipeline",
      "orient" => "union_case_four_perm",
      "restore" => "union_case_four_perm",
      "collapseRows" => "row_slice_adjacent_merge",
      "reverseRows" => "list_concat_reversed_row_slices",
      "transpose" => "list_map_static_index_at"
    },
    "game_elmtris" => %{
      "pieceOffsets" => "tuple2_case_table",
      "clearLines" => "filter_map_row_drop",
      "stampPiece" => "foldl_offset_patch",
      "lockedSlotsFromBoard" => "reverse_foldl_occupied"
    },
    "watchface_yes" => %{
      "monthString" => "int_string_lut",
      "directionString" => "union_string_lut",
      "batteryPercentString" => "maybe_int_string",
      "stepsString" => "maybe_int_string",
      "pickBottomRight" => "maybe_with_default_pick_slot",
      "temperatureString" => "union_int_suffix",
      "windSpeedString" => "union_int_suffix",
      "altitudeString" => "union_int_suffix"
    }
  }

  for {template, expected} <- @expectations do
    @tag template: template

    test "fusion manifest audit for #{template}", %{template: template} do
      expected = unquote(Macro.escape(expected))
      out_dir = Path.expand("tmp/plan_fusion_audit/#{template}", __DIR__)
      File.rm_rf!(out_dir)

      assert {:ok, _result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 out_dir: out_dir
               )

      {:ok, manifest} =
        Loader.load_manifest(Path.join(out_dir, "bytecode/elmc_bytecode.manifest.json"))

      fusion_by_name =
        (manifest["fusion_functions"] || [])
        |> Map.new(fn entry -> {entry["name"], entry} end)

      for {name, kind} <- expected do
        entry = Map.fetch!(fusion_by_name, name)
        assert entry["fusion_kind"] == kind
        assert is_map(entry["fusion_data"])

        if kind != "list_indexed_replace" do
          assert map_size(entry["fusion_data"]) > 0
        end
      end

      refute Enum.any?(manifest["skipped"] || [], fn entry ->
               Map.has_key?(expected, entry["name"]) and entry["reason"] == "empty_plan"
             end)

      assert {:ok, program} = ManifestProgram.load_linked(out_dir, {"Main", "init"})

      for {name, _kind} <- expected do
        plan = Map.fetch!(program.fusion_plans, {"Main", name})
        assert FusionRunner.runnable?(plan)
        assert plan.fusion_kind != nil
      end

      assert_manifest_execution_smoke(out_dir, template)
    end
  end

  defp assert_manifest_execution_smoke(out_dir, "watchface_yes") do
    yes_model = fn fields ->
      base = List.duplicate(nil, 20)

      {:record,
       Enum.reduce(fields, base, fn {idx, val}, acc ->
         List.replace_at(acc, idx, val)
       end)}
    end

    assert {:ok, "5m/s"} =
             Loader.run_manifest_entry(out_dir, {"Main", "windSpeedString"}, params: [{:union, 1, 5}])

    weather = {:record, [{:union, 1, 235}, 0, 0, 0, 0]}

    assert {:ok, "24C"} =
             Loader.run_manifest_entry(out_dir, {"Main", "temperatureString"},
               params: [yes_model.([{11, {:just, weather}}])]
             )
  end

  defp assert_manifest_execution_smoke(out_dir, "game_2048") do
    cells = List.duplicate(0, 16) |> List.replace_at(0, 2) |> List.replace_at(1, 2)

    assert {:ok, {:record, [collapsed, score]}} =
             Loader.run_manifest_entry(out_dir, {"Main", "collapseRows"}, params: [cells])

    assert score == 4
    assert Enum.at(collapsed, 0) == 4

    merge_model = {:record, [cells, 0, 0, 12_345, 0, 144, 168, 0]}

    assert {:ok, {:tuple2, {:record, fields}, _cmd}} =
             Loader.run_manifest_entry(out_dir, {"Main", "moveBoard"}, params: [1, merge_model])

    assert Enum.at(fields, 1) == 4
  end

  defp assert_manifest_execution_smoke(out_dir, "game_elmtris") do
    board = List.duplicate(0, 140)

    assert {:ok, {:tuple2, cleared, 0}} =
             Loader.run_manifest_entry(out_dir, {"Main", "clearLines"}, params: [board])

    assert length(cleared) == 140

    assert {:ok, pairs} = Loader.run_manifest_entry(out_dir, {"Main", "pieceOffsets"}, params: [0, 0])
    assert is_list(pairs)
    assert pairs != []
  end

  defp assert_manifest_execution_smoke(_out_dir, _template), do: :ok

  test "every registered manifest fusion kind has a FusionRunner clause" do
    source_path = Path.expand("../lib/elmc/backend/bytecode/manifest_program.ex", __DIR__)

    kinds =
      source_path
      |> File.read!()
      |> then(fn source ->
        ~r/"([a-z_]+)" => :([a-z_]+)/
        |> Regex.scan(source)
        |> Enum.map(fn [_, wire, atom] -> {wire, String.to_atom(atom)} end)
      end)

    sample_plan = %FunctionPlan{
      module: "Main",
      name: "probe",
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
      fusion_kind: nil,
      fusion_data: %{}
    }

    for {wire, kind} <- kinds do
      plan = %{sample_plan | fusion_kind: kind, fusion_data: minimal_fusion_data(kind)}
      assert FusionRunner.runnable?(plan), "missing runnable? for #{wire}/#{kind}"

      result = FusionRunner.run(plan, params: sample_params(kind))
      assert match?({:ok, _}, result) or result == :unsupported,
             "FusionRunner.run/2 missing clause for #{wire}/#{kind}"
    end
  end

  defp minimal_fusion_data(:tuple2_case_table),
    do: %{"outer_mod" => 4, "rows" => [%{"kind" => 0, "rotations" => [%{"rot" => 0, "pairs" => []}]}]}

  defp minimal_fusion_data(:filter_map_row_drop), do: %{"rows" => 1, "cols" => 1}
  defp minimal_fusion_data(:foldl_offset_patch), do: %{"cols" => 1, "rows" => 1, "piece_fields" => %{}}
  defp minimal_fusion_data(:reverse_foldl_occupied), do: %{"cols" => 1, "rows" => 1}
  defp minimal_fusion_data(:list_indexed_replace), do: %{}
  defp minimal_fusion_data(:list_int_search), do: %{"not_found" => -1}
  defp minimal_fusion_data(:spawn_tile_chain), do: %{"count" => 16, "passes" => 2, "board" => "zeros"}
  defp minimal_fusion_data(:union_int_lut), do: %{"lut" => %{"1" => 2}}
  defp minimal_fusion_data(:union_string_lut), do: %{"lut" => %{"1" => "x"}}
  defp minimal_fusion_data(:int_string_lut), do: %{"lut" => %{"1" => "Jan"}, "default" => "?"}
  defp minimal_fusion_data(:list_map_static_index_at), do: %{"default" => 0, "indices" => [0]}
  defp minimal_fusion_data(:maybe_int_string),
    do: %{"mode" => "maybe_case", "field" => 0, "nothing" => "--", "format" => %{"kind" => "plain", "suffix" => ""}}
  defp minimal_fusion_data(:maybe_with_default_pick_slot), do: %{"default" => 0, "pick" => %{"module" => "Main", "name" => "x"}, "slots" => %{"module" => "Main", "name" => "y"}}
  defp minimal_fusion_data(:union_case_four_perm), do: %{"width" => 4, "rows" => 4, "tags" => [1, 2, 3, 4], "mode" => "forward"}
  defp minimal_fusion_data(:union_int_suffix),
    do: %{
      "mode" => "direct",
      "branches" => [
        %{"tag" => 1, "prefix" => "", "suffix" => "m/s", "expr" => %{"kind" => "var"}}
      ]
    }
  defp minimal_fusion_data(:row_slice_adjacent_merge), do: %{"width" => 4, "rows" => 4}
  defp minimal_fusion_data(:list_concat_reversed_row_slices), do: %{"width" => 4, "rows" => 4}

  defp minimal_fusion_data(:permute_merge_inverse_pipeline),
    do: %{
      "width" => 4,
      "rows" => 4,
      "tags" => [1, 2, 3, 4],
      "storage_key" => 2048,
      "fields" => %{"cells" => 0, "seed" => 3, "score" => 1, "best" => 2, "turn" => 4}
    }

  defp sample_params(:tuple2_case_table), do: [0, 0]
  defp sample_params(:filter_map_row_drop), do: [List.duplicate(0, 1)]
  defp sample_params(:foldl_offset_patch), do: [{:record, [0, 0, 0, 0]}, List.duplicate(0, 1)]
  defp sample_params(:reverse_foldl_occupied), do: [List.duplicate(0, 1)]
  defp sample_params(:list_indexed_replace), do: [0, 1, List.duplicate(0, 4)]
  defp sample_params(:list_int_search), do: [0, 0, List.duplicate(0, 4)]
  defp sample_params(:spawn_tile_chain), do: [1]
  defp sample_params(:union_int_lut), do: [1]
  defp sample_params(:union_string_lut), do: [1]
  defp sample_params(:int_string_lut), do: [1]
  defp sample_params(:list_map_static_index_at), do: [List.duplicate(0, 4)]
  defp sample_params(:maybe_int_string), do: [{:record, List.duplicate(nil, 4)}]
  defp sample_params(:maybe_with_default_pick_slot), do: [{:record, List.duplicate(nil, 4)}]
  defp sample_params(:union_case_four_perm), do: [1, List.duplicate(0, 16)]
  defp sample_params(:union_int_suffix), do: [{:union, 1, 5}]
  defp sample_params(:row_slice_adjacent_merge), do: [List.duplicate(0, 16)]
  defp sample_params(:list_concat_reversed_row_slices), do: [Enum.to_list(0..15)]

  defp sample_params(:permute_merge_inverse_pipeline),
    do: [1, {:record, [List.duplicate(0, 16), 0, 0, 1, 0, 144, 168, 0]}]
end
