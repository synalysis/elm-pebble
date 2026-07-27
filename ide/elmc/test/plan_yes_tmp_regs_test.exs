defmodule Elmc.PlanYesTmpRegsTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLower
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.TestSupport.TemplateCompile

  @tag :slow
  test "watchface_yes plan helpers do not emit undeclared tmp_ regs" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes",
        plan_ir_mode: :primary,
        out_dir: Path.expand("tmp/plan_yes_tmp_regs", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    Process.put(:elmc_program_decls, decl_map)

    on_exit(fn -> Process.delete(:elmc_program_decls) end)

    for {name, rc?} <- [
          {"batteryAlert", true},
          {"normalizeCycleSec", true},
          {"monthString", false}
        ] do
      decl = Map.fetch!(decl_map, {"Main", name})

      {:ok, plan} =
        PlanLower.lower(decl, "Main", decl_map, rc_required: rc?)

      body = CLower.emit(plan, rc_required: rc?)

      refute body =~ ~r/\btmp_\d+\b/,
             "Main.#{name} emitted undeclared tmp reg:\n#{body}"
    end
  end
end
