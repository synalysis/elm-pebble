defmodule Elmc.PlanCowDropBorrowParamRetainTest do
  @moduledoc """
  `elmc_record_update_index_cow_drop` on a borrowed function param must not
  release the caller's model.

  Copy-path `*_cow_drop` releases `record`. Passing a borrowed param directly
  frees the caller's value (YES: scheduleCompanionFetches → 2nd MinuteChanged).
  Codegen retains into `__cow_base` first so only that credit is dropped.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  test "watchface_yes scheduleCompanionFetches retains borrowed model before cow_drop" do
    out_dir =
      Path.join(System.tmp_dir!(), "cow-borrow-retain-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               "watchface_yes",
               Keyword.put(@compile_opts, :out_dir, out_dir)
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_scheduleCompanionFetches")

    refute body =~ ~r/elmc_record_update_index_cow_drop\([^;]+,\s*model\s*,/

    assert body =~ ~r/
      ElmcValue\s*\*__cow_base\s*=\s*elmc_retain\(model\);\s*
      Rc\s*=\s*elmc_record_update_index_cow_drop\([^;]+,\s*__cow_base\s*,
    /x
  end
end
