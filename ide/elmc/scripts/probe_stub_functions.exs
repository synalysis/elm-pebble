alias Elmc.Backend.Plan.Lower.{Function, Lambda}
alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.CCodegen.{IRQueries, VarAnalysis}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
decl_map = IRQueries.function_decl_map(ir)

probe = fn mod, name ->
  decl = Map.fetch!(decl_map, {mod, name})
  IO.puts("\n=== #{mod}.#{name} ===")
  IO.inspect(decl.expr, limit: 8, printable_limit: 400)

  case Function.lower(decl, mod, decl_map) do
    {:ok, plan} ->
      IO.puts("OK blocks=#{length(plan.blocks)} lambdas=#{length(plan.lambdas)}")

    :unsupported ->
      reason = Process.get(:elmc_plan_unsupported_reasons, %{}) |> Map.get({mod, name})
      IO.puts("unsupported reason=#{inspect(reason)}")
  end
end

probe.("Pages.Internal.Platform", "startNewGetLoad")
probe.("RouteBuilder", "buildNoState")
probe.("Parser.Advanced", "map2")

decl = Map.fetch!(decl_map, {"RouteBuilder", "buildNoState"})
body = decl.expr

case body do
  %{op: :lambda, args: args, body: inner} ->
    free = VarAnalysis.lambda_capture_free_vars(inner, args)
    IO.puts("buildNoState lambda free=#{inspect(MapSet.to_list(free))}")

    ctx = Context.new(module: "RouteBuilder", function_name: "buildNoState", params: args, decl_map: decl_map)
    b = Builder.new("RouteBuilder", "buildNoState", args: args)

    case Lambda.compile(body, ctx, b) do
      {:ok, _, b1} -> IO.puts("buildNoState lambda compile OK nested=#{length(b1.lambdas)}")
      :unsupported -> IO.puts("buildNoState lambda compile unsupported")
    end

  other ->
    IO.puts("buildNoState not top lambda: #{inspect(other.op)}")
end
