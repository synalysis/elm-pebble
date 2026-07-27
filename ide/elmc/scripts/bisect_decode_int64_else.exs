alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.Expr
alias Elmc.Backend.CCodegen.IRQueries

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
decl_map = IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Lamdera.Wire3", "decodeInt64"})
body = hd(decl.expr.in_expr.args).body

ctx =
  Context.new(
    module: "Lamdera.Wire3",
    function_name: "probe",
    params: ["n0", "d", "unsignedToSigned"],
    decl_map: decl_map
  )

b = Builder.new("Lamdera.Wire3", "probe", args: ctx.params)

test = fn label, expr ->
  IO.puts("compile #{label}...")

  case Expr.compile(expr, ctx, b) do
    {:ok, _, b1} -> IO.puts("  OK lambdas=#{length(b1.lambdas)}")
    :unsupported -> IO.puts("  unsupported")
  end
end

else_expr = body.else_expr
test.("else", else_expr)

if match?(%{op: :if}, else_expr) do
  test.("else.then", else_expr.then_expr)
  test.("else.else", else_expr.else_expr)
end
