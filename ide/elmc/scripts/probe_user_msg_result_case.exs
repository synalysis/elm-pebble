alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.{Case, Expr, PatternBind}
alias Elmc.Backend.Plan.Lower.Case.{GuardedSwitch, TagSwitch}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))

arm = Enum.at(decl.expr.branches, 3)
user_case = arm.expr

IO.puts("userMsgResult case branches: #{length(user_case.branches)}")
IO.puts("TagSwitch? #{TagSwitch.branches?(user_case.branches)}")
IO.puts("GuardedSwitch? #{GuardedSwitch.branches?(user_case.branches)}")

ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update",
    params: Map.get(decl, :args, []) ++ ["fetcherKey", "userMsgResult"],
    decl_map: decl_map
  )

b = Builder.new("Pages.Internal.Platform", "update", args: ctx.params)

Process.delete(:elmc_plan_unsupported_reasons)

case Case.compile(user_case, ctx, b) do
  {:ok, _, _} -> IO.puts("userMsgResult Case.compile OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "userMsgResult Case.compile FAIL")
end

ok_arm = hd(user_case.branches)
Process.delete(:elmc_plan_unsupported_reasons)

case PatternBind.bind(ok_arm.pattern, Context.for_branch_arm(ctx), b, 77) do
  {:ok, ok_ctx, _} ->
    case Expr.compile(ok_arm.expr, ok_ctx, b) do
      {:ok, _, _} -> IO.puts("Ok arm body OK after PatternBind")
      :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "Ok arm body FAIL")
    end

  other ->
    IO.inspect(other, label: "Ok PatternBind")
end

Process.delete(:elmc_plan_unsupported_reasons)

case TagSwitch.compile(%{op: :var, name: "userMsgResult"}, user_case.branches, ctx, b) do
  {:ok, _, _} -> IO.puts("userMsgResult TagSwitch OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "userMsgResult TagSwitch FAIL")
end
