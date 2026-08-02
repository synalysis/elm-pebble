defmodule Elmc.TeaScenarioValgrindSmokeTest do
  @moduledoc """
  Valgrind TEA host smoke across enabled playbook templates.

  Catches take/borrow dispatch mismatches and in-place cow_drop-on-param
  retain bugs that host glibc/`elmc_release` often hide while Pebble
  `process_heap` faults.

  Tagged `:slow` / `:valgrind`; excluded from default `mix test`.
  Run one template per BEAM via:

      ./scripts/mix-test-per-template.sh test/tea_scenario_valgrind_smoke_test.exs
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.{HostSmoke, TeaScenario, TeaScenarioHarness, TemplateCompile}

  @moduletag :slow
  @moduletag :valgrind

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  @templates HostSmoke.templates(TeaScenario.enabled_names())

  for template <- @templates do
    @tag template: template

    test "TEA playbook has no Invalid free under valgrind: #{template}" do
      run_valgrind_smoke!(unquote(template))
    end
  end

  defp run_valgrind_smoke!(template) do
    if is_nil(System.find_executable("valgrind")), do: flunk("valgrind not available")
    if is_nil(System.find_executable("cc")), do: flunk("cc not available")

    out_dir =
      Path.join(System.tmp_dir!(), "tea-valgrind-#{template}-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               template,
               Keyword.put(@compile_opts, :out_dir, out_dir)
             )

    header_path = Path.join(out_dir, "c/elmc_pebble.h")
    scenario = TeaScenario.for_template(template, pebble_header_path: header_path)

    harness_path = Path.join(out_dir, "c/tea_valgrind_harness.c")
    File.write!(harness_path, TeaScenarioHarness.emit(template, scenario, header_path))

    extra_sources = []
    extra_flags = []

    {extra_sources, extra_flags} =
      if scenario[:needs_trig?] do
        RcTrackHarness.write_trig_stubs!(out_dir)

        {extra_sources ++ [Path.join(out_dir, "c/pebble_trig_host_stubs.c")],
         extra_flags ++ ["-include", Path.join(out_dir, "c/pebble_trig_host_stubs.h")]}
      else
        {extra_sources, extra_flags}
      end

    binary_name = "tea_valgrind_#{template}"

    {out, code} =
      RcTrackHarness.run_harness_capture(
        out_dir,
        harness_path,
        binary_name,
        sources: RcTrackHarness.pebble_harness_sources(out_dir, harness_path, extra_sources),
        extra_flags: extra_flags,
        rc_track: false,
        alloc_track: false,
        valgrind: true
      )

    assert out =~ "rc_ok tea_scenario #{template}", "harness output:\n#{out}"
    RcTrackHarness.assert_no_invalid_free!(out)
    assert code == 0, "valgrind exit #{code}:\n#{out}"
  end
end
