alias Elmc.Backend.Plan.Lower.Function
alias Elmc.Backend.Plan.Lower.{Expr, Case, PatternBind}
alias Elmc.Backend.Plan.{Builder, Context, PrimaryCoverage}
alias Elmc.Backend.CCodegen.IRQueries

fixture = Path.expand("../test/fixtures/simple_project", __DIR__)
# Match compile pipeline more closely
{:ok, result} =
  Elmc.compile(fixture, %{
    out_dir: Path.expand("../test/tmp/probe_gbw", __DIR__),
    entry_module: "Main",
    strip_dead_code: false,
    plan_ir_mode: :primary,
    plan_ir_strict: true
  })

ir = result.ir
decl_map = IRQueries.function_decl_map(ir)
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
key = {"Pkg.elm_random_1_0_0.Random", "getByWeight"}
decl = Map.fetch!(decl_map, key)
IO.puts("args=#{inspect(decl.args)}")
IO.puts("type=#{inspect(decl.type)}")
IO.inspect(decl.expr, pretty: true, limit: :infinity, printable_limit: :infinity)

# PrimaryCoverage path
report = PrimaryCoverage.all_functions_report(decl_map)
failed = Enum.filter(report.failed, fn {m,n,_} -> n == "getByWeight" end)
IO.inspect(failed, label: "coverage failed")
IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "reasons after coverage")

# Direct lower again after compile state
Process.put(:elmc_plan_unsupported_reasons, %{})
IO.inspect(Function.lower(decl, elem(key,0), decl_map, rc_required: true), label: "direct lower")
IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "reasons")

# Check layout diagnostics
diags = result.layout_coercion_diagnostics || []
fb = Enum.filter(diags, &(&1["code"] == "plan_primary_fallback"))
IO.inspect(fb, label: "fallbacks", pretty: true)
