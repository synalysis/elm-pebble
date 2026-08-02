defmodule Elmc.TemplateTeaScenarioSmokeTest do
  @moduledoc """
  Host TEA scenario smoke: scripted init/update/view with scene + SDK spy asserts.

  Run one template per BEAM via `./scripts/mix-test-per-template.sh
  test/template_tea_scenario_smoke_test.exs`.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.{HostSmoke, TeaScenario, TeaScenarioHarness, TemplateCompile}

  @moduletag :slow
  @moduletag :tea_scenario

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

    test "TEA scenario host smoke: #{template}" do
      run_tea_scenario_smoke!(unquote(template))
    end
  end

  defp run_tea_scenario_smoke!(template) do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for template TEA scenario smoke")

    out_dir = Path.join(System.tmp_dir!(), "tea-scenario-#{template}-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    compile_opts = Keyword.merge(@compile_opts, out_dir: out_dir)
    assert {:ok, _result} = TemplateCompile.compile_watch_template(template, compile_opts)

    header_path = Path.join(out_dir, "c/elmc_pebble.h")
    scenario = TeaScenario.for_template(template, pebble_header_path: header_path)

    harness_path = Path.join(out_dir, "c/tea_scenario_harness.c")
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

    binary_name = "tea_scenario_#{template}"

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        binary_name,
        sources: RcTrackHarness.pebble_harness_sources(out_dir, harness_path, extra_sources),
        extra_flags: extra_flags,
        rc_track: false,
        alloc_track: false
      )

    assert out =~ "rc_ok tea_scenario #{template}"
    refute out =~ "placeholder_time=1"
  end
end
