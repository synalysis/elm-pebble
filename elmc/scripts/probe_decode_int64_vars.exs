alias Elmc.Backend.CCodegen.VarAnalysis

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")

decl =
  ir.modules
  |> Enum.find(&(&1.name == "Lamdera.Wire3"))
  |> then(fn m -> Enum.find(m.declarations, &(&1.name == "decodeInt64")) end)

IO.puts("used_vars count=#{VarAnalysis.used_vars(decl.expr) |> MapSet.size()}")

lam = decl.expr.in_expr
IO.inspect(lam.args, label: "lambda args")

fv = VarAnalysis.lambda_capture_free_vars(lam.body, lam.args)
IO.puts("capture free vars count=#{MapSet.size(fv)}")
IO.puts("sample=#{inspect(MapSet.to_list(fv) |> Enum.take(10))}")
