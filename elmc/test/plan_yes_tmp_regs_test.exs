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

    # Pipeline-generated C (not re-lower): native_int params with retain must
    # alias screenW/screenH, not leave plan_native_int_0 uninitialized.
    out_dir = Path.expand("tmp/plan_yes_tmp_regs", __DIR__)
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    {start, _} =
      :binary.match(
        generated,
        "static RC elmc_fn_Yes_Layout_fromScreen(ElmcValue **out, elmc_int_t screenW, elmc_int_t screenH) {"
      )

    stop =
      case :binary.match(generated, "\n}\n\nstatic ", start) do
        {idx, _} -> idx
        :nomatch -> start + 2000
      end

    from_screen = binary_part(generated, start, stop - start)
    refute from_screen =~ "(void)screenH"
    refute from_screen =~ ~r/\bplan_native_int_0\b/
    assert from_screen =~ "screenW"
    assert from_screen =~ "screenH"
  end
end
