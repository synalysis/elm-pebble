defmodule Elmc.PlanYesBytecodeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Loader
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow
  @template "watchface_yes"

  test "watchface_yes fused string helpers run from bytecode manifest" do
    out_dir = Path.expand("tmp/plan_yes_bytecode", __DIR__)
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

    if MapSet.member?(fusion_names, "monthString") do
      assert {:ok, "Jan"} = Loader.run_manifest_entry(out_dir, {"Main", "monthString"}, params: [1])
      assert {:ok, "Dec"} = Loader.run_manifest_entry(out_dir, {"Main", "monthString"}, params: [12])
    end

    if MapSet.member?(fusion_names, "directionString") do
      assert {:ok, label} =
               Loader.run_manifest_entry(out_dir, {"Main", "directionString"}, params: [1])

      assert is_binary(label)
      assert label != ""
    end

    yes_model = fn fields ->
      base = List.duplicate(nil, 20)

      {:record,
       Enum.reduce(fields, base, fn {idx, val}, acc ->
         List.replace_at(acc, idx, val)
       end)}
    end

    if MapSet.member?(fusion_names, "batteryPercentString") do
      assert {:ok, "85%"} =
               Loader.run_manifest_entry(out_dir, {"Main", "batteryPercentString"},
                 params: [yes_model.([{4, {:just, 85}}])]
               )
    end

    if MapSet.member?(fusion_names, "stepsString") do
      assert {:ok, "--"} =
               Loader.run_manifest_entry(out_dir, {"Main", "stepsString"},
                 params: [yes_model.([])]
               )

      assert {:ok, "5000"} =
               Loader.run_manifest_entry(out_dir, {"Main", "stepsString"},
                 params: [yes_model.([{17, {:just, 5000}}])]
               )

      assert {:ok, "15k"} =
               Loader.run_manifest_entry(out_dir, {"Main", "stepsString"},
                 params: [yes_model.([{17, {:just, 15_000}}])]
               )
    end

    refute Enum.any?(manifest["skipped"] || [], fn entry ->
             entry["name"] in [
               "monthString",
               "directionString",
               "batteryPercentString",
               "stepsString",
               "pickBottomRight",
               "temperatureString",
               "windSpeedString"
             ] and
               entry["reason"] == "empty_plan"
           end)

    if MapSet.member?(fusion_names, "windSpeedString") do
      assert {:ok, "5m/s"} =
               Loader.run_manifest_entry(out_dir, {"Main", "windSpeedString"},
                 params: [{:union, 1, 5}]
               )
    end

    if MapSet.member?(fusion_names, "temperatureString") do
      weather = {:record, [{:union, 1, 235}, 0, 0, 0, 0]}

      assert {:ok, "--"} =
               Loader.run_manifest_entry(out_dir, {"Main", "temperatureString"},
                 params: [yes_model.([])]
               )

      assert {:ok, "24C"} =
               Loader.run_manifest_entry(out_dir, {"Main", "temperatureString"},
                 params: [yes_model.([{11, {:just, weather}}])]
               )
    end

    if MapSet.member?(fusion_names, "pickBottomRight") do
      assert {:ok, corner} =
               Loader.run_manifest_entry(out_dir, {"Main", "pickBottomRight"},
                 params: [yes_model.([])]
               )

      assert is_integer(corner)
    end
  end

  test "watchface_yes view runs from bytecode manifest" do
    out_dir = Path.expand("tmp/plan_yes_bytecode_view", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template(@template,
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               out_dir: out_dir
             )

    model = {:record, List.duplicate(nil, 20)}

    task =
      Task.async(fn ->
        Loader.run_manifest_entry(out_dir, {"Main", "view"}, params: [model])
      end)

    result =
      case Task.yield(task, 15_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, value} -> value
        nil -> flunk("bytecode view for watchface_yes timed out")
      end

    assert {:ok, view_ops} = result
    assert is_list(view_ops)
    assert Enum.any?(view_ops, &match?({:render_cmd, _, _}, &1))
  end
end
