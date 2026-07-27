# Usage: mix run scripts/probe_compile_phases.exs
alias Elmc.Backend.CCodegen.{GeneratedSource, IRQueries}
alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
alias ElmEx.IR.Lowerer
alias ElmEx.Frontend.Bridge

project_dir = Path.expand("test/tmp/plan_fold_probe")
opts = %{entry_module: "Main", strip_dead_code: false}

IO.puts("load+lower")
{:ok, project} = Bridge.load_project(project_dir)
{:ok, ir} = Lowerer.lower_project(project)
decl_map = IRQueries.function_decl_map(ir)
generic_targets = GenericTargets.function_targets(ir, opts)
IO.puts("decls=#{map_size(decl_map)} targets=#{MapSet.size(generic_targets)}")

{us, _} = :timer.tc(fn -> GeneratedSource.prepare_emit_session!(ir, opts) end)
IO.puts("prepare_emit_session #{div(us, 1000)}ms")

{us2, source} =
  :timer.tc(fn ->
    GeneratedSource.source(ir, opts)
  end)

IO.puts("source #{div(us2, 1000)}ms bytes=#{byte_size(source)}")
