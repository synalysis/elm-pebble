defmodule Elmc.OwnedSlotsPoolTest do
  @moduledoc """
  Nested BSS pool for large owned[] frames — no per-call heap churn.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Frame
  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Runtime.Generator
  alias Elmc.Test.RcTrackHarness

  test "codegen frame emits acquire/release for pebble_int32 heap-owned frames" do
    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)
    Process.put(:elmc_codegen_opts, %{pebble_int32: true})

    plan = %FunctionPlan{rc_required: true}
    # 24 slots → above Frame threshold (23)
    slots = Map.new(0..23, fn i -> {i, i} end)

    decl = Frame.owned_declaration(plan, slots)
    assert decl =~ "elmc_owned_slots_acquire(ELMC_OWNED_SLOT_COUNT)"
    assert decl =~ "Rc = RC_ERR_OUT_OF_MEMORY;"
    refute decl =~ "return RC_ERR_OUT_OF_MEMORY"
    refute decl =~ "elmc_calloc"

    epilogue = Frame.epilogue_release(Map.keys(slots), 24)
    assert epilogue =~ "elmc_owned_slots_release(owned, ELMC_OWNED_SLOT_COUNT)"
    refute epilogue =~ "elmc_free(owned)"
  end

  test "runtime pool acquire/release nests without owned_slots heap allocs" do
    tmp = Path.join(System.tmp_dir!(), "owned-slots-pool-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    runtime_dir = Path.join(tmp, "runtime")
    File.mkdir_p!(runtime_dir)

    assert :ok = Generator.write_runtime(runtime_dir, pebble_int32: true)

    runtime_h = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))
    runtime_c = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
    assert runtime_h =~ "elmc_owned_slots_acquire"
    assert runtime_h =~ "ELMC_OWNED_SLOTS_POOL_CAP"
    assert runtime_h =~ "ElmcOwnedSlotsPoolState"
    assert runtime_c =~ "elmc_owned_slots_acquire"
    assert runtime_c =~ "elmc_owned_slots_pool_state"
    refute runtime_c =~ "typedef struct {\n      ElmcValue *frames"

    harness = Path.join(tmp, "owned_slots_pool_harness.c")

    File.write!(harness, """
    #include <stdio.h>
    #include <string.h>
    #include "elmc_runtime.h"

    int main(void) {
    #if ELMC_ALLOC_TRACK
      elmc_alloc_track_reset();
    #endif
      ElmcValue **a = elmc_owned_slots_acquire(80);
      ElmcValue **b = elmc_owned_slots_acquire(40);
      ElmcValue **c = elmc_owned_slots_acquire(16);
      if (!a || !b || !c) return 1;
      if (a == b || b == c) return 2;
      a[0] = elmc_int_zero();
      b[0] = elmc_int_zero();
      c[0] = elmc_int_zero();
      elmc_owned_slots_release(c, 16);
      elmc_owned_slots_release(b, 40);
      elmc_owned_slots_release(a, 80);
    #if ELMC_ALLOC_TRACK
      printf("owned_slots_heap_allocs=%u\\n", elmc_alloc_track_owned_slots_alloc_count());
      if (elmc_alloc_track_owned_slots_alloc_count() != 0) return 3;
      if (elmc_alloc_track_live_count() != 0) return 4;
    #else
      printf("owned_slots_heap_allocs=0\\n");
    #endif
      printf("rc_ok owned_slots_pool\\n");
      return 0;
    }
    """)

    out =
      RcTrackHarness.run_harness!(
        tmp,
        harness,
        "owned_slots_pool",
        sources: [Path.join(runtime_dir, "elmc_runtime.c"), harness],
        alloc_track: true,
        rc_track: false,
        alloc_probe: false
      )

    assert out =~ "owned_slots_heap_allocs=0"
    assert out =~ "rc_ok owned_slots_pool"
  end

  test "pebble compile sizes the BSS pool from generated owned-slot counts" do
    tmp = Path.join(System.tmp_dir!(), "owned-slots-cap-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    prune_dir = Path.join(tmp, "c")
    runtime_dir = Path.join(tmp, "runtime")
    File.mkdir_p!(prune_dir)

    File.write!(Path.join(prune_dir, "elmc_generated.c"), """
    enum { ELMC_OWNED_SLOT_COUNT = 55 };
    ElmcValue **owned = elmc_owned_slots_acquire(ELMC_OWNED_SLOT_COUNT);
    """)

    assert :ok =
             Generator.write_runtime(runtime_dir,
               prune_from_dir: prune_dir,
               pebble_int32: true
             )

    runtime_h = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))
    assert runtime_h =~ "#define ELMC_OWNED_SLOTS_POOL_CAP 55"
    assert runtime_h =~ "#define ELMC_OWNED_SLOTS_POOL_DEPTH 3"
    refute runtime_h =~ "#define ELMC_OWNED_SLOTS_POOL_CAP 128"
  end
end
