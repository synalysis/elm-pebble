alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.Expr
alias Elmc.Backend.Plan.Lower.Case.TagSwitch

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))

user_case = Enum.at(decl.expr.branches, 3).expr
ok_branch = hd(user_case.branches)

ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update",
    params: Map.get(decl, :args, []) ++ ["fetcherKey", "userMsgResult"],
    decl_map: decl_map
  )

b = Builder.new("Pages.Internal.Platform", "update", args: ctx.params)
branch_ctx = Context.for_branch_arm(ctx)

{:ok, subj_reg, b1} = Expr.compile(%{op: :var, name: "userMsgResult"}, ctx, b)
IO.puts("userMsgResult reg=#{subj_reg}")

# invoke private via apply on TagSwitch - use compile_one_arm path through TagSwitch module
pattern = Map.get(ok_branch, :pattern, %{})
expr = Map.get(ok_branch, :expr)

arm_ctx_result =
  TagSwitch.__info__(:functions)
  |> IO.inspect(label: "TagSwitch exports")

Process.delete(:elmc_plan_unsupported_reasons)

case TagSwitch.compile(%{op: :var, name: "userMsgResult"}, [ok_branch], ctx, b) do
  {:ok, _, _} -> IO.puts("single Ok TagSwitch OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "single Ok TagSwitch FAIL")
end

stripped_pat = %{
  kind: :constructor,
  arg_pattern: pattern.arg_pattern,
  name: pattern.name,
  tag: pattern.tag,
  resolved_name: pattern.resolved_name
}

{:ok, arm_ctx, b_arm} =
  Elmc.Backend.Plan.Lower.PatternBind.bind(stripped_pat, branch_ctx, b1, subj_reg)

IO.inspect(Map.keys(arm_ctx.locals), label: "arm_ctx locals after bind")

Process.delete(:elmc_plan_unsupported_reasons)

case Expr.compile(expr, arm_ctx, b_arm) do
  {:ok, _, _} -> IO.puts("manual compile_one_arm path OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "manual compile_one_arm FAIL")
end

# inner actionOrRedirect case alone
inner_case = expr
Process.delete(:elmc_plan_unsupported_reasons)

ctx2 =
  ctx
  |> Context.put_local("userMsg", 10)
  |> Context.put_local("actionOrRedirect", 11)

case Expr.compile(inner_case, Context.for_branch_arm(ctx2), b) do
  {:ok, _, _} -> IO.puts("inner case OK with fake locals")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "inner case FAIL with fake locals")
end
