alias ElmEx.Frontend.Bridge
alias ElmEx.IR.Lowerer
alias Elmc.Backend.CCodegen.IRQueries
alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
alias Elmc.Backend.Plan.Debug

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, p} = Bridge.load_project(app)
{:ok, ir} = Lowerer.lower_project(p)
decl_map = IRQueries.function_decl_map(ir)
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))
Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

for {mod, fun} <- [{"Shared", "view"}, {"Route.Index", "view"}] do
  decl = Map.fetch!(decl_map, {mod, fun})

  case PlanLower.lower(decl, mod, decl_map, rc_required: false) do
    {:ok, plan} ->
      dump = Debug.dump(plan)
      IO.puts("=== #{mod}.#{fun} ===")
      IO.puts(dump)

      for line <- String.split(dump, "\n"), String.contains?(line, "title") or String.contains?(line, "record_get") do
        IO.puts(line)
      end

    other ->
      IO.inspect(other, label: "#{mod}.#{fun}")
  end
end
