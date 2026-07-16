alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.{Case, Expr, Function, PatternBind}
alias Elmc.Backend.Plan.Lower.Case.TagSwitch

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))
Process.put(:elmc_module_ports, Elmc.Backend.CCodegen.IRQueries.module_ports_map(ir))

ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update",
    params: Map.get(decl, :args, []),
    decl_map: decl_map,
    fallible: true
  )

b = Builder.new("Pages.Internal.Platform", "update", args: ctx.params, fallible: true)

Enum.with_index(decl.expr.branches)
|> Enum.each(fn {branch, idx} ->
  Process.delete(:elmc_plan_unsupported_reasons)

  case TagSwitch.compile(%{op: :var, name: "appMsg"}, [branch], ctx, b) do
    {:ok, _, _} ->
      IO.puts("arm #{idx} OK")

    :unsupported ->
      IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "arm #{idx} FAIL")
  end
end)

Process.delete(:elmc_plan_unsupported_reasons)
arm = Enum.at(decl.expr.branches, 3)

case PatternBind.bind(arm.pattern, Context.for_branch_arm(ctx), b, 42) do
  {:ok, arm_ctx, _} ->
    Process.delete(:elmc_plan_unsupported_reasons)

    case Expr.compile(arm.expr, arm_ctx, b) do
      {:ok, _, _} -> IO.puts("FetcherComplete body OK after bind")
      :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "FetcherComplete body FAIL")
    end

  other ->
    IO.inspect(other, label: "FetcherComplete PatternBind")
end

Process.delete(:elmc_plan_unsupported_reasons)

case Case.compile(decl.expr, ctx, b) do
  {:ok, _, _} -> IO.puts("Case.compile full OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "Case.compile full FAIL")
end
