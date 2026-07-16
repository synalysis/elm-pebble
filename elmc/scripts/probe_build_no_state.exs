alias Elmc.Backend.Plan.Lower.Lambda
alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.CCodegen.IRQueries

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
decl_map = IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"RouteBuilder", "buildNoState"})

body = decl.expr
%{op: :lambda, args: args, body: inner} = body

IO.inspect(inner, limit: :infinity, printable_limit: :infinity)

ctx = Context.new(module: "RouteBuilder", function_name: "buildNoState", params: args, decl_map: decl_map)
b = Builder.new("RouteBuilder", "buildNoState", args: args)

case Lambda.compile(body, ctx, b) do
  {:ok, _, b1} -> IO.puts("OK lambdas=#{length(b1.lambdas)}")
  :unsupported ->
    reasons = Process.get(:elmc_plan_unsupported_reasons, %{})
    IO.inspect(reasons, limit: :infinity)
end
