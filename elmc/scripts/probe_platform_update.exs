alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.{Case, Expr}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})

find_var = fn expr, target ->
  f = fn g, x, path ->
    case x do
      %{name: ^target, op: :var} -> [{Enum.reverse(path), x}]
      m when is_map(m) -> Enum.flat_map(m, fn {k, v} -> g.(g, v, [k | path]) end)
      l when is_list(l) -> Enum.flat_map(Enum.with_index(l), fn {v, i} -> g.(g, v, [i | path]) end)
      _ -> []
    end
  end

  f.(f, expr, [])
end

find_name = fn expr, target ->
  f = fn g, x, path ->
    case x do
      %{name: ^target} -> [{Enum.reverse(path), x}]
      m when is_map(m) -> Enum.flat_map(m, fn {k, v} -> g.(g, v, [k | path]) end)
      l when is_list(l) -> Enum.flat_map(Enum.with_index(l), fn {v, i} -> g.(g, v, [i | path]) end)
      _ -> []
    end
  end

  f.(f, expr, [])
end

refs = find_name.(decl.expr, "userMsgResult")
IO.puts("userMsgResult name refs: #{length(refs)}")
Enum.each(refs, fn {path, node} -> IO.inspect({Enum.take(path, 8), Map.take(node, [:op, :kind])}) end)

Enum.with_index(decl.expr.branches)
|> Enum.each(fn {branch, idx} ->
  pattern = Map.get(branch, :pattern, %{})
  label = Map.get(pattern, :name) || Map.get(pattern, :kind)

  IO.puts(
    "arm #{idx} #{label} userMsgResult_var=#{find_var.(Map.get(branch, :expr), "userMsgResult") != []} actionOrRedirect_var=#{find_var.(Map.get(branch, :expr), "actionOrRedirect") != []}"
  )
end)

pattern_has? = fn pat, name ->
  g = fn g, x ->
    case x do
      %{kind: :var, name: ^name} -> true
      m when is_map(m) -> Enum.any?(m, fn {_, v} -> g.(g, v) end)
      l when is_list(l) -> Enum.any?(l, &g.(g, &1))
      _ -> false
    end
  end

  g.(g, pat)
end

parent_case = fn expr ->
  g = fn g, x ->
    case x do
      %{op: :case, branches: branches} = c ->
        if Enum.any?(branches, fn b -> find_var.(Map.get(b, :expr), "userMsgResult") != [] end) or
             Enum.any?(branches, fn b ->
               match?(%{pattern: %{bind: "userMsgResult"}}, b) or
                 pattern_has?.(Map.get(b, :pattern), "userMsgResult")
             end) do
          c
        else
          Enum.find_value(x, &g.(g, &1))
        end

      m when is_map(m) -> Enum.find_value(m, &g.(g, &1))
      l when is_list(l) -> Enum.find_value(l, &g.(g, &1))
      _ -> nil
    end
  end

  g.(g, expr)
end

host = parent_case.(decl.expr)

if host do
  IO.inspect(Map.take(host, [:op, :subject]), label: "host case")
  IO.inspect(Enum.map(host.branches, &Map.get(&1, :pattern)), label: "patterns")
else
  IO.puts("host case not found")
end

Process.delete(:elmc_plan_unsupported_reasons)

params = Map.get(decl, :args, []) ++ ["userMsgResult"]
ctx =
  Context.new(
    module: "Pages.Internal.Platform",
    function_name: "update_probe",
    params: Enum.uniq(params),
    decl_map: decl_map
  )

b = Builder.new("Pages.Internal.Platform", "update_probe", args: ctx.params)

case Expr.compile(decl.expr, ctx, b) do
  {:ok, _, _} -> IO.puts("update expr OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "update expr failed")
end

Process.delete(:elmc_plan_unsupported_reasons)
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))

alias Elmc.Backend.Plan.Lower.Case.TagSwitch

case TagSwitch.compile(%{op: :var, name: "appMsg"}, decl.expr.branches, ctx, b) do
  {:ok, _, _} -> IO.puts("TagSwitch OK")
  :unsupported -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "TagSwitch failed")
end

arm = Enum.at(decl.expr.branches, 3)
IO.puts("FetcherComplete arm has userMsgResult var ref: #{find_var.(arm.expr, "userMsgResult") != []}")

Process.delete(:elmc_plan_unsupported_reasons)
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))
Process.put(:elmc_module_ports, Elmc.Backend.CCodegen.IRQueries.module_ports_map(ir))

case Elmc.Backend.Plan.Lower.Function.lower(decl, "Pages.Internal.Platform", decl_map, []) do
  {:ok, _} -> IO.puts("Function.lower OK")
  _ -> IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "Function.lower failed")
end
