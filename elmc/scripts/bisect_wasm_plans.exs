alias Elmc.Backend.CCodegen.{IRQueries, RcRequired}
alias Elmc.Backend.Plan
alias Elmc.Backend.Wasm.WebCoverage

app = Path.expand("../../elm_pebble_dev", __DIR__)

{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")

opts = %{web: true, entry_module: "Main", strip_dead_code: true, plan_ir_mode: :primary}

Process.put(:elmc_codegen_opts, opts)
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
Process.put(:elmc_module_ports, IRQueries.module_ports_map(ir))
Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

decl_map = IRQueries.function_decl_map(ir)

coverage_opts = [
  entry_module: "Main",
  strip_dead_code: true,
  plan_ir_mode: :primary,
  web: true
]

emit_map = WebCoverage.filter_reachable(decl_map, coverage_opts)
sorted = emit_map |> Map.keys() |> Enum.sort()
IO.puts("emit count=#{length(sorted)}")

Enum.with_index(sorted)
|> Enum.each(fn {{mod, name}, idx} ->
  if rem(idx, 25) == 0 do
    total = div(:erlang.memory(:total), 1_000_000)
    IO.puts("[#{idx}/#{length(sorted)}] mem=#{total}MB next=#{mod}.#{name}")
  end

  decl = Map.fetch!(emit_map, {mod, name})
  rc? = RcRequired.rc_required?(mod, name)
  Process.delete(:elmc_plan_unsupported_reasons)

  case Plan.lower_function(decl, mod, decl_map, rc_required: rc?) do
    {:ok, plan} ->
      blocks = length(plan.blocks)
      lambdas = length(plan.lambdas || [])

      if blocks > 150 or String.contains?(name, "update") or String.contains?(name, "loadData") do
        IO.puts("  large #{mod}.#{name} blocks=#{blocks} lambdas=#{lambdas}")
      end

    other ->
      IO.puts("  skip #{mod}.#{name} #{inspect(other)}")
  end
end)

IO.puts("all plans lowered OK")
