alias ElmEx.Frontend.Bridge
alias ElmEx.IR.Lowerer
alias Elmc.Backend.CCodegen.IRQueries
alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
alias Elmc.Backend.Plan.Verify

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, p} = Bridge.load_project(app)
{:ok, ir} = Lowerer.lower_project(p)
decl_map = IRQueries.function_decl_map(ir)
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))
Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

decl = Map.fetch!(decl_map, {"Route.Index", "view"})

case PlanLower.lower(decl, "Route.Index", decl_map, rc_required: false) do
  {:ok, plan} ->
    case Verify.run(plan) do
      :ok -> IO.puts("verify ok")
      {:error, e} -> IO.inspect(e, label: "verify error")
    end

    # reg 2 liveness
    alias Elmc.Backend.Plan.Allocate
    {slots, _} = Allocate.run(plan)
    IO.inspect(Map.get(slots, 2), label: "reg2 slot")

  other ->
    IO.inspect(other)
end
