alias Elmc.Backend.CCodegen.{IRQueries, RcRequired}
alias Elmc.Backend.Plan
alias ElmEx.Frontend.Bridge
alias ElmEx.IR.{DeadCode, Lowerer, PipeChain}

app = Path.expand("../../elm_pebble_dev", __DIR__)

{:ok, project} = Bridge.load_project(app)
{:ok, ir0} = Lowerer.lower_project(project)
ir = ir0 |> PipeChain.desugar_project() |> DeadCode.strip("Main")
decl_map = IRQueries.function_decl_map(ir)

Process.put(:elmc_codegen_opts, %{
  web: true,
  entry_module: "Main",
  strip_dead_code: true,
  plan_ir_mode: :primary
})

Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
Process.put(:elmc_module_ports, IRQueries.module_ports_map(ir))
Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))
Process.put(:elmc_union_constructor_payload_specs, IRQueries.union_constructor_payload_specs_map(ir))
Process.put(:elmc_program_decls, decl_map)

for {mod, name} <- [
      {"Internal.Cartesian.Layout", "layout"},
      {"Pages.Internal.Platform", "update"},
      {"Pkg.justinmimbs_date_4_1_0.Pattern", "finalize"}
    ] do
  IO.puts("\n=== #{mod}.#{name} ===")
  Process.delete(:elmc_plan_unsupported_reasons)

  case Map.fetch(decl_map, {mod, name}) do
    :error ->
      IO.puts("missing from decl_map")

    {:ok, decl} ->
      IO.puts("expr op=#{inspect(decl.expr && decl.expr.op)}")

      if decl.expr && decl.expr.op == :unsupported do
        IO.inspect(decl.expr, limit: 4)
      end

      rc? = RcRequired.rc_required?(mod, name)

      case Plan.lower_function(decl, mod, decl_map, rc_required: rc?) do
        {:ok, plan} ->
          IO.puts("plan OK blocks=#{length(plan.blocks)}")

        :unsupported ->
          IO.puts(
            "plan unsupported reason=#{inspect(Process.get(:elmc_plan_unsupported_reasons, %{}) |> Map.get({mod, name}), limit: 4)}"
          )

        other ->
          IO.puts("plan error #{inspect(other, limit: 3)}")
      end
  end
end
