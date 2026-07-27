alias Elmc.Backend.Plan.Lower.Function
alias Elmc.Backend.CCodegen.IRQueries

fixture = Path.expand("../test/fixtures/simple_project", __DIR__)
IO.puts("fixture=#{fixture}")
{:ok, project} = ElmEx.Frontend.Bridge.load_project(fixture)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project()
decl_map = IRQueries.function_decl_map(ir)
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
Process.put(:elmc_module_ports, IRQueries.module_ports_map(ir))
Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

keys =
  decl_map
  |> Map.keys()
  |> Enum.filter(fn {_m, n} -> n in ["getByWeight", "pickWeighted", "weighted"] end)
  |> Enum.sort()

IO.inspect(keys, label: "matching keys")

Enum.each(keys, fn {mod, name} = key ->
  decl = Map.fetch!(decl_map, key)
  IO.puts("\n=== #{mod}.#{name} ===")
  IO.puts("args=#{inspect(Map.get(decl, :args))}")
  IO.puts("type=#{inspect(Map.get(decl, :type))}")
  IO.inspect(Map.get(decl, :expr), label: "expr", pretty: true, limit: 50, printable_limit: 2000)

  Process.put(:elmc_plan_unsupported_reasons, %{})
  result = Function.lower(decl, mod, decl_map, rc_required: true)
  IO.inspect(result |> then(fn
    {:ok, plan} -> {:ok, length(plan.blocks), Map.keys(plan) |> Enum.take(12)}
    other -> other
  end), label: "lower(rc=true)")
  IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "reasons")
end)
