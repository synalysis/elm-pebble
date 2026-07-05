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
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
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
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
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
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "streamed fallback scene build advances past first draw command" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_stream_fallback_project", __DIR__)
    out_dir = Path.expand("tmp/scene_stream_fallback_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_non_direct_multi_command_view_app!(project_dir)

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    refute File.read!(Path.join(out_dir, "c/elmc_pebble.h")) =~
             "ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW"

    harness_path = Path.join(out_dir, "c/scene_stream_fallback_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_scene_command_count(&app) != 4) return 3;

        ElmcPebbleDrawCmd cmds[8];
        if (elmc_pebble_scene_commands_from(&app, cmds, 8, 0) != 4) return 4;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_CLEAR) return 5;
        if (cmds[1].kind != ELMC_PEBBLE_DRAW_FILL_RECT) return 6;
        if (cmds[2].kind != ELMC_PEBBLE_DRAW_FILL_RECT) return 7;
        if (cmds[3].kind != ELMC_PEBBLE_DRAW_FILL_RECT) return 8;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 9;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "scene_stream_fallback_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "scene draw cursor advances without re-decoding from byte zero" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_cursor_project", __DIR__)
    out_dir = Path.expand("tmp/scene_cursor_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_many_draw_commands_app!(project_dir, 99)

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/scene_cursor_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_scene_command_count(&app) != 99) return 3;

        ElmcPebbleDrawCmd cmds[64];
        elmc_pebble_scene_reset_draw_cursor(&app);
        if (elmc_pebble_scene_commands_next(&app, cmds, 64) != 64) return 4;
        if (app.scene_draw_byte_offset <= 0) return 5;
        if (elmc_pebble_scene_commands_next(&app, cmds, 64) != 35) return 6;
        if (app.scene_draw_byte_offset != app.scene.byte_count) return 7;
        if (elmc_pebble_scene_commands_next(&app, cmds, 64) != 0) return 8;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 9;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "scene_cursor_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "scene command stream resumes mid-cell when chunk splits rect and text" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_grid_chunk_project", __DIR__)
    out_dir = Path.expand("tmp/scene_grid_chunk_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_grid_scene_app!(project_dir)

    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/scene_grid_chunk_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[64];
        const int total = elmc_pebble_scene_command_count(&app);
        if (total != 38) return 3;
        if (elmc_pebble_scene_commands_from(&app, cmds, 32, 0) != 32) return 4;
        if (elmc_pebble_scene_commands_from(&app, cmds, 8, 32) != 6) return 5;
        if (elmc_pebble_scene_commands_from(&app, cmds, 1, 32) != 1) return 6;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_TEXT) return 7;
        if (cmds[0].text[0] == '\\0') return 8;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 9;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "scene_grid_chunk_harness")

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
        "-lm",
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
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "direct renderer substitutes helper arguments inside record field access" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_record_field_substitution_project", __DIR__)
    out_dir = Path.expand("tmp/direct_record_field_substitution_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_midpoint_view_app!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    harness_path = Path.join(out_dir, "c/direct_record_field_substitution_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[4] = {0};
        if (elmc_pebble_scene_commands_from(&app, cmds, 4, 0) != 1) return 3;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_LINE) return 4;
        if (cmds[0].p0 != 5 || cmds[0].p1 != 0) return 5;
        if (cmds[0].p2 != 0 || cmds[0].p3 != 5) return 6;

        elmc_pebble_deinit(&app);
        return 0;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "direct_record_field_substitution_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "direct renderer encodes clear, round rect, and model text in one scene" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/digital_watchface_scene_project", __DIR__)
    out_dir = Path.expand("tmp/digital_watchface_scene_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_digital_watchface_scene_app!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true,
               pebble_int32: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "static ElmcPebbleDrawCmd scene_cmd;"

    harness_path = Path.join(out_dir, "c/digital_watchface_scene_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_scene_command_count(&app) != 3) return 3;

        ElmcPebbleDrawCmd cmds[4] = {0};
        if (elmc_pebble_scene_commands_next(&app, cmds, 4) != 3) return 4;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_CLEAR) return 5;
        if (cmds[1].kind != ELMC_PEBBLE_DRAW_ROUND_RECT) return 6;
        if (cmds[2].kind != ELMC_PEBBLE_DRAW_TEXT) return 7;
        if (cmds[2].text[0] != '-' || cmds[2].text[1] != '-') return 8;

        elmc_pebble_deinit(&app);
        return 0;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "digital_watchface_scene_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "scene draw cursor splits three clears text and round rect across chunk boundary" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/digital_watch_chunk_boundary_project", __DIR__)
    out_dir = Path.expand("tmp/digital_watch_chunk_boundary_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_digital_watch_multi_clear_scene_app!(project_dir, 3)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true,
               pebble_int32: true
             })

    harness_path = Path.join(out_dir, "c/digital_watch_chunk_boundary_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_scene_command_count(&app) != 5) return 3;

        ElmcPebbleDrawCmd chunk[4] = {0};
        elmc_pebble_scene_reset_draw_cursor(&app);
        if (elmc_pebble_scene_commands_next(&app, chunk, 4) != 4) return 4;
        if (chunk[0].kind != ELMC_PEBBLE_DRAW_CLEAR) return 5;
        if (chunk[3].kind != ELMC_PEBBLE_DRAW_TEXT) return 6;
        if (chunk[3].text[0] != '-' || chunk[3].text[1] != '-') return 7;

        app.scene.dirty = 1;
        if (elmc_pebble_scene_commands_next(&app, chunk, 4) != 1) return 8;
        if (chunk[0].kind != ELMC_PEBBLE_DRAW_ROUND_RECT) return 9;
        if (app.scene_draw_byte_offset != app.scene.byte_count) return 10;

        elmc_pebble_deinit(&app);
        return 0;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "digital_watch_chunk_boundary_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "direct renderer preserves centered text options through record updates" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_text_options_project", __DIR__)
    out_dir = Path.expand("tmp/direct_text_options_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_centered_text_view_app!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "#define ELMC_RENDER_OP_TEXT 29"
    assert generated_c =~ "#define ELMC_TEXT_ALIGN_CENTER 1"
    assert generated_c =~ "#define ELMC_TEXT_OVERFLOW_WORD_WRAP 0"

    assert generated_c =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT);"

    assert generated_c =~
             "ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT))"

    harness_path = Path.join(out_dir, "c/direct_text_options_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[2] = {0};
        if (elmc_pebble_scene_commands_from(&app, cmds, 2, 0) != 1) return 3;
        if (cmds[0].kind != ELMC_PEBBLE_DRAW_TEXT) return 4;
        if (cmds[0].p1 != 10 || cmds[0].p2 != 20 || cmds[0].p3 != 30 || cmds[0].p4 != 18) return 5;
        if (cmds[0].p5 != 1) return 6;

        elmc_pebble_deinit(&app);
        return 0;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "direct_text_options_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "chunked context groups preserve nested text commands" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/context_group_text_project", __DIR__)
    out_dir = Path.expand("tmp/context_group_text_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_context_group_text_view_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/context_group_text_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd chunk[1] = {0};
        int saw_text = 0;
        for (int skip = 0; skip < 16; skip++) {
          chunk[0].kind = ELMC_PEBBLE_DRAW_NONE;
          int count = elmc_pebble_view_commands_from(&app, chunk, 1, skip);
          if (count < 0) return 3;
          if (count == 0) break;
          if (chunk[0].kind == ELMC_PEBBLE_DRAW_TEXT) {
            saw_text = 1;
            if (chunk[0].p1 != 10 || chunk[0].p2 != 20 || chunk[0].p3 != 80 || chunk[0].p4 != 18) return 4;
            if (chunk[0].text[0] != 'H' || chunk[0].text[1] != 'i') return 5;
          }
        }

        if (!saw_text) return 6;
        elmc_pebble_deinit(&app);
        return 0;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "context_group_text_harness")

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
        "-lm",
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
        ElmcValue *flags = elmc_new_int_take(0);
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
        if (second_count != cmd_count) return 32;

        ElmcPebbleApp watchface_app = {0};
        ElmcValue *watchface_flags = elmc_new_int_take(0);
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
        "-lm",
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
    assert abs(String.to_integer(alloc) - String.to_integer(rel)) <= 16
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
        ElmcValue *flags = elmc_new_int_take(0);
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
          "-lm",
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

    assert String.contains?(
             generated,
             "elmc_sub1((ELMC_SUBSCRIPTION_FRAME_BASE + (33 << 16)), ELMC_PEBBLE_MSG_FRAMETICK)"
           )

    harness_path = Path.join(out_dir, "c/frame_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
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
    assert String.contains?(generated, "elmc_fn_Main_view_scene_append")
    assert String.contains?(generated, "elmc_fn_Main_view_commands_append")
    refute String.contains?(generated, "elmc_direct_commands_from")
    assert String.contains?(generated, "direct_index_")
    refute String.contains?(generated, "elmc_fn_Main_cell_commands_append")

    harness_path = Path.join(out_dir, "c/indexed_map_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
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
    assert String.contains?(generated, "elmc_apply_extra(")

    harness_path = Path.join(out_dir, "c/partial_collision_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include "elmc_generated.h"

      enum {
        MODEL_FIELD_PLAYERY = 0,
        MODEL_FIELD_VELOCITYY = 1
      };

      static long field_int(ElmcValue *record, int index) {
        return (long)ELMC_RECORD_GET_INDEX_INT(record, index);
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[8] = {0};
        int count = elmc_pebble_view_commands_from(&app, cmds, 8, 0);
        if (count < 3) return 3;
        if (cmds[2].kind != ELMC_PEBBLE_DRAW_FILL_RECT) return 4;
        if (cmds[2].p0 != 30 || cmds[2].p1 != 10 || cmds[2].p2 != 20 || cmds[2].p3 != 4) return 5;

        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_UP, 1) != 0) return 6;
        if (field_int(app.worker.model, MODEL_FIELD_PLAYERY) != 6) return 7;
        if (field_int(app.worker.model, MODEL_FIELD_VELOCITYY) != -2) return 8;

        for (int i = 0; i < 8; i++) {
          if (elmc_pebble_dispatch_frame(&app, 33, 33 * (i + 1), i + 1) != 0) return 20 + i;
        }

        long y = field_int(app.worker.model, MODEL_FIELD_PLAYERY);
        long vy = field_int(app.worker.model, MODEL_FIELD_VELOCITYY);
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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0, run_out
  end

  test "game jump-n-run template survives repeated frame dispatch without heap corruption" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    repo_root = Path.expand("../..", __DIR__)

    source_template =
      Path.join(repo_root, "ide/priv/project_templates/game_jump_n_run")

    project_dir = Path.expand("tmp/game_jump_n_run_project", __DIR__)
    out_dir = Path.expand("tmp/game_jump_n_run_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp_r!(Path.join(source_template, "src"), Path.join(project_dir, "src"))

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          Path.join(repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
          Path.join(repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
          Path.join(repo_root, "ide/priv/internal_packages/elm-time/src"),
          Path.join(repo_root, "ide/priv/internal_packages/elm-random/src")
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{
            "elm/core" => "1.0.5",
            "elm/json" => "1.1.3",
            "elm/time" => "1.0.0",
            "elm/random" => "1.0.0"
          },
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert String.contains?(generated, "elmc_fn_Main_landedOnTile_native")

    harness_path = Path.join(out_dir, "c/game_jump_n_run_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        for (int i = 0; i < 30; i++) {
          if (elmc_pebble_dispatch_frame(&app, 33, 33 * (i + 1), i + 1) != 0) return 20 + i;
        }

        elmc_pebble_deinit(&app);
        return 0;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "game_jump_n_run_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0, run_out
  end

  test "drawing showcase Paths page survives Down button without crashing" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_template =
      Path.expand("../../ide/priv/project_templates/watch_demo_drawing_showcase", __DIR__)

    project_dir = Path.expand("tmp/drawing_paths_project", __DIR__)
    out_dir = Path.expand("tmp/drawing_paths_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    harness_path = Path.join(out_dir, "c/drawing_paths_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *launch_context(void) {
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *color_mode = elmc_new_int_take(1);
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, width, shape};
        ElmcValue *screen = elmc_record_new_take_value(4, screen_names, screen_values);
        ElmcValue *reason = elmc_new_int_take(1);
        const char *names[] = {"reason", "screen"};
        ElmcValue *values[] = {reason, screen};
        ElmcValue *__ret = elmc_record_new_take_value(2, names, values);
        return __ret;
      }

      static int count_draw_kind(const ElmcPebbleDrawCmd *cmds, int count, int32_t kind) {
        int found = 0;
        for (int i = 0; i < count; i++) {
          if (cmds[i].kind == kind) found++;
        }
        return found;
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = launch_context();
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[64] = {0};
        int initial_count = elmc_pebble_view_commands(&app, cmds, 64);
        if (initial_count < 1) return 3;

        if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_DOWN, 1) != 0) return 4;

        int path_count = elmc_pebble_view_commands(&app, cmds, 64);
        if (path_count < 3) return 5;

        int path_ops =
          count_draw_kind(cmds, path_count, ELMC_PEBBLE_DRAW_PATH_FILLED) +
          count_draw_kind(cmds, path_count, ELMC_PEBBLE_DRAW_PATH_OUTLINE) +
          count_draw_kind(cmds, path_count, ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN);
        if (path_ops < 2) return 6;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 7;
      }
      
      
      
      """
    )

    rotation_harness_path = Path.join(out_dir, "c/drawing_bitmap_rotation_harness.c")

    File.write!(
      rotation_harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *launch_context(void) {
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *color_mode = elmc_new_int_take(1);
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, width, shape};
        ElmcValue *screen = elmc_record_new_take_value(4, screen_names, screen_values);
        ElmcValue *reason = elmc_new_int_take(1);
        const char *names[] = {"reason", "screen"};
        ElmcValue *values[] = {reason, screen};
        ElmcValue *__ret = elmc_record_new_take_value(2, names, values);
        return __ret;
      }

      static int64_t rotated_bitmap_angle(const ElmcPebbleDrawCmd *cmds, int count) {
        for (int i = 0; i < count; i++) {
          if (cmds[i].kind == ELMC_PEBBLE_DRAW_ROTATED_BITMAP) {
            return cmds[i].p3;
          }
        }
        return -1;
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = launch_context();
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        for (int i = 0; i < 3; i++) {
          if (elmc_pebble_dispatch_button_raw(&app, ELMC_PEBBLE_BUTTON_DOWN, 1) != 0) return 3;
        }

        if (elmc_pebble_dispatch_frame(&app, 33, 33, 1) != 0) return 4;

        ElmcPebbleDrawCmd cmds[64] = {0};
        int count = elmc_pebble_view_commands(&app, cmds, 64);
        int64_t angle = rotated_bitmap_angle(cmds, count);
        if (angle != 4096) return 5;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 6;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "drawing_paths_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0, run_out

    rotation_binary_path = Path.join(out_dir, "drawing_bitmap_rotation_harness")

    {rotation_compile_out, rotation_compile_code} =
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
        rotation_harness_path,
        "-lm",
        "-o",
        rotation_binary_path
      ])

    assert rotation_compile_code == 0, rotation_compile_out

    {rotation_run_out, rotation_run_code} =
      System.cmd(rotation_binary_path, [], stderr_to_stdout: true)

    assert rotation_run_code == 0, rotation_run_out
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
        ElmcValue *flags = elmc_new_int_take(0);
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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "scene rebuild is lazy until ensure_scene after invalidation" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_dispatch_dirty_project", __DIR__)
    out_dir = Path.expand("tmp/scene_dispatch_dirty_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_grid_scene_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/scene_dispatch_dirty_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (!app.scene.dirty) return 3;
        if (elmc_pebble_ensure_scene(&app) != 0) return 4;
        if (app.scene.command_count != 38) return 5;
        int bytes = app.scene.byte_count;
        if (bytes <= 0) return 6;

        elmc_pebble_invalidate_scene(&app);
        if (!app.scene.dirty) return 7;

        if (elmc_pebble_ensure_scene(&app) != 0) return 8;
        if (app.scene.command_count != 38) return 9;
        if (app.scene.byte_count != bytes) return 10;

        ElmcPebbleDrawCmd cmds[64];
        if (elmc_pebble_scene_commands_from(&app, cmds, 64, 0) != 38) return 11;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 12;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "scene_dispatch_dirty_harness")

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
        "-lm",
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {_run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
  end

  test "dirty scene rebuilds via ensure_scene when commands_next runs" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/scene_dirty_direct_project", __DIR__)
    out_dir = Path.expand("tmp/scene_dirty_direct_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_grid_scene_app!(project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    harness_path = Path.join(out_dir, "c/scene_dirty_direct_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = elmc_new_int_take(0);
        if (elmc_pebble_init(&app, flags) != 0) return 2;
        elmc_release(flags);

        if (elmc_pebble_ensure_scene(&app) != 0) return 3;
        if (app.scene.byte_count <= 0) return 4;

        elmc_pebble_invalidate_scene(&app);
        if (!app.scene.dirty) return 5;

        if (elmc_pebble_ensure_scene(&app) != 0) return 6;

        ElmcPebbleDrawCmd cmds[64];
        elmc_pebble_scene_reset_draw_cursor(&app);
        if (elmc_pebble_scene_commands_next(&app, cmds, 64) != 38) return 7;
        if (app.scene.byte_count <= 0) return 8;
        if (app.scene.dirty) return 9;

        elmc_pebble_deinit(&app);
        return elmc_rc_allocated_count() == elmc_rc_released_count() ? 0 : 10;
      }
      
      
      
      """
    )

    binary_path = Path.join(out_dir, "scene_dirty_direct_harness")

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
        "-lm",
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
    |> String.replace("CompanionWatch.sendWatchToPhone RequestSunData", "Cmd.none")
    |> String.replace("CompanionWatch.sendWatchToPhone RequestWeather", "Cmd.none")
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
    assert String.contains?(generated, "static RC elmc_fn_Yes_Render_pointAt_native")

    point_at_body = Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Yes_Render_pointAt_native")

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
      #include "elmc_generated.c"

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

      static ElmcValue *test_launch_context(void) {
        ElmcValue *screen_width = elmc_new_int_take(144);
        ElmcValue *screen_height = elmc_new_int_take(168);
        ElmcValue *screen_shape = elmc_new_int_take(1);
        ElmcValue *screen_color_mode = elmc_new_int_take(2);
        ElmcValue *screen_values[] = {screen_width, screen_height, screen_shape, screen_color_mode};
        ElmcValue *screen = elmc_record_new_values_take_value(4, screen_values);
        ElmcValue *reason = elmc_new_int_take(2);
        ElmcValue *watch_model = elmc_new_string_take("");
        ElmcValue *watch_profile_id = elmc_new_string_take("flint");
        ElmcValue *has_microphone = elmc_new_bool_take(1);
        ElmcValue *has_compass = elmc_new_bool_take(0);
        ElmcValue *supports_health = elmc_new_bool_take(1);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        ElmcValue *context = NULL;
        if (elmc_record_new_values(&context, 7, context_values) != RC_SUCCESS) return NULL;
        elmc_release(reason);
        elmc_release(screen);
        elmc_release(watch_model);
        elmc_release(watch_profile_id);
        elmc_release(has_microphone);
        elmc_release(has_compass);
        elmc_release(supports_health);
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
        ElmcValue *face_ops = NULL;
        if (elmc_fn_Main_faceOps(&face_ops, face_args, 1) != RC_SUCCESS) return 7;
        if (!face_ops || face_ops->tag != ELMC_TAG_LIST || list_length(face_ops) <= 0) return 7;

        ElmcValue *point = NULL;
        if (elmc_fn_Yes_Render_pointAt_native(&point, 72, 84, 32, 0) != RC_SUCCESS) return 11;
        ElmcValue *point_x = elmc_record_get_index(point, 0);
        ElmcValue *point_y = elmc_record_get_index(point, 1);
        if (!point_x || !point_y || elmc_as_int(point_x) != 72 || elmc_as_int(point_y) != 52) return 12;
        elmc_release(point_x);
        elmc_release(point_y);
        elmc_release(point);

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
        if (cmds[1].p0 != 72 || cmds[1].p1 != 84 || cmds[1].p2 != 50) return 16;
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
                Path.join(out_dir, "c/elmc_worker.c"),
                Path.join(out_dir, "c/elmc_pebble.c"),
                harness_path,
                "-lm",
                "-o",
                binary_path
              ]
        ])

      assert compile_code == 0, "#{variant} compile failed:\n#{compile_out}"

      {run_out, run_code} = System.cmd(binary_path, [])
      assert run_code == 0, "#{variant} run failed:\n#{run_out}"
    end
  end

  test "yes watchface disables direct view scene when stack analysis marks render helpers risky" do
    source_template = Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)
    project_dir = Path.expand("tmp/watchface_yes_stack_project", __DIR__)
    out_dir = Path.expand("tmp/watchface_yes_stack_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_template, project_dir)

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

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               pebble_int32: true,
               strip_dead_code: true
             })

    pebble_h = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    pebble_c = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute pebble_h =~ "ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE"
    assert pebble_c =~
             "#if defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW) && \\\n        (defined(ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE) || !defined(ELMC_PEBBLE_PLATFORM))"
    assert pebble_c =~ "#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)"
    assert pebble_c =~
             "#elif defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW) && !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)"
    assert pebble_c =~ "BUILD_CHUNK_GUARD"
    assert generated =~ "elmc_fn_Main_view_commands_append"
    assert pebble_c =~ "#define ELMC_PEBBLE_APPEND_FALLBACK_SCENE 1"
    refute generated =~ "elmc_fn_Main_faceOps("
    refute generated =~ "RC elmc_fn_Main_view("
    assert generated =~ "elmc_malloc(ELMC_OWNED_SLOT_COUNT * sizeof(ElmcValue *)"

    report = File.read!(Path.join(out_dir, "elmc_stack_report.json")) |> Jason.decode!()

    assert Enum.any?(report["functions"], fn entry ->
             entry["function"] == "Yes.Render.drawDial" and entry["level"] == "risk"
           end)

    assert generated =~ "elmc_fn_Yes_Render_drawDial_commands_append"
    refute generated =~ "elmc_fn_Yes_Render_sunsetAngle(NULL"
    refute generated =~ "elmc_fn_Yes_Render_sunWindow(NULL"
    refute generated =~ "enum { ELMC_OWNED_SLOT_COUNT = 56 }"
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

  test "apps without compass features do not emit compass float dispatch" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_no_compass_float_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_no_compass_float_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_direct_helper_feature_app!(project_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true,
               pebble_int32: true
             })

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    pebble_c = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))
    runtime_c = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_COMPASS_EVENTS 0")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK 0")
    refute String.contains?(pebble_c, "elmc_pebble_dispatch_compass_heading")
    refute String.contains?(pebble_c, "elmc_new_float")
    refute String.contains?(runtime_c, "elmc_new_float")
    refute String.contains?(runtime_c, "elmc_as_float")
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
    assert String.contains?(generated, "elmc_fn_Main_view_commands_append")
    assert String.contains?(generated, "ELMC_RENDER_OP_RECT")
    refute String.contains?(generated, "elmc_fn_Main_drawCell_commands_append")
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

  test "accel config from Pebble.Accel.onData emits compile-time sampling defines" do
    source_fixture = Path.expand("fixtures/pebble_surface_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_accel_config_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_accel_config_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    assert String.contains?(header, "#define ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE 2")
    assert String.contains?(header, "#define ELMC_PEBBLE_ACCEL_SAMPLING_HZ 100")
  end

  test "tier 1 watch APIs enable generated command and subscription feature flags" do
    source_fixture = Path.expand("fixtures/pebble_surface_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_tier1_feature_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_tier1_feature_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))

    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_INT32 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_COMPASS_PEEK 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_CMD_DICTATION_START 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_APP_FOCUS_EVENTS 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_COMPASS_EVENTS 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_FEATURE_DICTATION_EVENTS 1")
    assert String.contains?(header, "#define ELMC_PEBBLE_SUB_APP_FOCUS (1 << 19)")
    assert String.contains?(header, "#define ELMC_PEBBLE_SUB_COMPASS (1 << 20)")
    assert String.contains?(header, "#define ELMC_PEBBLE_SUB_DICTATION (1 << 21)")
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
                , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x + 2, y = 47, w = 24, h = 18 } label
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

  defp write_grid_scene_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


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
        ( { cells = List.repeat 16 2 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                { x = 10, y = 26, cell = 28, gap = 3 }
        in
        Ui.clear Color.white
            :: (Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 4, w = 132, h = 16 } "2048"
                    :: List.indexedMap (drawCell layout) model.cells
               )
            |> Ui.toUiNode


    drawCell : { x : Int, y : Int, cell : Int, gap : Int } -> Int -> Int -> Ui.RenderOp
    drawCell layout index value =
        let
            x =
                layout.x + modBy 4 index * (layout.cell + layout.gap)

            y =
                layout.y + (index // 4) * (layout.cell + layout.gap)

            label =
                if value == 0 then
                    "."

                else
                    String.fromInt value

            textY =
                y + ((layout.cell - 18) // 2)
        in
        Ui.context
            [ Ui.strokeColor Color.black
            , Ui.textColor Color.black
            ]
            [ Ui.rect { x = x, y = y, w = layout.cell, h = layout.cell } Color.black
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = textY, w = layout.cell, h = 18 } label
            ]
            |> Ui.group
    
    """)
  end

  defp write_non_direct_multi_command_view_app!(project_dir) do
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
        ( 3, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode <|
            Ui.clear Color.white
                :: List.map
                    (\\_ -> Ui.fillRect { x = 4, y = 4, w = 8, h = 8 } Color.black)
                    (List.repeat model 3)
    
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

  defp write_midpoint_view_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Point =
        { x : Int, y : Int }


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
        let
            a =
                { x = 0, y = 0 }

            b =
                { x = 10, y = 0 }

            c =
                { x = 0, y = 10 }
        in
        Ui.toUiNode
            [ Ui.line (midpoint a b) (midpoint a c) Color.black
            ]


    midpoint : Point -> Point -> Point
    midpoint a b =
        { x = (a.x + b.x) // 2
        , y = (a.y + b.y) // 2
        }
    
    """)
  end

  defp write_digital_watch_multi_clear_scene_app!(project_dir, clear_count)
       when is_integer(clear_count) and clear_count >= 1 and clear_count <= 4 do
    colors =
      case clear_count do
        1 -> ["Color.white"]
        2 -> ["Color.white", "Color.yellow"]
        3 -> ["Color.white", "Color.yellow", "Color.red"]
        4 -> ["Color.white", "Color.yellow", "Color.red", "Color.blue"]
      end

    clear_lines =
      colors
      |> Enum.map(fn color -> "            , Ui.clear #{color}" end)
      |> Enum.join("\n")
      |> String.replace_prefix("            , ", "            ")

    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { timeString : String
        , screenW : Int
        , screenH : Int
        }


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
        ( { timeString = "--:--", screenW = 144, screenH = 168 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            cardW =
                (model.screenW * 17) // 20

            cardH =
                max 66 ((model.screenH * 70) // 168)

            cardX =
                (model.screenW - cardW) // 2

            cardY =
                (model.screenH - cardH) // 2

            cornerRadius =
                max 6 (min cardW cardH // 8)

            timeH =
                min 52 (cardH - 8)

            textY =
                cardY + ((cardH - timeH) // 2)
        in
        Ui.toUiNode
            [ #{clear_lines}
            , Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = cardX, y = textY, w = cardW, h = timeH } model.timeString
            , Ui.roundRect { x = cardX, y = cardY, w = cardW, h = cardH } cornerRadius Color.black
            ]
    
    """)
  end

  defp write_digital_watchface_scene_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { timeString : String
        , screenW : Int
        , screenH : Int
        }


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
        ( { timeString = "--:--", screenW = 144, screenH = 168 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            cardW =
                (model.screenW * 17) // 20

            cardH =
                max 66 ((model.screenH * 70) // 168)

            cardX =
                (model.screenW - cardW) // 2

            cardY =
                (model.screenH - cardH) // 2

            cornerRadius =
                max 6 (min cardW cardH // 8)

            timeH =
                min 52 (cardH - 8)

            textY =
                cardY + ((cardH - timeH) // 2)
        in
        Ui.toUiNode
            [ Ui.clear Color.white
            , Ui.roundRect { x = cardX, y = cardY, w = cardW, h = cardH } cornerRadius Color.black
            , Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = cardX, y = textY, w = cardW, h = timeH } model.timeString
            ]
    
    """)
  end

  defp write_centered_text_view_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources


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
            [ Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = 10, y = 20, w = 30, h = 18 } "2"
            ]
    
    """)
  end

  defp write_context_group_text_view_app!(project_dir) do
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


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


    label =
        Ui.group
            (Ui.context
                [ Ui.textColor Color.black ]
                [ Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = 10, y = 20, w = 80, h = 18 } "Hi" ]
            )


    view _ =
        Ui.toUiNode
            [ Ui.clear Color.white
            , label
            ]
    
    """)
  end

  test "elmc_pebble.c includes elmc_pebble.h after heap log build flags" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_heap_log_include_order_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(source_fixture, %{out_dir: out_dir, entry_module: "Main"})

    pebble_c = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))

    {heap_log_pos, _} = :binary.match(pebble_c, "#ifndef ELMC_PEBBLE_HEAP_LOG")
    {header_pos, _} = :binary.match(pebble_c, "#include \"elmc_pebble.h\"")

    assert heap_log_pos < header_pos,
           "elmc_pebble.h must be included after ELMC_PEBBLE_HEAP_LOG defaults"

    assert String.contains?(pebble_c, "void elmc_pebble_render_diag_log(")
  end

  test "worker marks render only when dispatch changes model or cmd" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/dispatch_needs_render_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(source_fixture, %{out_dir: out_dir, entry_module: "Main"})

    worker_c = File.read!(Path.join(out_dir, "c/elmc_worker.c"))
    pebble_c = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))

    assert worker_c =~ "dispatch_needs_render"
    assert worker_c =~ "if (!elmc_cmd_is_none(next_cmd))"
    assert pebble_c =~ "elmc_worker_dispatch_needs_render"
    assert pebble_c =~ "elmc_pebble_invalidate_scene_for_dispatch"
    refute pebble_c =~ "elmc_pebble_prepare_dispatch(ElmcPebbleApp *app) {\n      if (!app) return;\n      elmc_pebble_heap_log(\"dispatch:prepare:before\");\n      elmc_pebble_clear_view_cache(app);"
  end
end
