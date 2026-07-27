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
emit_map = WebCoverage.filter_reachable(decl_map, entry_module: "Main", strip_dead_code: true, plan_ir_mode: :primary, web: true)
sorted = emit_map |> Map.keys() |> Enum.sort()

from = String.to_integer(System.get_env("FROM") || "225")
to = String.to_integer(System.get_env("TO") || "260")

IO.puts("lowering #{from}..#{to} of #{length(sorted)}")

for idx <- from..to do
  {mod, name} = Enum.at(sorted, idx)
  decl = Map.fetch!(emit_map, {mod, name})
  rc? = RcRequired.rc_required?(mod, name)
  Process.delete(:elmc_plan_unsupported_reasons)
  before = :erlang.memory(:total)

  result =
    try do
      Plan.lower_function(decl, mod, decl_map, rc_required: rc?)
    catch
      :exit, reason -> {:exit, reason}
    end

  after_mem = :erlang.memory(:total)
  delta = after_mem - before

  case result do
    {:ok, plan} ->
      IO.puts(
        "[#{idx}] OK #{mod}.#{name} blocks=#{length(plan.blocks)} lambdas=#{length(plan.lambdas || [])} delta=#{div(delta, 1_000_000)}MB total=#{div(after_mem, 1_000_000)}MB"
      )

    other ->
      IO.puts("[#{idx}] FAIL #{mod}.#{name} #{inspect(other)} delta=#{div(delta, 1_000_000)}MB")
  end
end
