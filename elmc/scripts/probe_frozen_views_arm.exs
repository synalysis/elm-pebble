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

arm = Enum.at(decl.expr.branches, 10)
IO.puts("FrozenViewsReady arm pattern: #{inspect(Map.get(arm.pattern, :name))}")
IO.inspect(arm.pattern, label: "pattern", limit: :infinity)
IO.inspect(arm.expr, label: "expr", limit: 80)

ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update",
    params: Map.get(decl, :args, []) ++ ["pageDataBytes"],
    decl_map: decl_map,
    fallible: true
  )

b = Builder.new("Pages.Internal.Platform", "update", args: ctx.params, fallible: true)

Process.delete(:elmc_plan_unsupported_reasons)

case Case.compile(arm.expr, Context.for_branch_arm(ctx), b) do
  {:ok, _, _} -> IO.puts("FrozenViewsReady body Case.compile OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "FrozenViewsReady body FAIL")
end

Process.delete(:elmc_plan_unsupported_reasons)

case Function.lower(
       %{decl | expr: arm.expr, name: "frozen_probe", args: Map.get(decl, :args, []) ++ ["pageDataBytes"]},
       "Pages.Internal.Platform",
       decl_map,
       [],
       rc_required: true
     ) do
  {:ok, plan} ->
    IO.puts("Function.lower OK blocks=#{length(plan.blocks)}")

    instrs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)

    IO.puts("forward_ref_load count: #{Enum.count(instrs, &(&1.op == :forward_ref_load))}")
    IO.puts("forward_ref_set count: #{Enum.count(instrs, &(&1.op == :forward_ref_set))}")

    Enum.filter(instrs, &(&1.op == :forward_ref_load))
    |> Enum.take(10)
    |> IO.inspect(label: "sample forward_ref_loads")

  other ->
    IO.inspect(other, label: "Function.lower")
    IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "fail reasons")
end
