defmodule Elmc.TangramTemplateCodegenTest do
  use ExUnit.Case

  @moduletag timeout: 300_000

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Test.RcTrackHarness
  alias Elmc.TestSupport.TangramTemplate

  setup do
    on_exit(fn ->
      for key <- [
            :elmc_codegen_opts,
            :elmc_constructor_tags,
            :elmc_record_field_macros,
            :elmc_plan_ir_mode
          ] do
        Process.delete(key)
      end
    end)

    :ok
  end

  test "tangram watchface plan-primary direct render does not declare owned slots with call initializers" do
    project_dir = TangramTemplate.scaffold_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-primary-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated =~ ~r/ElmcValue \*owned\[\d+\] = elmc_fn_/
  end

  test "tangramFaceOps CIRCLE keeps distinct center and radius slots after fusion probes" do
    project_dir = TangramTemplate.scaffold_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-circle-slots-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_tangramFaceOps_commands_append")

    # Fusion probes (TailRecursiveLoop.try_emit) used to ValueSlots.reset mid-emit,
    # so clockRadius reused owned[0] (cx) and CIRCLE drew a degenerate circle.
    refute Regex.match?(
             ~r/ELMC_RENDER_OP_CIRCLE[\s\S]{0,400}?scene_cmd\.p0 = elmc_as_int\(owned\[(\d+)\]\);[\s\S]{0,120}?scene_cmd\.p2 = elmc_as_int\(owned\[\1\]\);/,
             body
           ),
           "CIRCLE center x and radius must not share one owned slot"

    new_int_slots =
      Regex.scan(~r/Rc = elmc_new_int\(&owned\[(\d+)\],/, body)
      |> Enum.map(fn [_, idx] -> String.to_integer(idx) end)
      |> Enum.uniq()

    # Native locals may replace some boxed ints; keep at least distinct center/radius roots.
    assert length(new_int_slots) >= 2
    assert Enum.min(new_int_slots) == 0
  end

  test "tangram watchface view codegen does not reference phantom Main.start helpers" do
    project_dir = TangramTemplate.scaffold_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-codegen-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated =~ "elmc_fn_Main_start",
           "expected minutePoint let-bindings to inline, not call phantom top-level helpers"

    assert generated =~ "ELMC_RENDER_OP_FILL_CIRCLE"
    assert generated =~ "elmc_fn_Main_tangramFaceOps"

    hour_markers_native =
      Elmc.Test.CCodegenExtract.fn_body(
        generated,
        "elmc_fn_Main_hourMarkers_commands_append_native"
      )

    # Color params are `elmc_int_t`; wrapping them with elmc_as_int fails under
    # Pebble SDK `-Werror=int-conversion` (CommandDef vs Plan param_kinds drift).
    refute hour_markers_native =~ "elmc_as_int(color)",
           "native Color param must not be passed through elmc_as_int"

    assert hour_markers_native =~ "scene_cmd.p3 = color;"
    # Native Int ABI may be `clockPoint_native(... const elmc_int_t ...)` or plan-primary
    # `elmc_fn_Main_clockPoint(... elmc_int_t ...)` without the `_native` suffix.
    assert generated =~
             ~r/(?:clockPoint_native|elmc_fn_Main_clockPoint)\(ElmcValue \*\*out, (?:const )?elmc_int_t cx, (?:const )?elmc_int_t cy, (?:const )?elmc_int_t slot, (?:const )?elmc_int_t radius\)/
    assert generated =~ ~r/elmc_fn_Main_hourMarkers(?:_native)?\b/
    assert generated =~
             ~r/(?:Rc = elmc_fn_Main_hourMarkers(?:_native)?\(&(?:tmp_\d+|owned\[\d+\]), (?:native_let_cx_\d+|plan_native_int_\d+), (?:native_let_cy_\d+|plan_native_int_\d+), (?:native_let_markerRadius_\d+|plan_native_int_\d+), (?:owned\[\d+\]|elmc_as_int\(owned\[\d+\]\))\)|ElmcValue \*tmp_\d+ = elmc_fn_Main_hourMarkers(?:_native)?\((?:native_let_cx_\d+|plan_native_int_\d+), (?:native_let_cy_\d+|plan_native_int_\d+), (?:native_let_markerRadius_\d+|plan_native_int_\d+), (?:owned\[\d+\]|elmc_as_int\(owned\[\d+\]\))\))/
    refute generated =~
             ~r/elmc_new_int\(&owned\[\d+\], native_let_cx_\d+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*Rc = elmc_new_int\(&owned\[\d+\], native_let_cy_\d+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*Rc = elmc_new_int\(&owned\[\d+\], native_let_markerRadius_\d+\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*ElmcValue \*call_args_\d+\[1\] = \{ model \};\s*\n\s*Rc = elmc_fn_Main_foregroundColor\(&owned\[\d+\], call_args_\d+, 1\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*\n\s*ElmcValue \*call_args_\d+\[4\] = \{ owned\[\d+\], owned\[\d+\], owned\[\d+\], owned\[\d+\] \};\s*\n\s*Rc = elmc_fn_Main_hourMarkers/
    # Direct-call ABI: `tangramFaceOps(&owned[i], model)` (no argc/call_args wrapper).
    assert generated =~
             ~r/Rc = elmc_fn_Main_tangramFaceOps\(&(?:tmp_\d+|owned\[\d+\]),\s*model\)/

    refute generated =~ ~r/ELMC_RC_LOG_FAIL\(__call_rc, "elmc_fn_Main_p/

    form_origin =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_formOrigin")

    assert form_origin =~ "CATCH_BEGIN"
    assert form_origin =~ "ElmcValue *owned["
    assert form_origin =~ "Rc = elmc_fn_Main_p(&"
    assert form_origin =~ "CHECK_RC(Rc);"
    assert form_origin =~ "Rc = elmc_fn_Main_nudgePoint("
    assert form_origin =~ "elmc_release_array_lifo(owned,"
    refute form_origin =~ "ELMC_RC_LOG_FAIL(__call_rc"
    assert Regex.scan(~r/return Rc;/, form_origin) |> length() == 1

    vector_draw_origin =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_vectorDrawOrigin")

    assert vector_draw_origin =~ "elmc_record_new_values_take("
    assert vector_draw_origin =~ "CHECK_RC(Rc);"

    catch_body =
      case Regex.run(~r/CATCH_BEGIN([\s\S]*?)CATCH_END/, vector_draw_origin) do
        [_, body] -> body
        _ -> flunk("expected vectorDrawOrigin to use CATCH_BEGIN/CATCH_END")
      end

    refute catch_body =~ ~r/\breturn\b/
    assert Regex.scan(~r/return Rc;/, vector_draw_origin) |> length() == 1
    assert vector_draw_origin =~ "return Rc;"

    minute_point =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_minutePoint")

    # Native-int Point records use elmc_record_new_values_ints (not boxed take).
    assert minute_point =~ "elmc_record_new_values_ints("
    assert minute_point =~ "CATCH_BEGIN"
    assert Regex.scan(~r/return Rc;/, minute_point) |> length() == 1

    piece_color =
      Elmc.Test.CCodegenExtract.fn_body(generated, "elmc_fn_Main_pieceColor")

    # Native int color table — value-return helper (not RC out-ptr).
    assert piece_color =~ "ELMC_COLOR_"
    assert piece_color =~ "elmc_new_int("
    refute piece_color =~ "ELMC_RC_INT_BOX("
    refute piece_color =~ "ELMC_RC_LOG_FAIL(__call_rc"
  end

  @tag :tangram_host
  @tag :slow
  test "tangram watchface ensure_scene builds without heap corruption" do
    project_dir = TangramTemplate.scaffold_project()
    out_dir = Path.join(System.tmp_dir!(), "tangram-host-#{System.unique_integer([:positive])}")
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
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


      """
    )

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      static ElmcValue *basalt_launch_context(void) {
        ElmcValue *reason = elmc_harness_new_int(2);
        ElmcValue *watch_model = elmc_harness_new_string("");
        ElmcValue *watch_profile_id = elmc_harness_new_string("basalt");
        ElmcValue *width = elmc_harness_new_int(144);
        ElmcValue *height = elmc_harness_new_int(168);
        ElmcValue *shape = elmc_harness_new_int(1);
        ElmcValue *color_mode = elmc_harness_new_int(1);
        ElmcValue *screen_values[] = {width, height, shape, color_mode};
        ElmcValue *screen = elmc_harness_record_new_values_take(4, screen_values);
        ElmcValue *has_microphone = elmc_harness_new_int(0);
        ElmcValue *has_compass = elmc_harness_new_int(0);
        ElmcValue *supports_health = elmc_harness_new_int(0);
        ElmcValue *context_values[] = {reason, watch_model, watch_profile_id, screen, has_microphone,
                                       has_compass, supports_health};
        ElmcValue *ret = elmc_harness_record_new_values_take(7, context_values);
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
        "-Werror=int-conversion",
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
