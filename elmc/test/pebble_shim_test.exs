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
        if (elmc_pebble_dispatch_random_int(&app, 42) != 0) return 5;
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

  defp available_c_compilers do
    ["cc", "gcc", "clang"]
    |> Enum.map(fn name -> {name, System.find_executable(name)} end)
    |> Enum.filter(fn {_name, path} -> is_binary(path) end)
    |> Enum.uniq_by(fn {_name, path} -> path end)
  end

  defp draw_feature?(header, suffix) do
    String.contains?(header, "#define ELMC_PEBBLE_FEATURE_DRAW_#{suffix} 1")
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
end
