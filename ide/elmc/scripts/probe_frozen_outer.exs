app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl = Map.fetch!(Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir), {"Pages.Internal.Platform", "update"})
arm = Enum.at(decl.expr.branches, 10)

outer = arm.expr.in_expr
Enum.with_index(outer.branches)
|> Enum.each(fn {br, i} ->
  IO.puts("\n=== outer arm #{i} ===")
  IO.inspect(br.pattern, limit: :infinity)
end)

find = fn expr ->
  f = fn g, x ->
    case x do
      %{op: :case, branches: branches} ->
        case Enum.find(branches, fn br ->
               br.pattern[:tag] == 2 and is_binary(br.pattern[:name]) and
                 String.contains?(br.pattern[:name], "HotUpdate")
             end) do
          nil -> Enum.find_value(x, &g.(g, &1))
          br -> br
        end

      m when is_map(m) -> Enum.find_value(m, &g.(g, &1))
      l when is_list(l) -> Enum.find_value(l, &g.(g, &1))
      _ -> nil
    end
  end

  f.(f, expr)
end

hot = find.(arm.expr)
IO.puts("\n=== HotUpdate pattern ===")
IO.inspect(hot.pattern, limit: :infinity)

find_rec = fn expr ->
  f = fn g, x ->
    case x do
      %{op: :let_in, name: "updatedPageData", value_expr: v} -> v
      m when is_map(m) -> Enum.find_value(m, &g.(g, &1))
      l when is_list(l) -> Enum.find_value(l, &g.(g, &1))
      _ -> nil
    end
  end

  f.(f, expr)
end

IO.inspect(find_rec.(hot.expr), label: "updatedPageData", limit: :infinity)
