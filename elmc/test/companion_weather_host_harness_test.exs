defmodule Elmc.CompanionWeatherHostHarnessTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  alias Elmc.Test.RcTrackHarness

  @fixture_dir Path.expand("fixtures/companion_weather_worker", __DIR__)
  @reading_fixture_dir Path.expand("fixtures/companion_reading_worker", __DIR__)

  @compile_opts [
    direct_render_only: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true,
    strip_dead_code: true,
    plan_ir_mode: :primary,
    plan_ir_strict: true
  ]

  test "companion ProvideReading dispatch updates view text without RC leak" do
    run_companion_weather_harness!(
      @fixture_dir,
      "companion_weather_host",
      "ELMC_PEBBLE_MSG_PROBEREADING",
      220,
      "22C"
    )
  end

  test "companion Fahrenheit reading renders in view" do
    run_companion_weather_harness!(
      @fixture_dir,
      "companion_weather_fahrenheit_host",
      "ELMC_PEBBLE_MSG_PROBEREADINGF",
      715,
      "72F"
    )
  end

  test "renamed Scale/ProvideReading fixture renders companion reading in view" do
    run_companion_weather_harness!(
      @reading_fixture_dir,
      "companion_reading_host",
      "ELMC_PEBBLE_MSG_PROBEREADING",
      175,
      "18C"
    )
  end

  @tag :slow
  test "80 companion reading updates keep RC balanced through view refresh" do
    run_companion_weather_flood!(@fixture_dir, "companion_weather_flood", 80)
  end

  defp run_companion_weather_harness!(project_dir, binary_name, msg_tag, wire_value, expected_text) do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for companion weather host harness")

    out_dir = Path.expand("tmp/#{binary_name}_codegen", __DIR__)
    File.rm_rf!(out_dir)
    RcTrackHarness.compile!(project_dir, out_dir, Keyword.merge(@compile_opts, entry_module: "Main"))

    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")

    File.write!(
      harness_path,
      companion_weather_harness_c(msg_tag, wire_value, expected_text)
    )

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        binary_name,
        sources: pebble_harness_sources(out_dir, harness_path),
        rc_track: false,
        alloc_track: false
      )

    assert out =~ "rc_ok companion weather view"
    RcTrackHarness.assert_balanced!(out)
  end

  defp run_companion_weather_flood!(project_dir, binary_name, iterations) do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for companion weather flood harness")

    out_dir = Path.expand("tmp/#{binary_name}_codegen", __DIR__)
    File.rm_rf!(out_dir)
    RcTrackHarness.compile!(project_dir, out_dir, Keyword.merge(@compile_opts, entry_module: "Main"))

    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
    File.write!(harness_path, companion_weather_flood_harness_c(iterations))

    out =
      RcTrackHarness.run_harness!(
        out_dir,
        harness_path,
        binary_name,
        sources: pebble_harness_sources(out_dir, harness_path),
        rc_track: false,
        alloc_track: false
      )

    assert out =~ "rc_ok companion weather flood"
    RcTrackHarness.assert_balanced!(out)
  end

  defp pebble_harness_sources(out_dir, harness_path) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_worker.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      harness_path
    ]
  end

  defp companion_weather_harness_c(msg_tag, wire_value, expected_text) do
    """
    #include <string.h>
    #include "elmc_pebble.h"

    static int scene_text_contains(const ElmcPebbleDrawCmd *cmds, int count, const char *needle) {
      for (int i = 0; i < count; i++) {
        if (cmds[i].text[0] == '\\0') continue;
        if (strncmp(cmds[i].text, needle, sizeof(cmds[i].text)) == 0) return 1;
      }
      return 0;
    }

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = elmc_new_int_take(0);
      if (elmc_pebble_init(&app, flags) != 0) return 2;
      elmc_release(flags);

      if (elmc_pebble_dispatch_tag_value(&app, #{msg_tag}, #{wire_value}) != 0) return 3;

      ElmcPebbleDrawCmd cmds[8] = {0};
      int count = elmc_pebble_view_commands(&app, cmds, 8);
      if (count < 1) return 4;
      if (!scene_text_contains(cmds, count, "#{expected_text}")) return 5;

      elmc_pebble_deinit(&app);
      printf("rc_ok companion weather view\\n");
      return 0;
    }
    """
  end

  defp companion_weather_flood_harness_c(iterations) do
    """
    #include "elmc_pebble.h"

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = elmc_new_int_take(0);
      if (elmc_pebble_init(&app, flags) != 0) return 2;
      elmc_release(flags);

      for (int i = 0; i < #{iterations}; i++) {
        if (elmc_pebble_dispatch_tag_value(&app, ELMC_PEBBLE_MSG_PROBEREADING, 200 + i) != 0) {
          return 10 + i;
        }

        if ((i % 8) == 7) {
          ElmcPebbleDrawCmd cmds[4] = {0};
          if (elmc_pebble_view_commands(&app, cmds, 4) < 1) return 200 + i;
        }
      }

      elmc_pebble_deinit(&app);
      printf("rc_ok companion weather flood\\n");
      return 0;
    }
    """
  end
end
