defmodule Elmc.TangramTemplateCodegenTest do
  use ExUnit.Case

  @repo_root Path.expand("../..", __DIR__)

  test "tangram watchface view codegen does not reference phantom Main.start helpers" do
    project_dir = scaffold_tangram_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-codegen-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated =~ "elmc_fn_Main_start",
           "expected minutePoint let-bindings to inline, not call phantom top-level helpers"

    assert generated =~ "ELMC_RENDER_OP_FILL_CIRCLE"
    assert generated =~ "elmc_fn_Main_tangramFaceOps"
    assert generated =~ "Rc = elmc_fn_Main_tangramFaceOps(&tmp_1, call_args_1, 1)"

    refute generated =~
             ~r/if \(native_b_\d+\) \{\n\s+ElmcValue \*tmp_\d+ = NULL;\n\s+Rc = elmc_new_int\(&tmp_/,
           "if-branch color literals must assign into the shared result slot without orphan temps"
  end

  @tag :tangram_host
  test "tangram watchface ensure_scene builds without heap corruption" do
    project_dir = scaffold_tangram_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-host-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated =~
             ~r/elmc_release\(tmp_2\);\n\s+ElmcValue \*tmp_\d+ = elmc_fn_Main_clockPoint_native\(tmp_2/,
           "hourMarkers must not release shared clockPoint operands before reuse"

    cc = System.find_executable("cc") || flunk("cc not available for tangram host harness")

    prelude_path = Path.join(out_dir, "c/tangram_harness_prelude.h")
    harness_path = Path.join(out_dir, "c/tangram_ensure_scene_harness.c")
    binary_path = Path.join(out_dir, "tangram_ensure_scene_harness")

    File.write!(
      prelude_path,
      """
      #include "elmc_runtime.h"
      ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **a, int n);
      ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **a, int n);
      """
    )

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **a, int n) {
        (void)a;
        (void)n;
        return elmc_int_zero();
      }

      ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **a, int n) {
        (void)a;
        (void)n;
        return elmc_int_zero();
      }

      static ElmcValue *basalt_launch_context(void) {
        ElmcValue *reason = elmc_new_int_take(2);
        ElmcValue *watch_model = elmc_new_string_take("");
        ElmcValue *watch_profile_id = elmc_new_string_take("basalt");
        ElmcValue *width = elmc_new_int_take(144);
        ElmcValue *height = elmc_new_int_take(168);
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *color_mode = elmc_new_int_take(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_record_new_values_take_value(4, screen_values);
        ElmcValue *has_microphone = elmc_new_int_take(0);
        ElmcValue *has_compass = elmc_new_int_take(0);
        ElmcValue *supports_health = elmc_new_int_take(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        return elmc_record_new_values_take_value(7, context_values);
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *context = basalt_launch_context();
        if (elmc_pebble_init(&app, context) != 0) return 1;
        elmc_release(context);

        if (elmc_pebble_ensure_scene(&app) != 0) return 2;
        if (elmc_pebble_scene_command_count(&app) <= 0) return 3;
        if (app.scene.byte_count <= 0) return 4;

        elmc_pebble_deinit(&app);
        return 0;
      }
      """
    )

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-include",
        prelude_path,
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

    if compile_code != 0, do: flunk("tangram host harness compile failed:\n#{compile_out}")

    {_run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)
    assert run_code == 0
  end

  defp scaffold_tangram_project do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elmc-tangram-#{System.unique_integer([:positive])}"
      )

    template_src =
      Path.join(@repo_root, "ide/priv/project_templates/watchface_tangram_time")

    File.mkdir_p!(Path.join(tmp, "src"))
    File.mkdir_p!(Path.join(tmp, "protocol/src"))
    File.cp_r!(Path.join(template_src, "src"), Path.join(tmp, "src"))
    File.cp_r!(Path.join(template_src, "protocol/src"), Path.join(tmp, "protocol/src"))

    sources = [
      "src",
      "protocol/src",
      Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
      Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
      Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
      Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
    ]

    elm_json = %{
      "type" => "application",
      "source-directories" => sources,
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))
    tmp
  end
end
