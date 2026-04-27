defmodule Elmc.PebbleShimTest do
  use ExUnit.Case

  test "pebble shim decodes appmessage payloads and drives worker loop" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_shim", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/pebble_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>
      #include <stdbool.h>

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 20;
        if (elmc_pebble_active_subscriptions(&app) != 31) return 31;

        if (elmc_pebble_tick(&app) != 0) return 3;
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 22;
        if (cmd.kind != ELMC_PEBBLE_CMD_TIMER_AFTER_MS || cmd.p0 != 1000) return 23;
        if (elmc_pebble_dispatch_appmessage(&app, 0, ELMC_PEBBLE_MSG_INCREMENT) != 0) return 4;
        if (elmc_pebble_dispatch_appmessage(&app, ELMC_PEBBLE_MSG_DECREMENT, 1) != 0) return 5;
        if (elmc_pebble_dispatch_button(&app, ELMC_PEBBLE_BUTTON_UP) != 0) return 6;
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 24;
        if (cmd.kind != ELMC_PEBBLE_CMD_STORAGE_WRITE_INT || cmd.p0 != 1 || cmd.p1 != 4) return 25;
        if (elmc_pebble_dispatch_button(&app, ELMC_PEBBLE_BUTTON_SELECT) != 0) return 26;
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 27;
        if (elmc_pebble_dispatch_button(&app, ELMC_PEBBLE_BUTTON_DOWN) != 0) return 7;
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 29;
        if (cmd.kind != ELMC_PEBBLE_CMD_STORAGE_DELETE || cmd.p0 != 1) return 30;
        if (elmc_pebble_dispatch_accel_tap(&app, ELMC_PEBBLE_ACCEL_AXIS_X, 1) != 0) return 8;

        ElmcPebbleDrawCmd cmds[8] = {0};
        int cmd_count = elmc_pebble_view_commands(&app, cmds, 8);
        if (cmd_count < 3) return 9;
        printf("view_count=%d\\n", cmd_count);
        printf("view0=%lld:%lld\\n", (long long)cmds[0].kind, (long long)cmds[0].p0);
        printf("view1=%lld:%lld\\n", (long long)cmds[1].kind, (long long)cmds[1].p1);
        printf("view2=%lld:%lld\\n", (long long)cmds[2].kind, (long long)cmds[2].p2);
        printf("model=%lld\\n", (long long)elmc_pebble_model_as_int(&app));

        int second_count = elmc_pebble_view_commands(&app, cmds, 8);
        if (second_count != 0) return 32;

        ElmcPebbleApp watchface_app = {0};
        ElmcValue *watchface_flags = elmc_new_int(0);
        if (elmc_pebble_init_with_mode(&watchface_app, watchface_flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 33;
        elmc_release(watchface_flags);
        if (elmc_pebble_run_mode(&watchface_app) != ELMC_PEBBLE_MODE_WATCHFACE) return 34;
        if (elmc_pebble_dispatch_button(&watchface_app, ELMC_PEBBLE_BUTTON_UP) != -9) return 35;
        if (elmc_pebble_dispatch_accel_tap(&watchface_app, ELMC_PEBBLE_ACCEL_AXIS_X, 1) != -9) return 36;
        elmc_pebble_deinit(&watchface_app);
        elmc_pebble_deinit(&app);

        printf("%llu %llu\\n",
               (unsigned long long)elmc_rc_allocated_count(),
               (unsigned long long)elmc_rc_released_count());
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "pebble_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        "-I#{Path.join(out_dir, "ports")}",
        "-I#{Path.join(out_dir, "c")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        Path.join(out_dir, "ports/elmc_ports.c"),
        Path.join(out_dir, "c/elmc_generated.c"),
        Path.join(out_dir, "c/elmc_worker.c"),
        Path.join(out_dir, "c/elmc_pebble.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
    assert String.contains?(run_out, "view_count=")
    assert String.contains?(run_out, "view0=2:0")
    assert String.contains?(run_out, "model=4")

    view_count =
      run_out
      |> String.split("\n", trim: true)
      |> Enum.find(&String.starts_with?(&1, "view_count="))
      |> String.replace("view_count=", "")
      |> String.to_integer()

    assert view_count >= 6

    [alloc, rel] =
      run_out
      |> String.split("\n", trim: true)
      |> List.last()
      |> String.split(" ")

    assert String.to_integer(alloc) > 0
    assert String.to_integer(alloc) == String.to_integer(rel)
  end
end
