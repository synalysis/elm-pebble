defmodule Elmc.PebbleShimTest do
  use ExUnit.Case

  test "random generate command dispatches to declared callback" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    project_dir = Path.expand("tmp/random_generate_project", __DIR__)
    out_dir = Path.expand("tmp/random_generate_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/random" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      """
      module Main exposing (init, update)

      import Random

      type Msg
          = RandomGenerated Int

      init flags =
          ( 0, Random.generate RandomGenerated (Random.int 1 2147483647) )

      update msg model =
          case msg of
              RandomGenerated value ->
                  ( value, Cmd.none )
      """
    )

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/random_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 3;
        if (cmd.kind != ELMC_PEBBLE_CMD_RANDOM_GENERATE) return 4;
        if (cmd.p0 != ELMC_PEBBLE_MSG_RANDOMGENERATED) return 8;
        if (elmc_pebble_dispatch_tag_value(&app, cmd.p0, 42) != 0) return 5;
        if (elmc_pebble_model_as_int(&app) != 42) return 6;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 7;
      }
      """
    )

    binary_path = Path.join(out_dir, "random_harness")

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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "storage read string command carries callback target" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/storage_read_string_project", __DIR__)
    out_dir = Path.expand("tmp/storage_read_string_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_storage_read_string_app!(project_dir)

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/storage_read_string_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleCmd cmd = {0};
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 3;
        if (cmd.kind != ELMC_PEBBLE_CMD_STORAGE_READ_STRING) return 4;
        if (cmd.p0 != 2048) return 5;
        if (cmd.p1 != ELMC_PEBBLE_MSG_BESTLOADED) return 6;
        if (elmc_pebble_dispatch_tag_string(&app, cmd.p1, "144") != 0) return 7;
        if (elmc_pebble_model_as_int(&app) != 144) return 8;

        elmc_pebble_deinit(&app);
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "storage_read_string_harness")

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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "scene command stream supports views larger than prior chunk size" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_stream_project", __DIR__)
    out_dir = Path.expand("tmp/scene_stream_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_many_draw_commands_app!(project_dir, 99)

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/scene_stream_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[128];
        if (elmc_pebble_scene_command_count(&app) != 99) return 3;
        if (elmc_pebble_scene_commands_from(&app, cmds, 128, 0) != 99) return 4;
        if (elmc_pebble_scene_commands_from(&app, cmds, 64, 64) != 35) return 5;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 6;
      }
      """
    )

    binary_path = Path.join(out_dir, "scene_stream_harness")

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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "scene dirty rect tracks moved visual command" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_dirty_rect_project", __DIR__)
    out_dir = Path.expand("tmp/scene_dirty_rect_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_moving_rect_app!(project_dir)

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/scene_dirty_rect_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_scene_command_count(&app) != 1) return 3;

        ElmcPebbleRect rect = {0};
        int full = 0;
        if (elmc_pebble_scene_dirty_rect(&app, &rect, &full) < 0) return 4;
        if (!full) return 5;

        if (elmc_pebble_dispatch_int(&app, ELMC_PEBBLE_MSG_MOVE) != 0) return 6;
        if (elmc_pebble_scene_dirty_rect(&app, &rect, &full) < 0) return 7;
        if (full) return 8;
        if (rect.x != 10) return 9;
        if (rect.y != 20) return 10;
        if (rect.w != 18) return 11;
        if (rect.h != 6) return 12;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 13;
      }
      """
    )

    binary_path = Path.join(out_dir, "scene_dirty_rect_harness")

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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "pebble shim decodes appmessage payloads and drives worker loop" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_shim_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_shim", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
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
        for (int i = 0; i < 16; i++) {
          if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 20;
          if (cmd.kind == ELMC_PEBBLE_CMD_NONE) break;
        }
        int64_t subscriptions = elmc_pebble_active_subscriptions(&app);
        if ((subscriptions & ELMC_PEBBLE_SUB_TICK) == 0) return 31;
        if ((subscriptions & ELMC_PEBBLE_SUB_BUTTON_RAW) == 0) return 31;
        if ((subscriptions & ELMC_PEBBLE_SUB_ACCEL_TAP) == 0) return 31;
        if ((subscriptions & ~(ELMC_PEBBLE_SUB_TICK | ELMC_PEBBLE_SUB_BUTTON_RAW | ELMC_PEBBLE_SUB_ACCEL_TAP)) != 0) return 37;

        if (elmc_pebble_tick(&app) != 0) return 3;
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 22;
        if (elmc_pebble_dispatch_appmessage(&app, 0, ELMC_PEBBLE_MSG_INCREMENT) != 0) return 4;
        if (elmc_pebble_dispatch_appmessage(&app, ELMC_PEBBLE_MSG_DECREMENT, 1) != 0) return 5;
        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_UP, 1) != 0) return 6;
        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_UP, 0) != 1) return 38;
        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_BACK, 1) != 1) return 39;
        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_BACK, 0) != 1) return 40;
        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_SELECT, 1) != 0) return 26;
        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_DOWN, 1) != 0) return 7;
        if (elmc_pebble_dispatch_accel_tap(&app, ELMC_PEBBLE_ACCEL_AXIS_X, 1) != 0) return 8;

        ElmcPebbleDrawCmd cmds[32] = {0};
        int cmd_count = elmc_pebble_view_commands(&app, cmds, 32);
        if (cmd_count < 3) return 9;
        printf("view_count=%d\\n", cmd_count);
        printf("view0=%lld:%lld\\n", (long long)cmds[0].kind, (long long)cmds[0].p0);
        printf("view1=%lld:%lld\\n", (long long)cmds[1].kind, (long long)cmds[1].p1);
        printf("view2=%lld:%lld\\n", (long long)cmds[2].kind, (long long)cmds[2].p2);
        printf("model=%lld\\n", (long long)elmc_pebble_model_as_int(&app));

        int second_count = elmc_pebble_view_commands(&app, cmds, 32);
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
    assert String.contains?(run_out, "view0=2:255")
    assert String.contains?(run_out, "model=")

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

  test "generated pebble C compiles cleanly on available host C compilers" do
    compilers = available_c_compilers()
    if compilers == [], do: flunk("no C compiler available for generated C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_portable_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_portable_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_minimal_watchface!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/portable_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[4] = {0};
        if (elmc_pebble_view_commands(&app, cmds, 4) < 1) return 3;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 4;
      }
      """
    )

    Enum.each(compilers, fn {name, cc} ->
      binary_path = Path.join(out_dir, "portable_harness_#{name}")

      {compile_out, compile_code} =
        System.cmd(cc, [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Werror",
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

      assert compile_code == 0, "#{name} failed:\n#{compile_out}"

      {run_out, run_code} = System.cmd(binary_path, [])
      assert run_code == 0, "#{name} harness failed:\n#{run_out}"
    end)
  end

  test "frame subscription interval codegen stays within pebble int range" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_frame_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_frame_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_frame_subscription_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    refute String.contains?(generated, "141733928960")
    assert String.contains?(generated, "elmc_new_int(2170880)")

    harness_path = Path.join(out_dir, "c/frame_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        int64_t subscriptions = elmc_pebble_active_subscriptions(&app);
        if ((subscriptions & ELMC_PEBBLE_SUB_FRAME) == 0) return 3;
        if (((subscriptions >> 16) & 0x7fff) != 33) return 4;
        if (elmc_pebble_dispatch_frame(&app, 33, 33, 1) != 0) return 5;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 6;
      }
      """
    )

    binary_path = Path.join(out_dir, "frame_harness")

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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "direct pebble renderer streams indexed mapped model lists" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_indexed_map_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_indexed_map_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_indexed_map_view!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert String.contains?(generated, "elmc_fn_Main_view_commands_from")
    assert String.contains?(generated, "elmc_fn_Main_cell_commands_append")

    harness_path = Path.join(out_dir, "c/indexed_map_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[2] = {0};
        int first = elmc_pebble_view_commands_from(&app, cmds, 2, 0);
        if (first != 2) return 3;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_CLEAR) return 4;

        int second = elmc_pebble_view_commands_from(&app, cmds, 2, 2);
        if (second != 2) return 5;

        int remaining = elmc_pebble_view_commands_from(&app, cmds, 2, 4);
        if (remaining != 1) return 6;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 7;
      }
      """
    )

    binary_path = Path.join(out_dir, "indexed_map_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror",
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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "native renderer and update handle partial predicates and helper record fields" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_partial_collision_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_partial_collision_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_partial_collision_view!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert String.contains?(generated, "elmc_partial_ref_")
    assert String.contains?(generated, "elmc_apply_extra")

    harness_path = Path.join(out_dir, "c/partial_collision_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      static long field_int(ElmcValue *record, const char *field) {
        ElmcValue *value = elmc_record_get(record, field);
        long out = (long)elmc_as_int(value);
        elmc_release(value);
        return out;
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[8] = {0};
        int count = elmc_pebble_view_commands_from(&app, cmds, 8, 0);
        if (count < 3) return 3;
        if (cmds[2].kind != ELMC_PEBBLE_DRAW_FILL_RECT) return 4;
        if (cmds[2].p0 != 30 || cmds[2].p1 != 10 || cmds[2].p2 != 20 || cmds[2].p3 != 4) return 5;

        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_UP, 1) != 0) return 6;
        if (field_int(app.worker.model, "playerY") != 6) return 7;
        if (field_int(app.worker.model, "velocityY") != -2) return 8;

        for (int i = 0; i < 8; i++) {
          if (elmc_pebble_dispatch_frame(&app, 33, 33 * (i + 1), i + 1) != 0) return 20 + i;
        }

        long y = field_int(app.worker.model, "playerY");
        long vy = field_int(app.worker.model, "velocityY");
        if (y != 6) return 40;
        if (vy != 0) return 41;

        elmc_pebble_deinit(&app);
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "partial_collision_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror",
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
    assert run_code == 0, run_out
  end

  test "generated draw feature flags match primitives used by different views" do
    rich_fixture = Path.expand("fixtures/simple_project", __DIR__)
    rich_project = Path.expand("tmp/pebble_rich_draw_flags_project", __DIR__)
    rich_out = Path.expand("tmp/pebble_rich_draw_flags", __DIR__)
    File.rm_rf!(rich_project)
    File.rm_rf!(rich_out)
    File.cp_r!(rich_fixture, rich_project)

    assert {:ok, _} = Elmc.compile(rich_project, %{out_dir: rich_out, entry_module: "Main"})

    rich_header = File.read!(Path.join(rich_out, "c/elmc_pebble.h"))
    assert draw_feature?(rich_header, "ARC")
    assert draw_feature?(rich_header, "PATH")
    assert draw_feature?(rich_header, "TEXT_LABEL")

    minimal_fixture = Path.expand("fixtures/simple_project", __DIR__)
    minimal_project = Path.expand("tmp/pebble_minimal_draw_flags_project", __DIR__)
    minimal_out = Path.expand("tmp/pebble_minimal_draw_flags", __DIR__)
    File.rm_rf!(minimal_project)
    File.rm_rf!(minimal_out)
    File.cp_r!(minimal_fixture, minimal_project)
    write_minimal_watchface!(minimal_project)

    assert {:ok, _} = Elmc.compile(minimal_project, %{out_dir: minimal_out, entry_module: "Main"})

    minimal_header = File.read!(Path.join(minimal_out, "c/elmc_pebble.h"))
    assert draw_feature?(minimal_header, "CLEAR")
    refute draw_feature?(minimal_header, "ARC")
    refute draw_feature?(minimal_header, "PATH")
    refute draw_feature?(minimal_header, "TEXT_LABEL")
  end

  test "compact retained scene encodes and decodes draw commands" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_compact_scene_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_compact_scene_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/compact_scene_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_ensure_scene(&app) != 0) return 3;
        int count = elmc_pebble_scene_command_count(&app);
        if (count <= 0) return 4;
        if (app.scene.byte_count <= 0) return 5;
        if (app.scene.byte_count >= count * (int)sizeof(ElmcPebbleDrawCmd)) return 6;

        ElmcPebbleDrawCmd cmds[64] = {0};
        int decoded = elmc_pebble_scene_commands_from(&app, cmds, 64, 0);
        if (decoded <= 0) return 7;

        int saw_path = 0;
        int saw_text = 0;
        for (int i = 0; i < decoded; i++) {
          if (cmds[i].kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
              cmds[i].kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
              cmds[i].kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
            saw_path = 1;
          }
          if (cmds[i].kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT ||
              cmds[i].kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT) {
            saw_text = 1;
          }
        }
        if (!saw_path) return 8;
        if (!saw_text) return 9;

        uint64_t hash = app.scene.hash;
        int bytes = app.scene.byte_count;
        if (elmc_pebble_ensure_scene(&app) != 0) return 10;
        if (app.scene.hash != hash || app.scene.byte_count != bytes) return 11;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 12;
      }
      """
    )

    binary_path = Path.join(out_dir, "compact_scene_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror",
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

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "host C renderer emits commands for Yes watchface template" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_template = Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)
    project_dir = Path.expand("tmp/watchface_yes_host_project", __DIR__)
    out_dir = Path.expand("tmp/watchface_yes_host_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_template, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")

    main_path
    |> File.read!()
    |> String.replace("import Companion.Watch as CompanionWatch\n", "")
    |> String.replace("CompanionWatch.sendWatchToPhone RequestUpdate", "Cmd.none")
    |> String.replace("CompanionWatch.onPhoneToWatch FromPhone", "Sub.none")
    |> then(&File.write!(main_path, &1))

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "protocol/src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3", "elm/time" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert String.contains?(generated, "elmc_fn_Main_view_commands_from")

    point_at_body =
      generated
      |> String.split("static ElmcValue *elmc_fn_Main_pointAt_native")
      |> List.last()
      |> String.split("ElmcValue *elmc_fn_Main_", parts: 2)
      |> hd()

    assert point_at_body =~ "native_trig_theta_"
    assert point_at_body =~ "generated_trig_sin_double(native_trig_theta_"
    assert point_at_body =~ "generated_trig_cos_double(native_trig_theta_"
    refute point_at_body =~ "elmc_basics_sin(tmp_"
    refute point_at_body =~ "elmc_basics_cos(tmp_"
    refute point_at_body =~ "elmc_new_float"

    harness_path = Path.join(out_dir, "c/watchface_yes_host_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include "elmc_generated.h"

      static int list_length(ElmcValue *list) {
        int count = 0;
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < 512) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          cursor = node->tail;
          count++;
        }
        return (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload == NULL) ? count : -1;
      }

      static int tuple_tag(ElmcValue *value) {
        if (!value || value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return -1;
        ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
        return (int)elmc_as_int(tuple->first);
      }

      static int first_list_item(ElmcValue *list, ElmcValue **out) {
        if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL || !out) return 0;
        *out = ((ElmcCons *)list->payload)->head;
        return *out != NULL;
      }

      static int expect_yes_ui_node(ElmcValue *view) {
        if (tuple_tag(view) != ELMC_PEBBLE_UI_WINDOW_STACK) return 0;
        ElmcTuple2 *stack = (ElmcTuple2 *)view->payload;
        if (list_length(stack->second) != 1) return 0;

        ElmcValue *window = NULL;
        if (!first_list_item(stack->second, &window)) return 0;
        if (tuple_tag(window) != ELMC_PEBBLE_UI_WINDOW_NODE) return 0;
        ElmcTuple2 *window_tuple = (ElmcTuple2 *)window->payload;
        if (!window_tuple->second || window_tuple->second->tag != ELMC_TAG_TUPLE2) return 0;
        ElmcTuple2 *window_payload = (ElmcTuple2 *)window_tuple->second->payload;
        if (elmc_as_int(window_payload->first) != 1) return 0;
        if (list_length(window_payload->second) != 1) return 0;

        ElmcValue *layer = NULL;
        if (!first_list_item(window_payload->second, &layer)) return 0;
        if (tuple_tag(layer) != ELMC_PEBBLE_UI_CANVAS_LAYER) return 0;
        ElmcTuple2 *layer_tuple = (ElmcTuple2 *)layer->payload;
        if (!layer_tuple->second || layer_tuple->second->tag != ELMC_TAG_TUPLE2) return 0;
        ElmcTuple2 *layer_payload = (ElmcTuple2 *)layer_tuple->second->payload;
        if (elmc_as_int(layer_payload->first) != 1) return 0;
        return list_length(layer_payload->second) > 0;
      }

      static ElmcValue *test_launch_context(void) {
        ElmcValue *screen_width = elmc_new_int(144);
        ElmcValue *screen_height = elmc_new_int(168);
        ElmcValue *screen_is_color = elmc_new_bool(1);
        ElmcValue *screen_is_round = elmc_new_bool(0);
        const char *screen_names[] = {"height", "isColor", "isRound", "width"};
        ElmcValue *screen_values[] = {screen_height, screen_is_color, screen_is_round, screen_width};
        ElmcValue *screen = elmc_record_new(4, screen_names, screen_values);
        elmc_release(screen_width);
        elmc_release(screen_height);
        elmc_release(screen_is_color);
        elmc_release(screen_is_round);

        ElmcValue *reason = elmc_new_int(2);
        ElmcValue *watch_model = elmc_new_string("");
        ElmcValue *watch_profile_id = elmc_new_string("flint");
        const char *context_names[] = {"reason", "screen", "watchModel", "watchProfileId"};
        ElmcValue *context_values[] = {reason, screen, watch_model, watch_profile_id};
        ElmcValue *context = elmc_record_new(4, context_names, context_values);
        elmc_release(reason);
        elmc_release(screen);
        elmc_release(watch_model);
        elmc_release(watch_profile_id);
        return context;
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = test_launch_context();
        if (elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE) != 0) return 2;
        elmc_release(flags);
        if ((int)sizeof(ElmcPebbleDrawCmd) > 112) return 18;

        ElmcValue *model = elmc_worker_model(&app.worker);
        if (!model) return 6;

        ElmcValue *face_args[1] = { model };
        ElmcValue *face_ops = elmc_fn_Main_faceOps(face_args, 1);
        if (!face_ops || face_ops->tag != ELMC_TAG_LIST || list_length(face_ops) <= 0) return 7;

        ElmcValue *view_args[1] = { model };
        ElmcValue *view = elmc_fn_Main_view(view_args, 1);
        if (!expect_yes_ui_node(view)) return 8;

        ElmcValue *dial_args[4] = { model, elmc_new_int(72), elmc_new_int(84), elmc_new_int(64) };
        ElmcValue *dial = elmc_fn_Main_drawDial(dial_args, 4);
        if (!dial || dial->tag != ELMC_TAG_LIST || list_length(dial) <= 0) return 9;
        elmc_release(dial_args[1]);
        elmc_release(dial_args[2]);
        elmc_release(dial_args[3]);

        ElmcValue *point_args[4] = { elmc_new_int(72), elmc_new_int(84), elmc_new_int(64), elmc_new_int(0) };
        ElmcValue *point = elmc_fn_Main_pointAt(point_args, 4);
        if (elmc_record_get_int(point, "x") != 72 || elmc_record_get_int(point, "y") != 20) return 12;
        elmc_release(point);
        elmc_release(point_args[0]);
        elmc_release(point_args[1]);
        elmc_release(point_args[2]);
        elmc_release(point_args[3]);

        ElmcValue *corner_args[1] = { model };
        ElmcValue *corners = elmc_fn_Main_drawCorners(corner_args, 1);
        if (!corners || corners->tag != ELMC_TAG_LIST || list_length(corners) < 0) return 10;

        ElmcValue *to_ui_args[1] = { face_ops };
        ElmcValue *manual_view = elmc_fn_Pebble_Ui_toUiNode(to_ui_args, 1);
        if (!expect_yes_ui_node(manual_view)) return 11;

        elmc_release(manual_view);
        elmc_release(corners);
        elmc_release(dial);
        elmc_release(view);
        elmc_release(face_ops);
        elmc_release(model);

        int count = elmc_pebble_scene_command_count(&app);
        if (count <= 0) return 3;

        ElmcPebbleDrawCmd cmds[16] = {0};
        int decoded = elmc_pebble_scene_commands_from(&app, cmds, 16, 0);
        if (decoded <= 0) return 4;
        if (app.scene.byte_count <= 0) return 19;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_CLEAR) return 5;
        if (cmds[0].p0 != 0xC0) return 13;
        if (decoded < 2) return 14;
        if (cmds[1].kind != ELMC_PEBBLE_DRAW_FILL_CIRCLE) return 15;
        if (cmds[1].p0 != 72 || cmds[1].p1 != 84 || cmds[1].p2 != 64) return 16;
        if (cmds[1].p3 != 0xC1) return 17;

        elmc_pebble_deinit(&app);
        return 0;
      }
      """
    )

    for {variant, extra_flags} <- [{"host64", []}, {"pebble_int32", ["-DELMC_PEBBLE_INT32"]}] do
      binary_path = Path.join(out_dir, "watchface_yes_host_harness_#{variant}")

      {compile_out, compile_code} =
        System.cmd(cc, [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Werror"
          | extra_flags ++
              [
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
              ]
        ])

      assert compile_code == 0, "#{variant} compile failed:\n#{compile_out}"

      {run_out, run_code} = System.cmd(binary_path, [])
      assert run_code == 0, "#{variant} run failed:\n#{run_out}"
    end
  end

  test "generated feature flags include Pebble.Light commands" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_light_feature_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_light_feature_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_light_command_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_BACKLIGHT 1")
  end

  test "unreachable Pebble declarations do not enable generated functions or features" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_unreachable_feature_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_unreachable_feature_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_unreachable_feature_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert draw_feature?(header, "CLEAR")
    refute draw_feature?(header, "ARC")
    refute String.contains?(generated, "elmc_fn_Main_unusedArc")
  end

  test "direct view helper references enable draw runtime features" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_direct_helper_feature_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_direct_helper_feature_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_direct_helper_feature_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert draw_feature?(header, "RECT")
    assert draw_feature?(header, "STROKE_COLOR")
    assert draw_feature?(header, "TEXT_COLOR")
    assert String.contains?(generated, "elmc_fn_Main_drawCell_commands_append")
  end

  test "fillRadial references enable radial draw runtime feature" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_fill_radial_feature_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_fill_radial_feature_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_fill_radial_feature_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    assert draw_feature?(header, "FILL_RADIAL")
  end

  defp available_c_compilers do
    ["cc", "gcc", "clang"]
    |> Enum.map(fn name -> {name, System.find_executable(name)} end)
    |> Enum.filter(fn {_name, path} -> is_binary(path) end)
    |> Enum.uniq_by(fn {_name, path} -> path end)
  end

  defp draw_feature?(header, suffix) do
    String.contains?(header, "#define ELMC_PEBBLE_FEATURE_DRAW_#{suffix} 1")
  end

  defp write_direct_helper_feature_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Button as Button
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


    type Msg
        = UpPressed


    init _ =
        ( { cells = [ 0, 2 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Button.onPress Button.Up UpPressed


    view model =
        Ui.toUiNode (List.indexedMap drawCell model.cells)


    drawCell : Int -> Int -> Ui.RenderOp
    drawCell index value =
        let
            x =
                10 + index * 31

            label =
                if value == 0 then
                    "."

                else
                    String.fromInt value
        in
        Ui.group
            (Ui.context
                [ Ui.strokeColor Color.black
                , Ui.textColor Color.black
                ]
                [ Ui.rect { x = x, y = 42, w = 28, h = 28 } Color.black
                , Ui.text Resources.DefaultFont { x = x + 2, y = 47, w = 24, h = 18 } label
                ]
            )


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }
    """)
  end

  defp write_fill_radial_feature_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.windowStack
            [ Ui.window 1
                [ Ui.canvasLayer 1
                    [ Ui.group
                        (Ui.context
                            [ Ui.fillColor Color.chromeYellow ]
                            [ Ui.fillRadial { x = 8, y = 8, w = 96, h = 96 } 0 32768 ]
                        )
                    ]
                ]
            ]
    """)
  end

  defp write_minimal_watchface!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { value : Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init launchContext =
        ( { value = Platform.launchReasonToInt launchContext.reason }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.windowStack
            [ Ui.window 1
                [ Ui.canvasLayer 1
                    [ Ui.clear Color.white ]
                ]
            ]
    """)
  end

  defp write_unreachable_feature_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { value : Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { value = 0 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.windowStack
            [ Ui.window 1
                [ Ui.canvasLayer 1
                    [ Ui.clear Color.white ]
                ]
            ]


    unusedArc =
        Ui.arc { x = 0, y = 0, w = 20, h = 20 } 0 180
    """)
  end

  defp write_indexed_map_view!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { cells = [ 0, 2, 4, 8 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            ([ Ui.clear Color.white ]
                ++ List.indexedMap cell model.cells
            )


    cell : Int -> Int -> Ui.RenderOp
    cell index value =
        Ui.textInt Resources.DefaultFont { x = index * 8, y = 0 } value
    """)
  end

  defp write_partial_collision_view!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Button as Button
    import Pebble.Events as Events
    import Pebble.Frame as Frame
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Tile =
        { x : Int, y : Int }

    type alias Model =
        { playerY : Int
        , velocityY : Int
        , offset : Int
        , tiles : List Tile
        }

    type Msg
        = FrameTick Frame.Frame
        | UpPressed

    init _ =
        ( { playerY = 6
          , velocityY = 0
          , offset = 0
          , tiles = [ { x = 30, y = 10 } ]
          }
        , Cmd.none
        )

    update msg model =
        case msg of
            FrameTick _ ->
                step model

            UpPressed ->
                ( { model | velocityY = -2 }, Cmd.none )

    step model =
        let
            nextOffset =
                model.offset + 1

            nextY =
                model.playerY + model.velocityY

            playerBottom =
                nextY + 4

            landingTile =
                if model.velocityY >= 0 then
                    List.filter (landedOnTile nextOffset (model.playerY + 4) playerBottom) model.tiles
                        |> List.head

                else
                    Nothing

            fixedY =
                case landingTile of
                    Just tile ->
                        (tileRect nextOffset tile).y - 4

                    Nothing ->
                        nextY
        in
        ( { model
            | offset = nextOffset
            , playerY = fixedY
            , velocityY =
                if landingTile /= Nothing then
                    0

                else
                    min 3 (model.velocityY + 1)
          }
        , Cmd.none
        )

    landedOnTile offset previousBottom playerBottom tile =
        let
            rect =
                tileRect offset tile
        in
        previousBottom <= rect.y && playerBottom >= rect.y

    tileRect offset tile =
        { x = tile.x - offset, y = tile.y, w = 20, h = 4 }

    subscriptions _ =
        Events.batch
            [ Frame.every 33 FrameTick
            , Button.onPress Button.Up UpPressed
            ]

    view model =
        Ui.toUiNode
            ([ Ui.clear Color.white
             , Ui.fillRect { x = 4, y = model.playerY, w = 4, h = 4 } Color.black
             ]
                ++ List.map (drawTile model.offset) model.tiles
            )

    drawTile offset tile =
        Ui.fillRect (tileRect offset tile) Color.black

    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """)
  end

  defp write_frame_subscription_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Events as Events
    import Pebble.Frame as Frame
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { frame : Int }


    type Msg
        = FrameTick Frame.Frame


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { frame = 0 }, Cmd.none )


    update msg model =
        case msg of
            FrameTick frame ->
                ( { model | frame = frame.frame }, Cmd.none )


    subscriptions _ =
        Events.batch [ Frame.every 33 FrameTick ]


    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]
    """)
  end

  defp write_light_command_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Light as Light
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        {}


    type Msg
        = NoOp


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Light.enable )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]
    """)
  end

  defp write_storage_read_string_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Storage as Storage
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Msg
        = BestLoaded String


    main : Program Decode.Value Int Msg
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( 0, Storage.readString 2048 BestLoaded )


    update msg _ =
        case msg of
            BestLoaded value ->
                ( Maybe.withDefault 0 (String.toInt value), Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode [ Ui.clear Color.white ]
    """)
  end

  defp write_many_draw_commands_app!(project_dir, count) do
    commands =
      0..(count - 1)
      |> Enum.map_join("\n            , ", fn index ->
        x = rem(index * 7, 140)
        y = rem(index * 5, 160)
        "Ui.fillRect { x = #{x}, y = #{y}, w = 2, h = 2 } Color.black"
      end)

    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Msg
        = NoOp


    main : Program Decode.Value Int Msg
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( 0, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            [ #{commands}
            ]
    """)
  end

  defp write_moving_rect_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type Msg
        = Move


    main : Program Decode.Value Int Msg
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( 0, Cmd.none )


    update msg model =
        case msg of
            Move ->
                ( model + 10, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            [ Ui.fillRect { x = 10 + model, y = 20, w = 8, h = 6 } Color.black
            ]
    """)
  end
end
