defmodule Elmc.GeneratedRcTrackCodegenOptimizationsTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackHarness

  @fixtures [
    {"RcTrackCompareProbe", "fixtures/rc_track_compare_project",
     ~w(probeListEqual probeRecordEqual)},
    {"RcTrackRecordUpdateProbe", "fixtures/rc_track_record_update_project",
     ~w(probeChainedUpdate probeAliasedBase probeDictUpdateAlias)},
    {"RcTrackGridIntProbe", "fixtures/rc_track_grid_int_project",
     ~w(probeGridAccess probeGridUpdate)}
  ]

  for {module_name, fixture_dir, probes} <- @fixtures do
    @tag :rc_track
    @tag :rc_track_codegen_optimizations
    test "#{module_name} probes balance rc registry" do
      module_name = unquote(module_name)
      fixture_dir = unquote(fixture_dir)
      probes = unquote(probes)
      project_dir = Path.expand(fixture_dir, __DIR__)
      out_dir = Path.expand("tmp/#{Macro.underscore(module_name)}", __DIR__)

      File.rm_rf!(out_dir)
      RcTrackHarness.compile!(project_dir, out_dir, entry_module: module_name)

      out =
        RcTrackHarness.run_probe_suite!(
          out_dir,
          module_name,
          Macro.underscore(module_name),
          RcTrackHarness.int_probes(probes)
        )

      RcTrackHarness.assert_balanced!(out)
      assert out =~ "probes=#{length(probes)}"
    end
  end
end
