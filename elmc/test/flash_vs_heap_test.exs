defmodule Elmc.FlashVsHeapTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.{BcVm, TierGate, TierMetrics}
  alias Elmc.Backend.FlashVsHeap.Report
  alias Elmc.TestSupport.TemplateCompile

  @templates ~w(watchface_yes game_2048)
  @compile_opts [
    codegen_profile: :size,
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  for template <- @templates do
    @tag template: template

    test "flash_vs_heap report separates flash and RAM proxies for #{template}" do
      template = unquote(template)
      out_dir = Path.join(System.tmp_dir!(), "flash-vs-heap-#{template}-#{System.unique_integer([:positive])}")
      File.rm_rf!(out_dir)

      assert {:ok, _result} =
               TemplateCompile.compile_watch_template(template, Keyword.merge(@compile_opts, out_dir: out_dir))

      assert File.regular?(Report.report_path(out_dir))

      report =
        out_dir
        |> Report.build(compile_opts: Map.new(@compile_opts))
        |> then(&Jason.encode!/1)
        |> Jason.decode!()

      assert report["contract"] == "elmc.flash_vs_heap.v1"
      assert is_map(report["flash"])
      assert is_map(report["ram"])
      assert report["flash"]["generated_text_bytes"] > 0
      assert report["ram"]["owned_slot_max"] >= 0
      assert report["constraint"] in ["flash_bound", "heap_bound", "balanced"]
      assert is_binary(report["recommendation"])
      assert report["bytecode_vm"]["enabled"] == false

      tier_metrics = TierMetrics.from_out_dir(out_dir)
      assert is_list(tier_metrics.rc_fn_text_sizes)
      refute TierGate.eligible?(tier_metrics)
      refute BcVm.enabled?(Map.put(Map.new(@compile_opts), :bytecode_tier_metrics, tier_metrics))
    end
  end

  test "tier metrics count large RC functions from generated C" do
    source = """
    static RC elmc_fn_Main_small(ElmcValue **out) {
      *out = elmc_int_zero();
      return RC_SUCCESS;
    }
    static RC elmc_fn_Main_large(ElmcValue **out) {
    #{String.duplicate("  (void)out;\n", 80)}
      return RC_SUCCESS;
    }
    """

    sizes = TierMetrics.rc_fn_text_sizes(source)
    assert {"elmc_fn_Main_large", large} = Enum.find(sizes, &match?({"elmc_fn_Main_large", _}, &1))
    assert large > Map.fetch!(TierGate.criteria(), :large_rc_fn_bytes)
  end

  test "flash bound when generated text dominates bin with enough large RC fns" do
    flash = %{"generated_text_share" => 0.5}
    ram = %{"owned_slot_max" => 4, "worker_last_dispatch_cmd_cap" => 0}
    tier = %{eligible: true}

    assert Report.classify_constraint(flash, ram, tier) == :flash_bound
  end

  test "heap bound when owned slots are deep and dispatch cmd cap is on" do
    flash = %{"generated_text_share" => 0.1}
    ram = %{"owned_slot_max" => 24, "worker_last_dispatch_cmd_cap" => 8}
    tier = %{eligible: false}

    assert Report.classify_constraint(flash, ram, tier) == :heap_bound
  end
end
