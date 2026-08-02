defmodule Elmc.TeaScenarioValgrindSmokeTest do
  @moduledoc """
  Valgrind TEA host smoke for watchface_yes.

  Catches take/borrow dispatch mismatches and in-place cow_drop-on-param
  retain bugs that host glibc/`elmc_release` often hide while Pebble
  `process_heap` faults.

  Tagged `:slow` / `:valgrind`; excluded from default `mix test`.
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.{TeaScenario, TeaScenarioHarness, TemplateCompile}

  @moduletag :slow
  @moduletag :valgrind

  @template "watchface_yes"

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true
  ]

  test "watchface_yes TEA playbook has no Invalid free under valgrind" do
    if is_nil(System.find_executable("valgrind")), do: flunk("valgrind not available")
    if is_nil(System.find_executable("cc")), do: flunk("cc not available")

    out_dir =
      Path.join(System.tmp_dir!(), "tea-valgrind-#{@template}-#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template(
               @template,
               Keyword.put(@compile_opts, :out_dir, out_dir)
             )

    header_path = Path.join(out_dir, "c/elmc_pebble.h")
    scenario = TeaScenario.for_template(@template, pebble_header_path: header_path)

    assert Enum.any?(scenario.steps, &match?({:drain_cmds, _}, &1)),
           "playbook must drain cmds (datetime path)"

    assert Enum.any?(scenario.steps, &match?({:dispatch_clock, _}, &1)) or
             Enum.any?(scenario.steps, &match?({:from_phone, _}, &1)),
           "playbook must include clock update and/or boxed FromPhone"

    harness_path = Path.join(out_dir, "c/tea_valgrind_harness.c")
    File.write!(harness_path, TeaScenarioHarness.emit(@template, scenario, header_path))
    RcTrackHarness.write_trig_stubs!(out_dir)

    binary_name = "tea_valgrind_#{@template}"

    {out, code} =
      RcTrackHarness.run_harness_capture(
        out_dir,
        harness_path,
        binary_name,
        sources:
          RcTrackHarness.pebble_harness_sources(out_dir, harness_path, [
            Path.join(out_dir, "c/pebble_trig_host_stubs.c")
          ]),
        extra_flags: ["-include", Path.join(out_dir, "c/pebble_trig_host_stubs.h")],
        rc_track: false,
        alloc_track: false,
        valgrind: true
      )

    assert out =~ "rc_ok tea_scenario #{@template}", "harness output:\n#{out}"
    RcTrackHarness.assert_no_invalid_free!(out)
    assert code == 0, "valgrind exit #{code}:\n#{out}"
  end
end
