defmodule Elmc.PlanPrimaryCodegenShapeTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  @templates ~w(
    game_elmtris
    game_2048
    watchface_analog
    watchface_digital
    watchface_yes
    app_minimal
    game_tiny_bird
  )

  for template <- @templates do
    @tag template: template
    test "primary #{template} has no legacy plan bridge markers", %{template: template} do
      out_dir = Path.expand("tmp/plan_codegen_shape_#{template}", __DIR__)
      File.rm_rf!(out_dir)

      assert {:ok, result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 out_dir: out_dir
               )

      refute Enum.any?(result.layout_coercion_diagnostics || [], fn diag ->
               diag["code"] in ["plan_primary_fallback", "plan_primary_gap"] and
                 diag["severity"] == "error"
             end)

      generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

      refute generated_c =~ "plan_primary_boxed",
             "#{template} still emits plan_primary_boxed native bridge"

      assert generated_c =~ "plan block",
             "#{template} missing plan block markers in generated C"
    end
  end
end
