defmodule Elmc.BinarySizeRoadmapTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Bytecode.{BcVm, ProjectWriter, TierGate, TierMetrics}
  alias Elmc.Backend.CCodegen.{ObjectTextEstimate, SchemaRegistry}
  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.FlashVsHeap.Report
  alias Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Compact
  alias Elmc.Runtime.Generator, as: RuntimeGenerator

  test "runtime prune does not seed list-array helpers without references" do
    tmp = Path.join(System.tmp_dir!(), "runtime-prune-seed-#{System.unique_integer([:positive])}")

    try do
      runtime_dir = Path.join(tmp, "runtime")
      c_dir = Path.join(tmp, "c")
      File.mkdir_p!(runtime_dir)
      File.mkdir_p!(c_dir)

      File.write!(Path.join(c_dir, "minimal.c"), """
      #include "elmc_runtime.h"
      void runtime_prune_seed_probe(void) {
        (void)elmc_new_int_take(0);
      }
      """)

      assert :ok =
               RuntimeGenerator.write_runtime(runtime_dir,
                 prune_from_dir: tmp,
                 pebble_int32: true
               )

      source = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
      refute source =~ "RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count)"
    after
      File.rm_rf(tmp)
    end
  end

  test "inactive compass float feature does not keep soft-float coercions" do
    tmp = Path.join(System.tmp_dir!(), "runtime-prune-float-#{System.unique_integer([:positive])}")

    try do
      runtime_dir = Path.join(tmp, "runtime")
      c_dir = Path.join(tmp, "c")
      File.mkdir_p!(runtime_dir)
      File.mkdir_p!(c_dir)

      File.write!(Path.join(c_dir, "elmc_pebble.h"), """
      #define ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK 0
      """)

      File.write!(Path.join(c_dir, "app.c"), """
      #include "elmc_runtime.h"
      #include "elmc_pebble.h"
      void app_tick(void) {
        (void)elmc_new_int_take(1);
        (void)elmc_as_int_number(NULL);
      }
      #if ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK
      void compass_dead(void) {
        (void)elmc_new_float(NULL, 1.0);
        (void)elmc_as_float(NULL);
      }
      #endif
      """)

      assert :ok =
               RuntimeGenerator.write_runtime(runtime_dir,
                 prune_from_dir: tmp,
                 pebble_int32: true
               )

      source = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
      header = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))
      refute source =~ ~r/double elmc_as_float\(/
      refute source =~ "ELMC_TAG_FLOAT) return (elmc_int_t)elmc_as_float"
      assert source =~ "elmc_int_t elmc_as_int_number"
      refute header =~ ~r/^double elmc_as_float\(/m
    after
      File.rm_rf(tmp)
    end
  end

  test "object text estimate includes runtime/elmc_runtime.c path" do
    paths = ObjectTextEstimate.app_source_paths("/tmp/out")
    assert Enum.any?(paths, &String.ends_with?(&1, "runtime/elmc_runtime.c"))
  end

  test "size profile compact draw allows circle primitives in subset" do
    flags =
      %{
        draw_clear: true,
        draw_text: true,
        draw_circle: true,
        draw_fill_circle: false,
        draw_fill_rect: true,
        draw_rect: false,
        draw_pixel: false,
        draw_line: false,
        draw_round_rect: false,
        draw_arc: false,
        draw_path: false,
        draw_fill_radial: false,
        draw_bitmap_in_rect: false,
        draw_vector_at: false,
        draw_vector_sequence_at: false,
        draw_bitmap_sequence_at: false,
        draw_rotated_bitmap: false,
        draw_context: false,
        draw_stroke_width: false,
        draw_antialiased: false,
        draw_stroke_color: false,
        draw_fill_color: false,
        draw_text_color: false,
        draw_compositing_mode: false,
        draw_text_int: false,
        draw_text_label: false,
        draw_text_any: true,
        compact_draw: false
      }

    assert Compact.compute(flags, %{codegen_profile: :size, size_prune_capabilities: true}).compact_draw
  end

  test "bytecode tier gate defers until generated text dominates bin" do
    refute TierGate.eligible?(%{
             generated_text_bytes: 10_000,
             pebble_app_bin_bytes: 65_000,
             rc_fn_text_sizes: []
           })

    assert TierGate.eligible?(%{
             generated_text_bytes: 30_000,
             pebble_app_bin_bytes: 65_000,
             rc_fn_text_sizes: for(i <- 1..10, do: {"fn_#{i}", 500})
           })
  end

  test "selective pebble bytecode stays off without tier metrics" do
    refute ProjectWriter.selective_pebble_bytecode?(%{emit_bytecode: false, bytecode_tier_metrics: %{}})
  end

  test "tier metrics derive RC function sizes from generated C" do
    tmp = Path.join(System.tmp_dir!(), "tier-metrics-#{System.unique_integer([:positive])}")

    try do
      c_dir = Path.join(tmp, "c")
      File.mkdir_p!(c_dir)

      File.write!(Path.join(c_dir, "elmc_generated.c"), """
      static RC elmc_fn_Main_big(ElmcValue **out) {
      #{String.duplicate("  (void)out;\n", 80)}
        return RC_SUCCESS;
      }
      """)

      metrics = TierMetrics.from_out_dir(tmp)
      assert length(metrics.rc_fn_text_sizes) == 1
      refute TierGate.eligible?(metrics)
    after
      File.rm_rf(tmp)
    end
  end

  test "bc vm stays disabled until tier gate and explicit opt-in" do
    metrics = %{
      generated_text_bytes: 30_000,
      pebble_app_bin_bytes: 65_000,
      rc_fn_text_sizes: for(i <- 1..10, do: {"fn_#{i}", 500})
    }

    refute BcVm.enabled?(%{bytecode_tier_metrics: metrics})
    refute BcVm.enabled?(%{bc_vm_enabled: true, bytecode_tier_metrics: %{}, emit_bytecode: true})

    assert BcVm.enabled?(%{
             bc_vm_enabled: true,
             emit_bytecode: true,
             bytecode_tier_metrics: metrics
           })

    assert BcVm.enabled?(%{
             bc_vm_enabled: true,
             emit_bytecode: false,
             bytecode_tier_metrics: metrics
           })
  end

  test "flash vs heap report classifies bytecode vm as deferred" do
    tmp = Path.join(System.tmp_dir!(), "flash-report-#{System.unique_integer([:positive])}")

    try do
      c_dir = Path.join(tmp, "c")
      File.mkdir_p!(c_dir)
      File.write!(Path.join(c_dir, "elmc_generated.c"), "static RC elmc_fn_Main_x(ElmcValue **out){return RC_SUCCESS;}")
      File.write!(Path.join(tmp, "elmc_stack_report.json"), ~s({"code_size_indicators":{"owned_slot_max":4}}))

      report = Report.build(tmp, compile_opts: %{codegen_profile: :size, pebble_int32: true})
      assert report["bytecode_vm"]["enabled"] == false
      assert report["ram"]["worker_last_dispatch_cmd_cap"] == 0
    after
      File.rm_rf(tmp)
    end
  end

  test "schema registry marks optional-native flattenable records" do
    registry =
      SchemaRegistry.build_from_field_types(%{
        {"Main", "Grid"} => %{"x" => "Int", "y" => "Maybe Int"}
      })

    assert SchemaRegistry.flattenable?(registry, "Main", "Grid")
    refute SchemaRegistry.all_native?(registry, "Main", "Grid")
  end

  test "storage plan exposes maybe int unboxed layout" do
    plan = StoragePlan.maybe_int_unboxed()
    assert StoragePlan.maybe_int_unboxed?(plan)
    refute StoragePlan.maybe_int_unboxed?(StoragePlan.scalar_unboxed(:int))
  end

  test "size profile zeros last-dispatch cmd cap for RAM" do
    alias Elmc.Backend.Plan.Worker.Host.Lower, as: HostLower

    assert HostLower.last_dispatch_cmd_cap_for_test(%{codegen_profile: :size}) == 0
    assert HostLower.last_dispatch_cmd_cap_for_test(%{}) == 8
  end
end
