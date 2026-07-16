alias Elmc.Backend.CCodegen.VarAnalysis

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")

decl =
  ir.modules
  |> Enum.find(&(&1.name == "Pages.Internal.Platform"))
  |> then(fn m -> Enum.find(m.declarations, &(&1.name == "update")) end)

inner = hd(Enum.at(decl.expr.branches, 3).expr.branches).expr
action = Enum.find(inner.branches, fn b -> Map.get(b.pattern, :name) == "ActionResponse" end)

find_lambdas = fn node ->
  walk = fn
    g, %{op: :lambda} = lam ->
      [lam | Enum.flat_map(lam, fn {_, v} -> g.(g, v) end)]

    g, m when is_map(m) ->
      Enum.flat_map(m, fn {_, v} -> g.(g, v) end)

    g, l when is_list(l) ->
      Enum.flat_map(l, fn v -> g.(g, v) end)

    _g, _ ->
      []
  end

  walk.(walk, node)
end

lams = find_lambdas.(action.expr)
IO.puts("lambda count #{length(lams)}")
Enum.each(lams, fn lam -> IO.inspect(lam.args, label: "lambda args") end)

lam = Enum.find(lams, fn %{args: args} -> args == ["tupleArg"] end) || hd(lams)
IO.inspect(VarAnalysis.lambda_capture_free_vars(lam.body, lam.args) |> MapSet.to_list(), label: "tupleArg free vars")
IO.inspect(VarAnalysis.used_vars(lam.body) |> MapSet.to_list() |> Enum.sort(), label: "tupleArg used vars")
