defmodule Elmc.PlanCowDropBorrowParamRetainTest do
  @moduledoc """
  In-place `elmc_record_update_index_cow_drop` on a borrowed function param must
  retain into the owned dest slot.

  Without that retain, epilogue LIFO releases the aliased param and frees the
  caller's model while the returned `(Model, Cmd)` tuple still points at it
  (YES: second CurrentDateTime → scheduleCompanionFetches → Invalid free).
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

  test "watchface_yes scheduleCompanionFetches retains after cow_drop of model param" do
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

    assert body =~ ~r/elmc_record_update_index_cow_drop\([^;]+,\s*model\s*,/

    assert body =~ ~r/
      elmc_record_update_index_cow_drop\([^;]+,\s*model\s*,[\s\S]*?
      if\s*\(\s*owned\[\d+\]\s*==\s*model\s*\)\s*\{\s*
      \s*owned\[\d+\]\s*=\s*elmc_retain\(owned\[\d+\]\)
    /x
  end
end
