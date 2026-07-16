app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl = Map.fetch!(Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir), {"Pages.Internal.Platform", "update"})
arm = Enum.at(decl.expr.branches, 10)

all_cases = fn expr ->
  f = fn g, x, acc ->
    case x do
      %{op: :case, branches: branches} = c ->
        acc = [c | acc]
        Enum.reduce(branches, acc, fn br, a -> g.(g, Map.get(br, :expr), a) end)

      m when is_map(m) ->
        Enum.reduce(m, acc, fn {_, v}, a -> g.(g, v, a) end)

      l when is_list(l) ->
        Enum.reduce(l, acc, fn v, a -> g.(g, v, a) end)

      _ ->
        acc
    end
  end

  f.(f, expr, [])
end

sketch_cases =
  all_cases.(arm.expr)
  |> Enum.filter(fn c ->
    Enum.any?(c.branches, fn br ->
      br.pattern[:tag] == 2 and match?(%{kind: :constructor}, br.pattern)
    end)
  end)

IO.puts("cases with tag-2 ctor arms: #{length(sketch_cases)}")

for c <- sketch_cases do
  br = Enum.find(c.branches, &(&1.pattern[:tag] == 2))
  IO.puts("subject=#{inspect(c.subject)} name=#{br.pattern[:name]} resolved=#{br.pattern[:resolved_name]}")
end

hot =
  sketch_cases
  |> Enum.find_value(fn c ->
    Enum.find(c.branches, fn br ->
      n = br.pattern[:resolved_name] || br.pattern[:name] || ""
      String.contains?(to_string(n), "HotUpdate")
    end)
  end)
  |> then(fn c ->
    Enum.find(c.branches, fn br ->
      n = br.pattern[:resolved_name] || br.pattern[:name] || ""
      String.contains?(to_string(n), "HotUpdate")
    end)
  end)

find_let = fn expr, name ->
  f = fn g, x ->
    case x do
      %{op: :let_in, name: ^name, value_expr: v} -> v
      m when is_map(m) -> Enum.find_value(m, &g.(g, &1))
      l when is_list(l) -> Enum.find_value(l, &g.(g, &1))
      _ -> nil
    end
  end

  f.(f, expr)
end

IO.inspect(find_let.(hot.expr, "updatedPageData"), label: "HotUpdate updatedPageData", limit: :infinity)
IO.inspect(find_let.(hot.expr, "updatedPageData_"), label: "HotUpdate updatedPageData_", limit: :infinity)
