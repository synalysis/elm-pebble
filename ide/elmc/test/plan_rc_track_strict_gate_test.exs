defmodule Elmc.PlanRcTrackStrictGateTest do
  @moduledoc """
  Gate: rc_track elm/core probe fixtures compile under plan_ir_strict.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackMatrix

  @moduletag :plan_surface
  @moduletag :slow

  for {_core, %{module: module, fixture: fixture}} <- RcTrackMatrix.registry() do
    fixture_rel = Path.basename(fixture)
    @tag fixture: fixture_rel

    test "strict plan-primary compiles #{module} rc_track fixture",
         %{fixture: fixture_rel} do
      root = Path.expand("fixtures/#{fixture_rel}", __DIR__)
      out_dir = Path.expand("tmp/plan_rc_strict/#{fixture_rel}", __DIR__)

      assert {:ok, result} =
               Elmc.compile(root, %{
                 out_dir: out_dir,
                 entry_module: "Main",
                 strip_dead_code: false,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true
               })

      fallbacks =
        (result.layout_coercion_diagnostics || [])
        |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))

      assert fallbacks == [],
             "expected zero plan_primary_fallback in #{fixture_rel}: #{inspect(Enum.take(fallbacks, 3))}"

      c_path = Path.join(out_dir, "c/elmc_generated.c")

      if File.regular?(c_path) do
        unknown_count =
          c_path
          |> File.read!()
          |> then(&Regex.scan(~r/elmc_unknown\b/, &1))
          |> length()

        assert unknown_count == 0,
               "expected zero elmc_unknown in #{fixture_rel}, got #{unknown_count}"
      end
    end
  end
end
