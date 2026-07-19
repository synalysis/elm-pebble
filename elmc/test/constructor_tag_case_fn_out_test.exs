defmodule Elmc.ConstructorTagCaseFnOutTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract

  test "SecondChanged update branch writes function out once after tuple assembly" do
    out_dir = Path.expand("tmp/constructor_tag_case_fn_out_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template("watchface_yes",
               out_dir: out_dir,
               plan_ir_mode: :primary,
               plan_ir_strict: false,
               direct_render_only: true,
               prune_runtime: true,
               pebble_int32: true,
               strip_dead_code: true
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    update_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_update")

    # Plan-primary update dispatches on union tags, then merges once into *out.
    assert update_body =~ "case ELMC_UNION_MAIN_SECONDCHANGED:"
    assert update_body =~ "case ELMC_UNION_MAIN_BATTERYLEVELCHANGED:"
    assert update_body =~ ~r/\*out = owned\[\d+\];/
    refute update_body =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;\n\s*owned\[\d+\] = \(\(\*out\)/
    refute update_body =~ "ElmcValue *tmp_"
    refute update_body =~ ~r/ElmcValue \*owned\[\d+\] = \(owned\[\d+\] == model\)/

    second_changed = plan_case_body(update_body, "ELMC_UNION_MAIN_SECONDCHANGED")
    assert second_changed =~ "elmc_tuple2("
    refute second_changed =~ "*out ="
    refute second_changed =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;/

    battery_changed = plan_case_body(update_body, "ELMC_UNION_MAIN_BATTERYLEVELCHANGED")
    assert battery_changed =~ "elmc_basics_clamp("
    assert battery_changed =~ "elmc_maybe_just_own(&owned["
    assert battery_changed =~ "elmc_tuple2("
    refute battery_changed =~ "*out ="
    refute battery_changed =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;/

    hour_changed = plan_case_body(update_body, "ELMC_UNION_MAIN_HOURCHANGED")
    assert hour_changed =~ "Rc = elmc_cmd1(&owned["
    assert hour_changed =~ ~r/Rc = elmc_fn_Main_scheduleCompanionFetches\(&owned\[\d+\]/
    refute hour_changed =~ "*out ="

    minute_changed = plan_case_body(update_body, "ELMC_UNION_MAIN_MINUTECHANGED")
    refute minute_changed =~ ~r/owned\[0\] = owned\[\d+\];\n\s*owned\[0\] = owned\[\d+\];/
    assert minute_changed =~ ~r/Rc = elmc_fn_Main_scheduleCompanionFetches\(&owned\[\d+\],/
    refute minute_changed =~ "*out ="

    subs_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_subscriptions")

    # Plan-primary subscriptions assemble kernel Sub values via direct calls.
    assert subs_body =~ "elmc_fn_Pebble_Health_onEvent"
    assert subs_body =~ "elmc_fn_Pebble_Events_onMinuteChange"
    assert subs_body =~ "elmc_sub0" or subs_body =~ "elmc_sub1"
    refute subs_body =~ "*out = elmc_int_zero();"
    refute subs_body =~ "ElmcValue *tmp_"
    # Plan publishes the subscription list once at the epi.
    assert subs_body =~ ~r/\*out = owned\[\d+\];/
    refute subs_body =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;\n\s*\*out =/

    corner_slots = CCodegenExtract.fn_body(generated, "elmc_fn_Main_cornerSlots")

    assert corner_slots =~ "Rc = elmc_fn_Main_topLeftSlot(&owned["
    assert corner_slots =~ "Rc = elmc_fn_Main_dateSlot(&owned["
    assert corner_slots =~ "elmc_record_new_values_take("
    refute corner_slots =~ "elmc_retain((*out))"
    refute corner_slots =~ "ElmcValue *tmp_"

    top_left_native =
      CCodegenExtract.fn_body(generated, "elmc_fn_Main_topLeftStepsAvailable_native")

    top_left_boxed =
      CCodegenExtract.fn_body(generated, "elmc_fn_Main_topLeftStepsAvailable")

    assert generated =~ "static RC elmc_fn_Main_topLeftStepsAvailable_native(bool *out,"
    assert top_left_native != ""

    # Plan may emit a thin projection wrapper over the boxed helper.
    if top_left_native =~ "CATCH_BEGIN" do
      assert top_left_native =~ "CHECK_RC("
      assert top_left_native =~ "ElmcValue *owned["
      assert top_left_native =~ "Rc = elmc_fn_Main_haveSteps("
      assert top_left_native =~ "*out = "
      refute top_left_native =~ "ElmcValue *tmp_"
      refute top_left_native =~ "__alloc_rc"
      refute top_left_native =~ "__call_rc"
      refute top_left_native =~ ~r/;;/
      refute top_left_native =~ ~r/elmc_release\(tmp_/
    else
      assert top_left_native =~ "elmc_fn_Main_topLeftStepsAvailable(&boxed"
      assert top_left_native =~ "*out = elmc_as_bool(boxed)"
      assert top_left_boxed =~ "Rc = elmc_fn_Main_haveSteps("
      refute top_left_boxed =~ "ElmcValue *tmp_"
      refute top_left_boxed =~ ~r/elmc_release\(tmp_/
    end

    has_moon_native = CCodegenExtract.fn_impl_body(generated, "elmc_fn_Main_hasMoonTimes_native")

    if has_moon_native != "" do
      if has_moon_native =~ "CATCH_BEGIN" do
        refute has_moon_native =~ "if (Rc != RC_SUCCESS) return Rc;"
        assert has_moon_native =~ "return Rc;" or has_moon_native =~ "*out ="
      else
        assert has_moon_native =~ "elmc_fn_Main_hasMoonTimes(&boxed"
        assert has_moon_native =~ "*out = elmc_as_bool(boxed)"
      end
    end

    corner_slots_fn = CCodegenExtract.fn_body(generated, "elmc_fn_Main_cornerSlots")
    refute corner_slots_fn =~ "elmc_release(tmp_"

    show_corners_native = CCodegenExtract.fn_body(generated, "elmc_fn_Main_showCorners_native")

    assert show_corners_native != ""
    refute show_corners_native =~ ~r/;;/

    top_left_slot = CCodegenExtract.fn_body(generated, "elmc_fn_Main_topLeftSlot")

    assert top_left_slot =~ "ELMC_UNION_"
    assert top_left_slot =~ "BATTERYCORNER"
    refute top_left_slot =~ "owned[4] = owned[4]"
    refute top_left_slot =~ "owned[7] = owned[7]"
    assert top_left_slot =~ "Rc = elmc_fn_Main_batteryPercentString(&owned["
    assert top_left_slot =~ "Rc = elmc_fn_Main_stepsString(&owned["
    assert top_left_slot =~ "elmc_record_new_values_take("
    assert top_left_slot =~ ~r/\*out = owned\[\d+\];/

    assert generated =~ "#define ELMC_UNION_COMPANION_TYPES_POLARDAY"
    assert generated =~ "#define ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    assert generated =~ "#define ELMC_UNION_COMPANION_TYPES_CELSIUS"

    sun_bottom_right = CCodegenExtract.fn_body(generated, "elmc_fn_Main_sunBottomRightSlot")

    assert sun_bottom_right =~ "ELMC_UNION_COMPANION_TYPES_POLARDAY"
    assert sun_bottom_right =~ "ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    refute sun_bottom_right =~ ~r/elmc_union_tag_matches\([^,]+,\s*2\)/

    temperature_string = CCodegenExtract.fn_body(generated, "elmc_fn_Main_temperatureString")
    temperature_string_native = CCodegenExtract.fn_impl_body(generated, "elmc_fn_Main_temperatureString")

    assert temperature_string =~ "elmc_fn_Main_temperatureString_native" or
             temperature_string_native =~ "ELMC_UNION_COMPANION_TYPES_CELSIUS"

    direct_render = CCodegenExtract.fn_body(generated, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert direct_render =~ "ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    assert direct_render =~ "ELMC_UNION_COMPANION_TYPES_POLARDAY"
    refute direct_render =~ ~r/elmc_union_tag_matches\(owned\[17\],\s*3\)/
    refute direct_render =~ ~r/if \(elmc_scene_writer_push_cmd\(writer, &scene_cmd\) != 0\)/
    assert direct_render =~ "Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd)"
    assert direct_render =~ "CHECK_RC(Rc)"
    refute direct_render =~ ~r/^\s+;\s*$/m
  end

  defp plan_case_body(update_body, union_macro) do
    case_entries =
      Regex.scan(~r/case ELMC_UNION_MAIN_\w+:\s*goto (elmc_plan_block_\d+);/, update_body)
      |> Enum.map(fn [_, label] -> label end)

    case Regex.run(~r/case #{union_macro}:\s*goto (elmc_plan_block_\d+);/, update_body) do
      [_, label] ->
        after_label =
          update_body
          |> String.split(label <> ":", parts: 2)
          |> Enum.at(1)

        assert is_binary(after_label), "missing plan label #{label} for #{union_macro}"

        next_entries =
          case_entries
          |> Enum.drop_while(&(&1 != label))
          |> Enum.drop(1)

        Enum.reduce_while(next_entries, after_label, fn next_label, body ->
          case String.split(body, next_label <> ":", parts: 2) do
            [before, _] -> {:halt, before}
            [_] -> {:cont, body}
          end
        end)

      _ ->
        flunk("update body missing case #{union_macro}")
    end
  end
end
