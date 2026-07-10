defmodule Elmc.PlanTemplateStrictGateTest do
  @moduledoc """
  Smoke gate: selected watch templates must compile with `plan_ir_strict: true`.

  Templates are fixtures only. Failures indicate missing **generic** plan lowering,
  not app bugs. See `docs/PLAN_IR_COVERAGE.md` for the coverage matrix and how to
  extend it.
  """

  use ExUnit.Case, async: false

  alias Elmc.TestSupport.TemplateCompile

  @moduletag :slow

  # Templates verified to pass strict plan-primary (zero plan_primary_fallback).
  # Add a name here only after `plan_ir_strict: true` compiles cleanly.
  @strict_pass ~w(
    game_2048
    game_elmtris
    game_basic
    game_jump_n_run
    game_tiny_bird
    watchface_poke_battle
    watchface_yes
    watchface_analog
    watchface_digital
    watchface_minimal
    watchface_weather_animated
    watchface_tangram_time
    watchface_color_shapes
    watchface_smoke_screen
    app_minimal
    watch_demo_accel
    watch_demo_storage
    companion_demo_storage
    companion_demo_weather_env
    starter_watch
  )

  for template <- @strict_pass do
    @tag template: template

    test "strict plan-primary compiles #{template}", %{template: template} do
      out_dir = Path.expand("tmp/plan_strict_gate/#{template}", __DIR__)

      assert {:ok, result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 out_dir: out_dir
               )

      fallbacks =
        (result.layout_coercion_diagnostics || [])
        |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))

      assert fallbacks == [],
             "expected zero plan_primary_fallback, got:\n#{inspect(fallbacks, pretty: true)}"
    end
  end
end
