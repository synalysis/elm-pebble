alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.{Expr, Lambda}
alias Elmc.Backend.CCodegen.IRQueries

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
decl_map = IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Lamdera.Wire3", "decodeInt64"})

else_then = hd(decl.expr.in_expr.args).body.else_expr.then_expr

defmodule UnwrapD do
  def unwrap(expr, 0), do: expr
  def unwrap(%{op: :call, name: "d", args: [inner | _]}, n), do: unwrap(inner, n - 1)
  def unwrap(other, _), do: other
end

map_arg = Enum.at(else_then.args, 1)
succeed_call = UnwrapD.unwrap(map_arg, 2)
lam = hd(succeed_call.args)

ctx = Context.new(module: "Lamdera.Wire3", function_name: "probe", params: ["d"], decl_map: decl_map)
b = Builder.new("Lamdera.Wire3", "probe", args: ["d"])

IO.puts("compile inner b0/b1 lambda...")
case Lambda.compile(lam, ctx, b) do
  {:ok, _, b1} -> IO.puts("lambda OK nested=#{length(b1.lambdas)}")
  :unsupported -> IO.puts("lambda unsupported")
end

IO.puts("compile succeed call...")
case Expr.compile(succeed_call, ctx, b) do
  {:ok, _, _} -> IO.puts("succeed OK")
  :unsupported -> IO.puts("succeed unsupported")
end

IO.puts("compile d (d succeed)...")
d_once = %{op: :call, name: "d", args: [succeed_call]}
case Expr.compile(d_once, ctx, b) do
  {:ok, _, _} -> IO.puts("d once OK")
  :unsupported -> IO.puts("d once unsupported")
end

IO.puts("compile full map arg...")
case Expr.compile(map_arg, ctx, b) do
  {:ok, _, _} -> IO.puts("map arg OK")
  :unsupported -> IO.puts("map arg unsupported")
end

IO.puts("compile else.then map...")
case Expr.compile(else_then, Context.put_local(ctx, "unsignedToSigned", 99), b) do
  {:ok, _, _} -> IO.puts("else.then OK")
  :unsupported -> IO.puts("else.then unsupported")
end
