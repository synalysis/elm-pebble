alias ElmEx.Frontend.Bridge
alias ElmEx.IR.Lowerer
alias ElmEx.IR.PipeChain

fixture = Path.expand("../test/fixtures/simple_project", __DIR__)

# Mirror Elmc.compile project load
opts = %{entry_module: "Main", strip_dead_code: false, plan_ir_mode: :primary, plan_ir_strict: true}
# Use same helpers if exported - otherwise Bridge.load_project
{:ok, project} = Bridge.load_project(fixture, lowerer_diagnostics: true)
IO.puts("project opts path")

{:ok, ir0} = Lowerer.lower_project(project)
ir1 = PipeChain.desugar_project(ir0)
dump = fn ir, label ->
  mod = Enum.find(ir.modules, &(&1.name == "Pkg.elm_random_1_0_0.Random"))
  d = Enum.find(mod.declarations, &(&1.name == "getByWeight"))
  IO.puts("#{label}: args=#{inspect(d.args)} subject=#{inspect(Map.get(d.expr, :subject))} op=#{d.expr.op}")
end
dump.(ir0, "after lower")
dump.(ir1, "after pipe")

# Check if CCodegen mutates IR
out = Path.expand("../test/tmp/probe_gbw5", __DIR__)
File.rm_rf!(out)
# Call codegen like compile does
:ok = Elmc.Backend.CCodegen.GeneratedSource # warmup
# Use public compile path pieces
alias Elmc.Backend.CCodegen.IRQueries
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir1))
# Write artifacts
case Elmc.Backend.CCodegen.write_project(ir1, out, "Main", %{plan_ir_mode: :primary, plan_ir_strict: true, entry_module: "Main", strip_dead_code: false}) do
  {:ok, _} -> :ok
  other -> IO.inspect(other, label: "write_project")
end
dump.(ir1, "after write_project (same ir1)")

# Also find write API
