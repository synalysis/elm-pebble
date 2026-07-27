alias Elmc.Backend.CCodegen.IRQueries
alias Elmc.Backend.Plan.Lower.Function, as: LowerFunction
alias ElmEx.Frontend.Bridge
alias ElmEx.IR.{DeadCode, Lowerer}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = Bridge.load_project(app)
{:ok, ir0} = Lowerer.lower_project(project)
ir = DeadCode.strip(ir0, "Main")
decl_map = IRQueries.function_decl_map(ir)

probe = fn mod, name ->
  IO.puts("\n=== #{mod}.#{name} ===")

  case Map.fetch(decl_map, {mod, name}) do
    :error ->
      IO.puts("missing from decl_map")

    {:ok, decl} ->
      IO.inspect(decl.expr, limit: 6, printable_limit: 300)

      case LowerFunction.lower(decl, mod, decl_map) do
        {:ok, plan} ->
          IO.puts("plan OK blocks=#{length(plan.blocks)}")

        :unsupported ->
          reason = Process.get(:elmc_plan_unsupported_reasons, %{}) |> Map.get({mod, name})
          IO.puts("plan unsupported reason=#{inspect(reason, limit: 6)}")
      end
  end
end

probe.("QueryParams", "addParam")
probe.("Route", "segmentsToRoute")
probe.("Head.Twitter", "rawTags")
probe.("Internal.Svg", "box")
