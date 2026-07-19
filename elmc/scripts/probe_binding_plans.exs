# Usage: mix run scripts/probe_binding_plans.exs
alias Elmc.Backend.CCodegen.{BindingPlans, SchemaRegistry, IRQueries, LayoutSolver, ListIntRepr, ListRecordRepr}
alias ElmEx.IR.Lowerer
alias ElmEx.Frontend.Bridge

minimal_json = Jason.encode!(%{
  "type" => "application",
  "source-directories" => ["src"],
  "elm-version" => "0.19.1",
  "dependencies" => %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}}
})

source = """
module Main exposing (board, len)

board : List Int
board =
    List.repeat 140 0

len : Int
len =
    List.length board
"""

project_dir = Path.expand("test/tmp/plan_fold_probe", __DIR__)
File.rm_rf!(project_dir)
File.mkdir_p!(Path.join(project_dir, "src"))
File.write!(Path.join(project_dir, "src/Main.elm"), source)
File.write!(Path.join(project_dir, "elm.json"), minimal_json <> "\n")

IO.puts("loading…")
{:ok, project} = Bridge.load_project(project_dir)
IO.puts("lowering…")
{:ok, ir} = Lowerer.lower_project(project)
decl_map = IRQueries.function_decl_map(ir)
IO.puts("decls=#{map_size(decl_map)}")

sr = SchemaRegistry.build(ir)

for {label, fun} <- [
      {"ListIntRepr.analyze", fn -> ListIntRepr.analyze(decl_map) end},
      {"ListIntRepr.analyze_float", fn -> ListIntRepr.analyze_float(decl_map) end},
      {"ListRecordRepr.analyze", fn -> ListRecordRepr.analyze(decl_map, sr) end},
      {"BindingPlans.analyze", fn -> BindingPlans.analyze(decl_map, sr) end},
      {"LayoutSolver.analyze", fn -> LayoutSolver.analyze(decl_map, sr) end}
    ] do
  {us, _result} = :timer.tc(fun)
  IO.puts("#{label} #{div(us, 1000)}ms")
end
