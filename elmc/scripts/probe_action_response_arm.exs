alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.{Case, Expr, PatternBind}
alias Elmc.Backend.Plan.Lower.Case.TagSwitch

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))

fetcher = Enum.at(decl.expr.branches, 3)
ok_body = hd(fetcher.expr.branches).expr
action_arm = hd(ok_body.branches)

params =
  Map.get(decl, :args, []) ++
    ["fetcherKey", "userMsgResult", "userMsg", "actionOrRedirect", "maybeFetcherDoneActionData"]

ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update",
    params: params,
    decl_map: decl_map,
    fallible: true
  )

b = Builder.new("Pages.Internal.Platform", "update", args: ctx.params, fallible: true)

Process.delete(:elmc_plan_unsupported_reasons)

case TagSwitch.compile(%{op: :var, name: "actionOrRedirect"}, [action_arm], ctx, b) do
  {:ok, _, _} -> IO.puts("ActionResponse TagSwitch OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "ActionResponse TagSwitch FAIL")
end

Process.delete(:elmc_plan_unsupported_reasons)

case PatternBind.bind(action_arm.pattern, Context.for_branch_arm(ctx), b, 88) do
  {:ok, arm_ctx, b1} ->
    IO.inspect(Map.keys(arm_ctx.locals), label: "ActionResponse locals")

    case Expr.compile(action_arm.expr, arm_ctx, b1) do
      {:ok, _, _} -> IO.puts("ActionResponse body OK")
      :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "ActionResponse body FAIL")
    end

  other ->
    IO.inspect(other, label: "ActionResponse PatternBind")
end

Process.delete(:elmc_plan_unsupported_reasons)

case Case.compile(ok_body, ctx, b) do
  {:ok, _, _} -> IO.puts("actionOrRedirect case OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "actionOrRedirect case FAIL")
end
