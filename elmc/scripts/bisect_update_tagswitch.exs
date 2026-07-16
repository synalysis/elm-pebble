alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.Case.TagSwitch

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))

decl =
  ir.modules
  |> Enum.find(&(&1.name == "Pages.Internal.Platform"))
  |> then(fn m -> Enum.find(m.declarations, &(&1.name == "update")) end)

branches = decl.expr.branches
wildcard = List.last(branches)
tagged = Enum.drop(branches, -1)

ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update",
    params: ["config", "appMsg", "model"],
    decl_map: %{}
  )

b = Builder.new("Pages.Internal.Platform", "update", args: ["config", "appMsg", "model"])

Enum.reduce(1..length(tagged), :ok, fn n, _ ->
  subset = Enum.take(tagged, n) ++ [wildcard]

  Process.delete(:elmc_plan_unsupported_reasons)

  case TagSwitch.compile(%{op: :var, name: "appMsg"}, subset, ctx, b) do
    {:ok, _, _} ->
      label = n |> then(&Enum.at(tagged, &1 - 1)) |> Map.get(:pattern) |> Map.get(:name)
      IO.puts("OK through arm #{n - 1} (#{label})")
      :ok

    :unsupported ->
      label = n |> then(&Enum.at(tagged, &1 - 1)) |> Map.get(:pattern) |> Map.get(:name)
      IO.puts("FAIL at arm #{n - 1} (#{label})")
      IO.inspect(Process.get(:elmc_plan_unsupported_reasons))
      :halt
  end
end)
