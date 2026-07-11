defmodule Elmc.BytecodePlatformOpsTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Loader

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  defp compile_fixture!(_opts \\ []) do
    out_dir = Path.expand("tmp/bytecode_platform_ops_#{System.unique_integer([:positive])}", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    out_dir
  end

  defp model_record(score \\ 42) do
    # cells, score, best, seed, turn, screenW, screenH, displayShape
    {:record, [nil, score, nil, nil, nil, 144, 168, nil]}
  end

  test "probeScoreOf returns model score field" do
    build_dir = compile_fixture!()

    assert {:ok, 42} =
             Loader.run_manifest_entry(build_dir, {"Main", "probeScoreOf"}, params: [model_record()])
  end

  test "subscriptions returns sub_batch list of pebble_sub entries" do
    build_dir = compile_fixture!()

    assert {:ok, result} =
             Loader.run_manifest_entry(build_dir, {"Main", "subscriptions"}, params: [model_record(0)])

    subs =
      case result do
        list when is_list(list) -> list
        :cmd_batch -> flunk("cmd_batch without list payload")
        other -> flunk("expected subscription list, got #{inspect(other)}")
      end

    assert length(subs) >= 4
    assert Enum.all?(subs, &match?({:pebble_sub, _, _}, &1))
  end
end
