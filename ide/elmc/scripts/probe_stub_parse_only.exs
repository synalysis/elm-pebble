alias Elmc.Backend.CCodegen.IRQueries
alias ElmEx.Frontend.Bridge
alias ElmEx.IR.{DeadCode, Lowerer}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = Bridge.load_project(app)
{:ok, ir0} = Lowerer.lower_project(project)
ir = DeadCode.strip(ir0, "Main")
decl_map = IRQueries.function_decl_map(ir)

for {mod, name} <- [
      {"QueryParams", "addParam"},
      {"Route", "segmentsToRoute"},
      {"Head.Twitter", "rawTags"},
      {"Internal.Svg", "box"}
    ] do
  IO.puts("\n=== #{mod}.#{name} ===")

  case Map.fetch(decl_map, {mod, name}) do
    :error ->
      IO.puts("missing from decl_map")

    {:ok, decl} ->
      case decl.expr do
        %{op: :unsupported} = expr ->
          IO.puts("FAIL unsupported reason=#{inspect(expr.reason, limit: 3)}")

        %{op: op} ->
          IO.puts("OK op=#{op}")

        other ->
          IO.puts("FAIL expr=#{inspect(other, limit: 2)}")
      end
  end
end
