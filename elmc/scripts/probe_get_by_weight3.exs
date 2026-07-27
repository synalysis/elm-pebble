alias Elmc.Backend.Plan.Lower.Function
alias Elmc.Backend.Plan.TupleParamBind
alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.CCodegen.IRQueries
alias ElmEx.IR.FnArgDesugar

fixture = Path.expand("../test/fixtures/simple_project", __DIR__)

# Path A: Bridge + lower only
{:ok, project} = ElmEx.Frontend.Bridge.load_project(fixture)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir_a = ir0 |> ElmEx.IR.PipeChain.desugar_project()
dm_a = IRQueries.function_decl_map(ir_a)
decl_a = Map.fetch!(dm_a, {"Pkg.elm_random_1_0_0.Random", "getByWeight"})
IO.puts("PATH A args=#{inspect(decl_a.args)}")
IO.puts("PATH A expr.op=#{inspect(decl_a.expr.op)} subject=#{inspect(Map.get(decl_a.expr, :subject))}")

# Find raw declaration before FnArgDesugar if possible - look at source args in project modules
mod =
  Enum.find(project.modules || project[:modules] || [], fn m ->
    name = Map.get(m, :name) || Map.get(m, "name")
    name in ["Random", "Pkg.elm_random_1_0_0.Random"] or String.contains?(to_string(name), "random")
  end)
IO.puts("project module found?=#{mod != nil}")

# Inspect IR module decl args from ir0 before pipe
mod_ir = Enum.find(ir0.modules, &(&1.name == "Pkg.elm_random_1_0_0.Random"))
raw = Enum.find(mod_ir.declarations, &(&1.name == "getByWeight"))
IO.puts("IR0 args=#{inspect(raw.args)}")
IO.inspect(raw.expr, label: "IR0 expr head", limit: 20)

# Simulate sanitize path
IO.inspect(FnArgDesugar.desugar_args(["(weight, value)", "others", "countdown"], %{op: :var, name: "body"}), label: "desugar (weight,value)")
IO.inspect(FnArgDesugar.desugar_args(["(Float, a)", "others", "countdown"], %{op: :var, name: "body"}), label: "desugar nonsense")

# Path B: use result.ir from previous compile if present
out = Path.expand("../test/tmp/probe_gbw", __DIR__)
# Recompile lightly by loading cached? Just use Bridge again and also check lowerer cache keys

Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir_a))
Process.put(:elmc_plan_unsupported_reasons, %{})
IO.inspect(Function.lower(decl_a, "Pkg.elm_random_1_0_0.Random", dm_a, rc_required: true) , label: "lower A")

# Synthetic weight__value decl matching compile output
decl_w = %{
  name: "getByWeight",
  kind: :function,
  args: ["weight__value", "others", "countdown"],
  type: "(Float, a) -> List (Float, a) -> Float -> a",
  expr: decl_a.expr  # wrong - need body that uses weight/value
}

# Build weight__value shaped body like compile output
body = %{
  op: :case,
  subject: "others",
  branches: [
    %{pattern: %{kind: :constructor, name: "[]", resolved_name: "[]"}, expr: %{op: :var, name: "value"}},
    %{
      pattern: %{
        kind: :constructor,
        name: "::",
        resolved_name: "::",
        arg_pattern: %{
          kind: :tuple,
          elements: [%{kind: :var, name: "second"}, %{kind: :var, name: "otherOthers"}]
        }
      },
      expr: %{
        op: :if,
        cond: %{
          op: :compare,
          kind: :lte,
          left: %{op: :var, name: "countdown"},
          right: %{op: :qualified_call, target: "Basics.abs", args: [%{op: :var, name: "weight"}]}
        },
        then_expr: %{op: :var, name: "value"},
        else_expr: %{
          op: :qualified_call,
          target: "Pkg.elm_random_1_0_0.Random.getByWeight",
          args: [
            %{op: :var, name: "second"},
            %{op: :var, name: "otherOthers"},
            %{op: :call, name: "__sub__", args: [
              %{op: :var, name: "countdown"},
              %{op: :qualified_call, target: "Basics.abs", args: [%{op: :var, name: "weight"}]}
            ]}
          ]
        }
      }
    }
  ]
}

decl_w = %{name: "getByWeight", args: ["weight__value", "others", "countdown"], type: "(Float, a) -> List (Float, a) -> Float -> a", expr: body}
dm_w = Map.put(dm_a, {"Pkg.elm_random_1_0_0.Random", "getByWeight"}, decl_w)
Process.put(:elmc_plan_unsupported_reasons, %{})
IO.inspect(Function.lower(decl_w, "Pkg.elm_random_1_0_0.Random", dm_w, rc_required: true), label: "lower weight__value")
IO.inspect(Process.get(:elmc_plan_unsupported_reasons), label: "reasons")

# Try TupleParamBind manually
ctx = Context.new(module: "Pkg.elm_random_1_0_0.Random", function_name: "getByWeight", params: decl_w.args, decl_map: dm_w, rc_required: true, fallible: true, function_tail: true)
b = Builder.new("Pkg.elm_random_1_0_0.Random", "getByWeight", args: decl_w.args, rc_required: true, fallible: true)
b = Enum.reduce(Enum.with_index(decl_w.args), b, fn {n,i}, acc -> {_r, b1} = Builder.get_or_load_param(acc, i, n); b1 end)
IO.inspect(TupleParamBind.bind(decl_w, ctx, b) |> then(fn
  {:ok, ctx2, b2} -> {:ok, Map.keys(ctx2.locals || %{}), length(b2.blocks)}
  other -> other
end), label: "TupleParamBind.bind")

