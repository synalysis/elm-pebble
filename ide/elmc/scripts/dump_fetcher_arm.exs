app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")

decl =
  ir.modules
  |> Enum.find(&(&1.name == "Pages.Internal.Platform"))
  |> then(fn m -> Enum.find(m.declarations, &(&1.name == "update")) end)

arm = Enum.at(decl.expr.branches, 3)
IO.inspect(arm.pattern, label: "pattern", limit: :infinity)

dump =
  fn e, depth ->
    if depth > 8 do
      "..."
    else
      case e do
        %{op: :let_in, name: n, value_expr: v} ->
          "let #{n} = #{dump.(v, depth + 1)} in " <> dump.(Map.get(e, :in_expr), depth + 1)

        %{op: :case, subject: s, branches: branches} ->
          arms =
            branches
            |> Enum.map(fn b ->
              pat = Map.get(b, :pattern, %{})
              pat_label =
                case pat do
                  %{kind: :constructor, name: name} -> name
                  %{kind: :var, name: name} -> name
                  _ -> inspect(pat, limit: 5)
                end

              "#{pat_label} -> #{dump.(Map.get(b, :expr), depth + 1)}"
            end)
            |> Enum.join(" | ")

          "case #{inspect(s)} { #{arms} }"

        %{op: op, name: name} when is_binary(name) ->
          "#{op}(#{name})"

        %{op: op} ->
          to_string(op)

        _ ->
          inspect(e, limit: 20)
      end
    end
  end

IO.puts(dump.(arm.expr, 0))
