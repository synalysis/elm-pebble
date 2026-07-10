defmodule Elmc.PlanYesRenderLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  test "watchface_yes fromScreen decl args match cdecl param names" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes",
        plan_ir_mode: :primary,
        out_dir: Path.expand("tmp/plan_yes_from_screen_args", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    decl = Map.fetch!(decl_map, {"Yes.Layout", "fromScreen"})

    assert decl.args == ["screenW", "screenH"]
    assert is_binary(decl.type) and String.contains?(decl.type, "Int")

    alias Elmc.Backend.CCodegen.Native.FunctionCall

    assert FunctionCall.call_site_arg_kinds(decl, "Yes.Layout", decl_map) == [
             :native_int,
             :native_int
           ]

    {:ok, plan} = PlanLower.lower(decl, "Yes.Layout", decl_map, rc_required: true)

    init_decl = Map.fetch!(decl_map, {"Main", "init"})
    {:ok, init_plan} = PlanLower.lower(init_decl, "Main", decl_map, rc_required: true)

    init_calls =
      init_plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :call_fn))
      |> Enum.map(&{&1.args.module, &1.args.name})

    assert {"Yes.Layout", "fromScreen"} in init_calls,
           "init call_fn targets: #{inspect(init_calls)}"

    assert Enum.map(plan.params, & &1.name) == ["screenW", "screenH"]

    load_params =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))

    assert Enum.all?(load_params, fn %{args: %{index: idx}} -> idx in [0, 1] end)

    const_c_exprs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :const_c_expr))
      |> Enum.map(& &1.args.value)

    refute Enum.any?(const_c_exprs, &String.starts_with?(&1, "arg"))
  end

  test "watchface_yes Yes.Render and Yes.Layout lower without fallbacks" do
    out_dir = Path.expand("tmp/plan_yes_render_lower", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             TemplateCompile.compile_watch_template("watchface_yes",
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)

    for {mod, name} <- [
          {"Yes.Render", "drawBottomRight"},
          {"Yes.Render", "drawBottomRightCountdown"},
          {"Yes.Render", "pointAt"},
          {"Yes.Layout", "fromScreen"}
        ] do
      decl = Map.fetch!(decl_map, {mod, name})

      assert {:ok, _plan} =
               PlanLower.lower(decl, mod, decl_map, rc_required: false),
             "expected plan lowering for #{mod}.#{name}"
    end

    yes_failed =
      PrimaryCoverage.report(decl_map, ir: result.ir).failed
      |> Enum.filter(fn {mod, _, _} -> String.starts_with?(mod, "Yes.") end)

    assert yes_failed == []

    refute Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "plan_primary_fallback"))

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    point_at_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_pointAt")
    assert point_at_body =~ "plan block"
    assert point_at_body =~ "elmc_basics_sin"
    assert point_at_body =~ "elmc_new_float"

    draw_br_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_drawBottomRight")
    assert draw_br_body =~ "elmc_render_cmd6"
    refute draw_br_body =~ "drawVectorAt_native"

    init_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_init")
    assert init_body =~ "Rc = elmc_fn_Yes_Layout_fromScreen(&owned["
    assert init_body =~ "plan_native_int_"
    refute init_body =~ "elmc_as_int(owned[2])"
    refute init_body =~ "owned[5] = elmc_fn_Yes_Layout_fromScreen("

    from_screen_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Layout_fromScreen")
    refute from_screen_body =~ "elmc_int_t plan_native_int_87;"
    refute from_screen_body =~ "plan_native_int_93 ="
    assert from_screen_body =~ "elmc_int_t plan_native_int_55;"
    refute from_screen_body =~ "elmc_as_int(arg"
    refute from_screen_body =~ "tmp_"
    refute from_screen_body =~ "Rc = elmc_new_int(out,"
    assert from_screen_body =~ "elmc_int_idiv"
    refute from_screen_body =~ ~r/owned\[\d+\] = elmc_new_int_take\(screenW\)/
    refute from_screen_body =~ ~r/owned\[\d+\] = elmc_new_int_take\(screenH\)/
    assert from_screen_body =~ "elmc_new_int_take(screenW)"
    assert from_screen_body =~ "elmc_new_int_take(screenH)"

    direction_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_directionString_native")
    assert direction_body =~ "switch ("
    refute direction_body =~ "goto elmc_plan_block_"
    refute direction_body =~ "elmc_fn_Main_direction("

    month_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_monthString_native")
    assert month_body =~ "native_str_immortal_lut_"
    assert month_body =~ "*out ="
    refute month_body =~ "goto elmc_plan_block_"
    refute month_body =~ "elmc_as_int(month)"

    refute generated_c =~ "watchToPhoneTag"
    assert generated_c =~ "ELMC_PEBBLE_CMD_COMPANION_SEND, 3, 0"

    wind_speed_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_windSpeedString_native")
    assert wind_speed_body =~ "snprintf"
    assert wind_speed_body =~ "%lldm/s"
    refute wind_speed_body =~ "goto elmc_plan_block_"

    altitude_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_altitudeString_native")
    assert altitude_body =~ "snprintf"
    assert altitude_body =~ "%lldft"

    wind_speed_wrapper = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_windSpeedString")
    assert wind_speed_wrapper =~ "windSpeedString_native(out, speed)"
    refute wind_speed_wrapper =~ "elmc_as_int(speed)"

    temp_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_temperatureString_native")
    assert temp_body =~ "outer_maybe"
    assert temp_body =~ "snprintf"
    assert temp_body =~ "%lldC"
    refute temp_body =~ "goto elmc_plan_block_"

    steps_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_stepsString_native")
    assert steps_body =~ "steps >= 10000"
    assert steps_body =~ "%lldk"
    refute steps_body =~ "goto elmc_plan_block_"

    battery_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_batteryPercentString_native")
    assert battery_body =~ "elmc_maybe_with_default_int(0"
    assert battery_body =~ "%lld%%"
    refute battery_body =~ "goto elmc_plan_block_"

    draw_dial_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_drawDial_commands_append")
    assert draw_dial_body =~ "direct_hoisted_int"
    assert draw_dial_body =~ "elmc_angle_from_minute"
    assert draw_dial_body =~ ~r/direct_item_i_\d+ & 1/
    refute draw_dial_body =~ ~r/native_mod_\d+ = direct_item_i_\d+ % 2/
    refute draw_dial_body =~ ~r/owned\[\d+\] = elmc_retain\(layout\)/
    refute draw_dial_body =~ ~r/elmc_release\(layout\)/
    refute Regex.match?(~r/ELMC_RECORD_GET_INDEX_INT\(owned\[\d+\], 2 \/\* cx \*\/\)/, draw_dial_body)
  end
end
