app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl = Map.fetch!(Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir), {"Pages.Internal.Platform", "update"})
arm = Enum.at(decl.expr.branches, 10)
decode_case = hd(arm.expr.in_expr.branches).expr.in_expr

IO.puts("decode Maybe case branches: #{length(decode_case.branches)}")
Enum.with_index(decode_case.branches)
|> Enum.each(fn {br, i} ->
  pat = br.pattern
  IO.puts("\ndecode arm #{i}: #{Map.get(pat, :name, pat.kind)} bind=#{Map.get(pat, :bind)}")
  IO.inspect(br.expr, label: "  expr", limit: 15)
end)

just_arm = hd(decode_case.branches)
sketch_case = just_arm.expr.in_expr

IO.puts("\nResponseSketch case branches: #{length(sketch_case.branches)}")
Enum.with_index(sketch_case.branches)
|> Enum.each(fn {br, i} ->
  IO.puts("  sketch arm #{i}: #{br.pattern.name} tag=#{br.pattern.tag}")
end)

hot = Enum.find(sketch_case.branches, &(&1.pattern.name =~ "HotUpdate"))
IO.inspect(hot.pattern, label: "HotUpdate bind vars")

updated =
  hot.expr
  |> then(fn e ->
    f = fn g, x ->
      case x do
        %{op: :let_in, name: "updatedPageData", value_expr: v} -> v
        m when is_map(m) -> Enum.find_value(m, &g.(g, &1))
        l when is_list(l) -> Enum.find_value(l, &g.(g, &1))
        _ -> nil
      end
    end

    f.(f, e)
  end)

IO.inspect(updated, label: "HotUpdate updatedPageData", limit: :infinity)
