defmodule Elmc.YesCurrentDatetimeMinuteFieldTest do
  @moduledoc """
  Regression: after `case model.now of Just now ->`, field `minute` must use
  CurrentDateTime layout (index 5), not TickSpec.minute (index 0 = year).

  Wrong index made MinuteChanged overwrite year → new calendarDayKey → perpetual
  ProvideSun refetch → double-free on the second sun update (YES emery).
  """

  use ExUnit.Case, async: false

  @moduletag :slow

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: false,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  test "watchface_yes MinuteChanged and homeMinuteOfDay use CurrentDateTime.minute" do
    out_dir =
      Path.join(System.tmp_dir!(), "yes-dt-minute-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               "watchface_yes",
               Keyword.put(@compile_opts, :out_dir, out_dir)
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    update_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_update")
    home_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_homeMinuteOfDay")

    # MinuteChanged must update CurrentDateTime.minute (index 5), never
    # TickSpec.minute (index 0 = year). Wrong index freezes the dial and
    # forces a new calendarDayKey → perpetual ProvideSun → double-free.
    assert update_body =~
             ~r/elmc_record_update_index_cow_drop\([^;]+ELMC_FIELD_(?:PEBBLE_TIME_|PKG_APP_PEBBLE_TIME_|PEBBLE_CMD_)CURRENTDATETIME_MINUTE/

    refute update_body =~
             ~r/elmc_record_update_index_cow_drop\([^;]+ELMC_FIELD_YES_RENDER_TICKSPEC_MINUTE/

    assert home_body =~ "ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE" or
             home_body =~ "ELMC_FIELD_PKG_APP_PEBBLE_TIME_CURRENTDATETIME_MINUTE" or
             home_body =~ "ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MINUTE"

    refute home_body =~ "ELMC_FIELD_YES_RENDER_TICKSPEC_MINUTE"

    # record_get borrows; plan owns the dest slot — must retain or epilogue frees
    # model.now / lastSunFetchDayKey while the model still holds them.
    schedule_body =
      CCodegenExtract.fn_body(generated, "elmc_fn_Main_scheduleCompanionFetches")

    assert schedule_body =~
             ~r/elmc_retain\(elmc_record_get_index\([^;]*ELMC_FIELD_MAIN_MODEL_NOW/
  end
end
