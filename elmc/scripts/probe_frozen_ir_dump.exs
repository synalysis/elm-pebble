alias Elmc.Backend.CCodegen.IRQueries

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
tags = IRQueries.constructor_tag_map(ir)

for name <- ["HotUpdate", "RenderPage", "Redirect", "NotFound", "Action", "Just", "Ok", "Nothing"] do
  IO.puts("#{name} => #{Map.get(tags, name, "missing")}")
end

decl_map = IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})
arm = Enum.at(decl.expr.branches, 10)

dump_case = fn case_expr, label ->
  IO.puts("\n=== #{label} ===")
  IO.puts("subject: #{inspect(case_expr.subject)}")

  Enum.with_index(case_expr.branches)
  |> Enum.each(fn {br, i} ->
    pat = br.pattern
    pat_label =
      case pat do
        %{kind: :wildcard} -> "wildcard"
        %{kind: :tuple, elements: els} ->
          "tuple(#{length(els)}) " <>
            Enum.map_join(els, ", ", fn
              %{kind: :constructor, name: n} -> n
              %{kind: :tuple, elements: inner} ->
                "inner_tuple(#{length(inner)})"
              other -> inspect(other.kind)
            end)

        %{kind: :constructor, name: n} -> n
        other -> inspect(other)
      end

    IO.puts("  arm #{i}: #{pat_label}")
  end)
end

# outer case in FrozenViewsReady
outer = arm.expr
dump_case.(outer.in_expr, "outer case")

just_ok_arm = hd(outer.in_expr.branches)
dump_case.(just_ok_arm.expr.in_expr.in_expr, "decodedResponse case")

hot_arm =
  just_ok_arm.expr.in_expr.in_expr.branches
  |> Enum.find(fn br -> match?(%{name: "HotUpdate"}, br.pattern) end)

IO.inspect(hot_arm.pattern, label: "HotUpdate pattern")
IO.inspect(hot_arm.expr, label: "HotUpdate expr", limit: 60)
