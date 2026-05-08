defmodule Elmc.PebbleShimTest do
  use ExUnit.Case

  test "pebble shim decodes appmessage payloads and drives worker loop" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for pebble shim C test")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/pebble_shim_project", __DIR__)
    out_dir = Path.expand("tmp/pebble_shim", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    write_companion_internal!(project_dir)
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
        if (elmc_pebble_active_subscriptions(&app) != 31) return 31;

        if (elmc_pebble_tick(&app) != 0) return 3;
        if (elmc_pebble_take_cmd(&app, &cmd) != 0) return 22;
        if (elmc_pebble_dispatch_appmessage(&app, 0, ELMC_PEBBLE_MSG_INCREMENT) != 0) return 4;
        if (elmc_pebble_dispatch_appmessage(&app, ELMC_PEBBLE_MSG_DECREMENT, 1) != 0) return 5;
        if (elmc_pebble_dispatch_button(&app, ELMC_PEBBLE_BUTTON_UP) != 0) return 6;
        if (elmc_pebble_dispatch_button(&app, ELMC_PEBBLE_BUTTON_SELECT) != 0) return 26;
        if (elmc_pebble_dispatch_button(&app, ELMC_PEBBLE_BUTTON_DOWN) != 0) return 7;
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

  defp available_c_compilers do
    ["cc", "gcc", "clang"]
    |> Enum.map(fn name -> {name, System.find_executable(name)} end)
    |> Enum.filter(fn {_name, path} -> is_binary(path) end)
    |> Enum.uniq_by(fn {_name, path} -> path end)
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

  defp write_companion_internal!(project_dir) do
    path = Path.join(project_dir, "src/Companion/Internal.elm")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    module Companion.Internal exposing (watchToPhoneTag, watchToPhoneValue)

    import Companion.Types exposing (WatchToPhone)


    watchToPhoneTag : WatchToPhone -> Int
    watchToPhoneTag _ =
        2


    watchToPhoneValue : WatchToPhone -> Int
    watchToPhoneValue _ =
        3
    """)
  end
end
