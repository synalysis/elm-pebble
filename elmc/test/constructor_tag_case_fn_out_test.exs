defmodule Elmc.ConstructorTagCaseFnOutTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract

  @source_template Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)

  test "SecondChanged update branch writes function out once after tuple assembly" do
    project_dir = Path.expand("tmp/constructor_tag_case_fn_out_project", __DIR__)
    out_dir = Path.expand("tmp/constructor_tag_case_fn_out_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(@source_template, project_dir)

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

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    update_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_update")

    second_changed =
      update_body
      |> String.split("case ELMC_PEBBLE_MSG_SECONDCHANGED:")
      |> Enum.at(1)
      |> then(fn rest ->
        rest |> String.split("case ") |> hd()
      end)

    assert second_changed =~ "elmc_tuple2_take("
    refute second_changed =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;\n\s*owned\[\d+\] = \(\(\*out\)/

    battery_changed =
      update_body
      |> String.split("case ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED:")
      |> Enum.at(1)
      |> then(fn rest -> rest |> String.split("case ") |> hd() end)

    assert battery_changed =~ ~r/owned\[\d+\] = elmc_basics_clamp\(/
    assert battery_changed =~ "elmc_maybe_just_own(&owned["
    assert battery_changed =~ "Rc = elmc_tuple2_take(out,"
    refute battery_changed =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;/
    refute second_changed =~ "ElmcValue *tmp_"
    refute update_body =~ ~r/ElmcValue \*owned\[\d+\] = \(owned\[\d+\] == model\)/

    hour_changed =
      update_body
      |> String.split("case ELMC_PEBBLE_MSG_HOURCHANGED:")
      |> Enum.at(1)
      |> then(fn rest -> rest |> String.split("case ") |> hd() end)

    assert hour_changed =~ "Rc = elmc_cmd1(&owned["
    assert hour_changed =~ ~r/Rc = elmc_fn_Main_scheduleCompanionFetches\((?:out|&owned\[\d+\])/
    refute hour_changed =~ "elmc_release(owned["

    minute_changed =
      update_body
      |> String.split("case ELMC_PEBBLE_MSG_MINUTECHANGED:")
      |> Enum.at(1)
      |> then(fn rest -> rest |> String.split("case ") |> hd() end)

    refute minute_changed =~ ~r/owned\[0\] = owned\[\d+\];\n\s*owned\[0\] = owned\[\d+\];/
    assert minute_changed =~ ~r/Rc = elmc_fn_Main_scheduleCompanionFetches\(&owned\[\d+\],/
    assert minute_changed =~ "*out = owned["

    subs_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_subscriptions")

    assert subs_body =~ "if (elmc_maybe_just_true(owned[0]))"
    assert subs_body =~ "Rc = elmc_sub1(&owned[1], ELMC_SUBSCRIPTION_HEALTH"
    assert subs_body =~ "owned[1] = elmc_int_zero();"
    refute subs_body =~ "*out = elmc_int_zero();"
    refute subs_body =~ "owned[1] = tmp_"
    refute subs_body =~ "ElmcValue *tmp_"
    refute subs_body =~ "elmc_retain(owned[1])"
    assert subs_body =~ "Rc = elmc_sub1(&owned["
    assert subs_body =~ "elmc_list_from_values_take(out,"
    refute subs_body =~ ~r/elmc_list_from_values_take\(&owned\[\d+\]/
    refute subs_body =~ ~r/\*out = owned\[\d+\];\n\s*owned\[\d+\] = NULL;/

    corner_slots = CCodegenExtract.fn_body(generated, "elmc_fn_Main_cornerSlots")

    assert corner_slots =~ "(ElmcValue *[]){ model }"
    refute corner_slots =~ "ElmcValue *call_args_1[1] = { model };"
    assert corner_slots =~ "Rc = elmc_fn_Main_topLeftSlot(&owned[0], (ElmcValue *[]){ model }, 1);"
    assert corner_slots =~ "Rc = elmc_fn_Main_dateSlot(&owned[1], (ElmcValue *[]){ model }, 1);"
    assert corner_slots =~ "elmc_record_new_values_take(out,"
    refute corner_slots =~ "elmc_fn_Main_topLeftSlot(out,"
    refute corner_slots =~ "elmc_retain((*out))"

    top_left_available =
      CCodegenExtract.fn_body(generated, "elmc_fn_Main_topLeftStepsAvailable")

    assert top_left_available =~ "elmc_fn_Main_topLeftStepsAvailable_native(&native_result, model);"
    refute top_left_available =~ "elmc_new_bool(out, elmc_fn_Main_topLeftStepsAvailable_native(model))"
    refute top_left_available =~ "ElmcValue *tmp_"

    top_left_native =
      CCodegenExtract.fn_body(generated, "elmc_fn_Main_topLeftStepsAvailable_native")

    assert generated =~ "static RC elmc_fn_Main_topLeftStepsAvailable_native(bool *out,"
    assert top_left_native =~ "CATCH_BEGIN"
    assert top_left_native =~ "CHECK_RC("
    assert top_left_native =~ "ElmcValue *owned["
    assert top_left_native =~ "Rc = elmc_fn_Main_haveSteps("
    assert top_left_native =~ "*out = "
    refute top_left_native =~ "ElmcValue *tmp_"
    refute top_left_native =~ "bool (native_"
    refute top_left_native =~ "__alloc_rc"
    refute top_left_native =~ "__call_rc"
    refute top_left_native =~ ~r/;;/
    refute top_left_native =~ ~r/elmc_release\(tmp_/
    assert top_left_native =~ "owned["

    has_moon_times = CCodegenExtract.fn_body(generated, "elmc_fn_Main_hasMoonTimes")
    assert has_moon_times =~ "CATCH_BEGIN"
    refute has_moon_times =~ "if (Rc != RC_SUCCESS) return Rc;"
    assert has_moon_times =~ "return Rc;"

    has_moon_native = CCodegenExtract.fn_body(generated, "elmc_fn_Main_hasMoonTimes_native")
    refute has_moon_native =~ "elmc_release(tmp_"
    assert has_moon_native =~ "owned["

    corner_slots_fn = CCodegenExtract.fn_body(generated, "elmc_fn_Main_cornerSlots")
    refute corner_slots_fn =~ "elmc_release(tmp_"

    show_corners_native = CCodegenExtract.fn_body(generated, "elmc_fn_Main_showCorners_native")

    assert show_corners_native =~ "bool native_bool_if_"
    refute show_corners_native =~ ~r/;;/

    top_left_slot = CCodegenExtract.fn_body(generated, "elmc_fn_Main_topLeftSlot")

    assert top_left_slot =~ "ELMC_UNION_"
    assert top_left_slot =~ "BATTERYCORNER"
    assert top_left_slot =~ "(ElmcValue *[]){ model }"
    refute top_left_slot =~ "owned[4] = owned[4]"
    refute top_left_slot =~ "owned[7] = owned[7]"
    assert top_left_slot =~ "Rc = elmc_fn_Main_batteryPercentString(&owned["
    assert top_left_slot =~ "Rc = elmc_fn_Main_stepsString(&owned["
    assert top_left_slot =~ "elmc_record_new_values_take(out,"

    assert generated =~ "#define ELMC_UNION_COMPANION_TYPES_POLARDAY"
    assert generated =~ "#define ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    assert generated =~ "#define ELMC_UNION_COMPANION_TYPES_CELSIUS"

    sun_bottom_right = CCodegenExtract.fn_body(generated, "elmc_fn_Main_sunBottomRightSlot")

    assert sun_bottom_right =~ "ELMC_UNION_COMPANION_TYPES_POLARDAY"
    assert sun_bottom_right =~ "ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    refute sun_bottom_right =~ ~r/elmc_union_tag_matches\([^,]+,\s*2\)/

    temperature_string = CCodegenExtract.fn_body(generated, "elmc_fn_Main_temperatureString")
    assert temperature_string =~ "ELMC_UNION_COMPANION_TYPES_CELSIUS"

    direct_render = CCodegenExtract.fn_body(generated, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert direct_render =~ "ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    assert direct_render =~ "ELMC_UNION_COMPANION_TYPES_POLARDAY"
    refute direct_render =~ ~r/elmc_union_tag_matches\(owned\[17\],\s*3\)/
    refute direct_render =~ ~r/if \(elmc_scene_writer_push_cmd\(writer, &scene_cmd\) != 0\)/
    assert direct_render =~ "Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd)"
    assert direct_render =~ "CHECK_RC(Rc)"
    refute direct_render =~ ~r/^\s+;\s*$/m
  end
end
