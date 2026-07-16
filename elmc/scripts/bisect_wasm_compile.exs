alias Elmc.Backend.CCodegen.{IRQueries, RcRequired}
alias Elmc.Backend.Plan
alias Elmc.Backend.Wasm.{Module, WebCoverage}

app = Path.expand("../../elm_pebble_dev", __DIR__)

{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")

opts = %{
  web: true,
  entry_module: "Main",
  strip_dead_code: true,
  plan_ir_mode: :primary
}

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

lower_one = fn {mod, name}, decl ->
  rc? = RcRequired.rc_required?(mod, name)

  case Plan.lower_function(decl, mod, decl_map, rc_required: rc?) do
    {:ok, plan} when plan.blocks != [] ->
      {:ok, plan}

    {:ok, _empty} ->
      :skip

    other ->
      other
  end
end

{plans, skips} =
  Enum.reduce(sorted, {[], 0}, fn key, {acc, skip_n} ->
    {mod, name} = key
    decl = Map.fetch!(emit_map, key)

    case lower_one.(key, decl) do
      {:ok, plan} ->
        blocks = length(plan.blocks)
        lambdas = length(plan.lambdas || [])

        if String.contains?(mod, "Platform") or blocks > 100 do
          IO.puts("plan OK #{mod}.#{name} blocks=#{blocks} lambdas=#{lambdas}")
        end

        {[plan | acc], skip_n}

      _ ->
        {acc, skip_n + 1}
    end
  end)

plans = Enum.reverse(plans)
IO.puts("plans=#{length(plans)} skips=#{skips}")
mem = fn label -> IO.puts("#{label}: total=#{div(elem(:erlang.memory(:total), 1), 1_000_000)}MB") end
mem.("after plans")

IO.puts("Module.build all...")
module_map = Module.build(plans, export_all: true, entry_exports: ["Main$main"])
mem.("after build")

wat = Map.get(module_map, :wat, "")
IO.puts("wat bytes=#{byte_size(wat)} functions=#{length(module_map.functions)}")
mem.("done")

# Incremental bisect if build succeeds
if byte_size(wat) > 0 do
  IO.puts("incremental build bisect (last plan only)...")

  last = List.last(plans)
  _ = Module.build([last], export_all: true)
  IO.puts("single last plan OK: #{last.module}.#{last.name}")
end
