defmodule Elmc.TangramTemplateCodegenTest do
  use ExUnit.Case

  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TangramTemplate

  test "tangram watchface view codegen does not reference phantom Main.start helpers" do
    project_dir = TangramTemplate.scaffold_project()
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
    assert generated =~
             ~r/clockPoint_native\(ElmcValue \*\*out, const elmc_int_t cx, const elmc_int_t cy, const elmc_int_t slot, const elmc_int_t radius\)/
    assert generated =~ "elmc_fn_Main_hourMarkers_native"
    assert generated =~
             ~r/(?:Rc = elmc_fn_Main_hourMarkers_native\(&(?:tmp_\d+|owned\[\d+\]), native_let_cx_\d+, native_let_cy_\d+, native_let_markerRadius_\d+, owned\[\d+\]\)|ElmcValue \*tmp_\d+ = elmc_fn_Main_hourMarkers_native\(native_let_cx_\d+, native_let_cy_\d+, native_let_markerRadius_\d+, owned\[\d+\]\))/
    refute generated =~
             ~r/elmc_new_int\(&owned\[\d+\], native_let_cx_\d+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*Rc = elmc_new_int\(&owned\[\d+\], native_let_cy_\d+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*Rc = elmc_new_int\(&owned\[\d+\], native_let_markerRadius_\d+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*ElmcValue \*call_args_\d+\[1\] = \{ model \};\s*\n\s*Rc = elmc_fn_Main_foregroundColor\(&owned\[\d+\], call_args_\d+, 1\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*ElmcValue \*call_args_\d+\[4\] = \{ owned\[\d+\], owned\[\d+\], owned\[\d+\], owned\[\d+\] \};\s*\n\s*Rc = elmc_fn_Main_hourMarkers/
    assert generated =~ ~r/Rc = elmc_fn_Main_tangramFaceOps\(&(?:tmp_\d+|owned\[\d+\]), call_args_1, 1\)/

    refute generated =~ ~r/ELMC_RC_LOG_FAIL\(__call_rc, "elmc_fn_Main_p_native"/

    form_origin =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_formOrigin_native")

    assert form_origin =~ "CATCH_BEGIN"
    assert form_origin =~ "ElmcValue *owned["
    assert form_origin =~ "Rc = elmc_fn_Main_p_native(&"
    assert form_origin =~ "CHECK_RC(Rc);"
    assert form_origin =~ "elmc_fn_Main_nudgePoint(call_args_"
    assert form_origin =~ "*out = elmc_fn_Main_nudgePoint"
    assert form_origin =~ "elmc_release_array_lifo(owned, DIM(owned));"
    refute form_origin =~ ~r/owned\[\d+\] = owned\[\d+\];/
    refute form_origin =~ "ELMC_RC_LOG_FAIL(__call_rc"

    vector_draw_origin =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_vectorDrawOrigin_native")

    assert vector_draw_origin =~ "elmc_record_new_values_take(out,"
    assert vector_draw_origin =~ "CHECK_RC(Rc);"

    catch_body =
      case Regex.run(~r/CATCH_BEGIN([\s\S]*?)CATCH_END;/, vector_draw_origin) do
        [_, body] -> body
        _ -> flunk("expected vectorDrawOrigin_native to use CATCH_BEGIN/CATCH_END")
      end

    refute catch_body =~ ~r/\breturn\b/
    refute catch_body =~ "*out = owned["
    assert Regex.scan(~r/return Rc;/, vector_draw_origin) |> length() == 1
    assert vector_draw_origin =~ "return Rc;"

    minute_point =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_minutePoint_native")

    assert minute_point =~ "elmc_record_new_values_take(out,"
    refute minute_point =~ "*out = owned["

    piece_color =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_pieceColor_native")

    piece_catch =
      case Regex.run(~r/CATCH_BEGIN([\s\S]*?)CATCH_END;/, piece_color) do
        [_, body] -> body
        _ -> flunk("expected pieceColor_native to use CATCH_BEGIN/CATCH_END")
      end

    assert piece_color =~ "CHECK_RC(Rc);"
    refute piece_catch =~ ~r/\breturn\b/
    assert piece_catch =~ ~r/\*out = tmp_\d+;/
    assert Regex.scan(~r/return Rc;/, piece_color) |> length() == 1
    assert piece_color =~ "return Rc;"
  end

  @tag :tangram_host
  test "tangram watchface ensure_scene builds without heap corruption" do
    project_dir = TangramTemplate.scaffold_project()
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
      #{RcTrackHarness.harness_rc_helpers()}
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
        ElmcValue *reason = elmc_harness_new_int(2);
        ElmcValue *watch_model = elmc_harness_new_string("");
        ElmcValue *watch_profile_id = elmc_harness_new_string("basalt");
        ElmcValue *width = elmc_harness_new_int(144);
        ElmcValue *height = elmc_harness_new_int(168);
        ElmcValue *shape = elmc_new_int_take(1);
        ElmcValue *color_mode = elmc_harness_new_int(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_record_new_values_take_value(4, screen_values);
        ElmcValue *has_microphone = elmc_harness_new_int(0);
        ElmcValue *has_compass = elmc_harness_new_int(0);
        ElmcValue *supports_health = elmc_harness_new_int(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        ElmcValue *ret = elmc_record_new_values_take_value(7, context_values);
        return ret;
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
end
