defmodule Elmc.PlanFixedLengthNilTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Case.ListSwitch
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :slow

  test "polygonLines matches fixed_length_nil_branches?" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_tangram_time",
        plan_ir_mode: :primary,
        plan_ir_strict: false,
        out_dir: Path.expand("tmp/plan_fixed_length_nil", __DIR__)
      )

    branches =
      result
      |> TemplateCompile.decl_map_from_result()
      |> Map.fetch!({"Main", "polygonLines"})
      |> Map.fetch!(:expr)
      |> Map.fetch!(:branches)

    assert ListSwitch.fixed_length_nil_branches?(branches)
  end
end
