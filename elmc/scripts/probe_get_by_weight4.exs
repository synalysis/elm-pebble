alias ElmEx.IR.FnArgDesugar
alias Elmc.Backend.CCodegen.IRQueries

fixture = Path.expand("../test/fixtures/simple_project", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(fixture)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
mod = Enum.find(ir0.modules, &(&1.name == "Pkg.elm_random_1_0_0.Random"))
raw = Enum.find(mod.declarations, &(&1.name == "getByWeight"))
IO.puts("Bridge+Lowerer args=#{inspect(raw.args)}")
IO.puts("subject=#{inspect(get_in(raw.expr, [:subject]))}")

# Full compile IR from previous out_dir
# Re-read by compiling with dump — check lowerer cache
cache_info = Application.get_env(:elm_ex, :ir_cache)
IO.inspect(cache_info, label: "cache env")

# Check what args look like in AST before IR desugar
# Find Random source module in project
mods = Map.get(project, :modules) || project.modules
random_mods =
  Enum.filter(mods, fn m ->
    n = to_string(Map.get(m, :name) || "")
    String.contains?(n, "Random") or String.contains?(n, "random")
  end)
IO.puts("random-like modules: #{inspect(Enum.map(random_mods, & &1.name))}")

Enum.each(random_mods, fn m ->
  decls = Map.get(m, :declarations) || Map.get(m, :decls) || []
  g = Enum.find(List.wrap(decls), fn d -> (Map.get(d, :name) || "") == "getByWeight" end)
  if g do
    IO.puts("AST #{m.name}.getByWeight args=#{inspect(Map.get(g, :args))}")
  end
end)

IO.inspect(FnArgDesugar.desugar_args(["(weight, value)", "others", "countdown"], %{op: :int_literal, value: 1}), label: "desugar tuple")

# How does Elmc.compile IR differ? Check if there's a post-pass
# Look at result from tmp probe_gbw if still there - dump via loading bytecode? 
# Instead lower again with same opts as compile

Code.require_file("lib/elmc.ex") # already loaded
out = Path.expand("../test/tmp/probe_gbw2", __DIR__)
File.rm_rf!(out)
{:ok, result} = Elmc.compile(fixture, %{out_dir: out, entry_module: "Main", strip_dead_code: false, plan_ir_mode: :primary, plan_ir_strict: true})
decl = result.ir.modules |> Enum.find(&(&1.name == "Pkg.elm_random_1_0_0.Random")) |> then(fn m -> Enum.find(m.declarations, &(&1.name == "getByWeight")) end)
IO.puts("COMPILE args=#{inspect(decl.args)}")
IO.puts("COMPILE subject=#{inspect(Map.get(decl.expr, :subject))}")

# Diff: check if PipeChain or something else changes args — compare ir before codegen
# Instrument: dump from Lowerer with cache disabled
