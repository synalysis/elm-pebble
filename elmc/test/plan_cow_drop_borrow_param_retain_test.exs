defmodule Elmc.PlanCowDropBorrowParamRetainTest do
  @moduledoc """
  Record updates on a borrowed function param must not release the caller's model.

  Copy-path `*_cow_drop` releases `record`. Passing a borrowed param directly
  frees the caller's value. Emit uses `*_cow` on borrowed params and retains
  only when the dest aliases the base after an in-place update (YES:
  `updateFromPhone` Provide* branches).
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

  test "watchface_yes updateFromPhone uses cow on borrowed model param" do
    out_dir =
      Path.join(System.tmp_dir!(), "cow-borrow-retain-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               "watchface_yes",
               Keyword.put(@compile_opts, :out_dir, out_dir)
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_updateFromPhone")

    refute body =~ ~r/elmc_record_update_index_cow_drop\([^;]+,\s*model\s*,/

    assert body =~ ~r/
      Rc\s*=\s*elmc_record_update_index_cow\(&owned\[\d+\],\s*model\s*,
    /x

    assert body =~ ~r/
      if\s*\(owned\[\d+\]\s*==\s*model\)\s*\{\s*
        owned\[\d+\]\s*=\s*elmc_retain\(owned\[\d+\]\);
    /x
  end
end
