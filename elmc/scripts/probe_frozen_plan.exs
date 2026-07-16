alias Elmc.Backend.Plan.Lower.Function

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)
Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(ir))

decl = Map.fetch!(decl_map, {"Pages.Internal.Platform", "update"})
arm = Enum.at(decl.expr.branches, 10)

Process.delete(:elmc_plan_unsupported_reasons)

case Function.lower(
       %{
         decl
         | name: "frozen_arm_probe",
           args: Map.get(decl, :args, []),
           expr: arm.expr
       },
       "Pages.Internal.Platform",
       decl_map,
       rc_required: true
     ) do
  {:ok, plan} ->
    instrs = Enum.flat_map(plan.blocks, & &1.instrs)

    page_refs =
      instrs
      |> Enum.filter(fn
        %{op: :forward_ref_load, args: %{ref: ref}} when is_binary(ref) ->
          String.contains?(ref, "pageData")

        _ ->
          false
      end)

    IO.puts("forward_ref_load pageData count: #{length(page_refs)}")
    Enum.take(page_refs, 5) |> IO.inspect(label: "samples")

    sync_sets =
      instrs
      |> Enum.filter(fn
        %{op: :forward_ref_set, args: %{ref: ref}} when is_binary(ref) ->
          String.contains?(ref, "pageData")

        _ ->
          false
      end)

    IO.puts("forward_ref_set pageData count: #{length(sync_sets)}")

  other ->
    IO.inspect(other)
    IO.inspect(Process.get(:elmc_plan_unsupported_reasons))
end

hot = fn expr ->
  f = fn g, x ->
    case x do
      %{op: :case, branches: branches} ->
        case Enum.find(branches, fn br ->
               is_binary(br.pattern[:name]) and String.ends_with?(br.pattern.name, "HotUpdate")
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

hot_arm = hot.(arm.expr)
IO.inspect(hot_arm.pattern, label: "HotUpdate pattern")

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

IO.inspect(find_rec.(hot_arm.expr), label: "updatedPageData IR", limit: :infinity)

final_model = fn expr ->
  f = fn g, x ->
    case x do
      %{op: :record_update, fields: fields, base: %{name: "model"}} ->
        case Enum.find(fields, &(&1.name == "pageData")) do
          nil -> g.(g, Map.delete(x, :fields))
          f -> f.expr
        end

      m when is_map(m) -> Enum.find_value(m, &g.(g, &1))
      l when is_list(l) -> Enum.find_value(l, &g.(g, &1))
      _ -> nil
    end
  end

  f.(f, expr)
end

IO.inspect(final_model.(hot_arm.expr), label: "HotUpdate model.pageData update expr", limit: 30)
