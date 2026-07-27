defmodule Elmc.GeneratedRcTrackStressTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.Test.RcTrackMatrix

  @iterations 100

  for {module_name, fixture_dir, probe_name} <- RcTrackMatrix.stress_probes() do
    @tag :rc_track
    @tag :rc_track_stress
    test "stress #{module_name}.#{probe_name} balances rc registry over 100 iterations" do
      module_name = unquote(module_name)
      fixture_dir = unquote(fixture_dir)
      probe_name = unquote(probe_name)
      binary_name = "rc_stress_#{Macro.underscore(module_name)}_#{Macro.underscore(probe_name)}"

      out =
        RcTrackHarness.run_stress_core_probe!(
          __DIR__,
          fixture_dir,
          module_name,
          probe_name,
          binary_name,
          @iterations
        )

      RcTrackHarness.assert_balanced!(out)
      assert out =~ "iterations=#{@iterations}"
    end
  end
end
