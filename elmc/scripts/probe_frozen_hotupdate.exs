walk = fn g, x, acc ->
  case x do
    %{op: :case, subject: subj} = c ->
      acc = if subj == "decodedResponse", do: [c | acc], else: acc
      Enum.reduce(x, acc, fn {_, v}, a -> g.(g, v, a) end)

    m when is_map(m) ->
      Enum.reduce(m, acc, fn {_, v}, a -> g.(g, v, a) end)

    l when is_list(l) ->
      Enum.reduce(l, acc, fn v, a -> g.(g, v, a) end)

    _ ->
      acc
  end
end

pat_vars = fn pat ->
  g = fn g, x, acc ->
    case x do
      %{kind: :var, name: n} -> [n | acc]
      m when is_map(m) -> Enum.reduce(m, acc, fn {_, v}, a -> g.(g, v, a) end)
      l when is_list(l) -> Enum.reduce(l, acc, fn v, a -> g.(g, v, a) end)
      _ -> acc
    end
  end

  g.(g, pat, []) |> Enum.uniq()
end

page_data_expr = fn expr ->
  g = fn g, x ->
    case x do
      %{op: :record_literal, fields: fields} ->
        case Enum.find(fields, &(&1.name == "pageData")) do
          nil -> []
          %{expr: e} -> [e]
        end

      m when is_map(m) -> Enum.flat_map(m, fn {_, v} -> g.(g, v) end)
      l when is_list(l) -> Enum.flat_map(l, &g.(g, &1))
      _ -> []
    end
  end

  g.(g, expr)
end

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl = Map.fetch!(Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir), {"Pages.Internal.Platform", "update"})
arm = Enum.at(decl.expr.branches, 10)

cases = walk.(walk, arm.expr, [])
IO.puts("decodedResponse cases: #{length(cases)}")

for dc <- cases do
  Enum.with_index(dc.branches)
  |> Enum.each(fn {br, i} ->
    pat = br.pattern
    IO.puts("\ndecoded arm #{i}: #{Map.get(pat, :name, inspect(pat.kind))} tag=#{Map.get(pat, :tag)}")
    IO.puts("  pattern vars: #{inspect(pat_vars.(pat))}")
    IO.inspect(page_data_expr.(br.expr), label: "  pageData expr")
  end)
end

outer_cases = walk.(walk, arm.expr, []) |> Enum.filter(&(&1.subject == "caseSubject"))
IO.puts("\nouter caseSubject cases: #{length(outer_cases)}")

for oc <- outer_cases do
  Enum.with_index(oc.branches)
  |> Enum.each(fn {br, i} ->
    IO.puts("\nouter arm #{i} vars: #{inspect(pat_vars.(br.pattern))}")
    IO.inspect(br.pattern, limit: 20)
  end)
end
