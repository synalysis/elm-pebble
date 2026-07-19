alias Elmc.Backend.CCodegen.IRQueries
alias ElmEx.Frontend.Bridge
alias ElmEx.IR.{DeadCode, Lowerer}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = Bridge.load_project(app)
{:ok, ir0} = Lowerer.lower_project(project)
ir = DeadCode.strip(ir0, "Main")
decl_map = IRQueries.function_decl_map(ir)

for {mod, name} <- [
      {"Internal.Cartesian.Layout", "layout"},
      {"Pages.Internal.Platform", "update"},
      {"Pkg.justinmimbs_date_4_1_0.Pattern", "finalize"}
    ] do
  IO.puts("\n=== #{mod}.#{name} ===")

  case Map.fetch(decl_map, {mod, name}) do
    :error ->
      IO.puts("missing")

    {:ok, decl} ->
      case decl.expr do
        %{op: :unsupported} = expr ->
          IO.puts("unsupported reason=#{Map.get(expr, :reason) || Map.get(expr, "reason")}")
          src = Map.get(expr, :source) || Map.get(expr, "source")
          if is_binary(src), do: IO.puts(String.slice(src, 0, 800))

        %{op: op} ->
          IO.puts("OK op=#{op}")
      end
  end
end
