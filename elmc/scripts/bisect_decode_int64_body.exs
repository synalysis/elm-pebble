alias Elmc.Backend.Plan.{Builder, Context}
alias Elmc.Backend.Plan.Lower.{Expr, Function, Lambda}
alias Elmc.Backend.CCodegen.{IRQueries, VarAnalysis}

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, project} = ElmEx.Frontend.Bridge.load_project(app)
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
decl_map = IRQueries.function_decl_map(ir)
decl = Map.fetch!(decl_map, {"Lamdera.Wire3", "decodeInt64"})

defmodule UnwrapD do
  def unwrap(expr, 0), do: expr
  def unwrap(%{op: :call, name: "d", args: [inner | _]}, n), do: unwrap(inner, n - 1)
  def unwrap(other, _), do: other
end

defmodule Flatten do
  def flatten(args, %{op: :lambda, args: inner, body: body}, pre),
    do: flatten(args ++ (inner || []), body, pre)

  def flatten(args, body, pre), do: {args, body, pre}
end

else_then = hd(decl.expr.in_expr.args).body.else_expr.then_expr
map_arg = Enum.at(else_then.args, 1)
succeed_call = UnwrapD.unwrap(map_arg, 2)
lam = hd(succeed_call.args)

{flat_args, flat_body, _} = Flatten.flatten([], lam, [])
free = VarAnalysis.lambda_capture_free_vars(flat_body, flat_args)

IO.puts("flat_args=#{length(flat_args)} free=#{inspect(MapSet.to_list(free))}")
IO.inspect(flat_body, limit: 5, printable_limit: 200)

ctx = Context.new(module: "Lamdera.Wire3", function_name: "probe", params: ["d", "n0"], decl_map: decl_map)
b = Builder.new("Lamdera.Wire3", "probe", args: ["d", "n0"])

IO.puts("compile flat body only...")
child_ctx =
  Context.new(
    module: "Lamdera.Wire3",
    function_name: "probe_body",
    params: MapSet.to_list(free) ++ flat_args,
    decl_map: decl_map
  )

child_b = Builder.new("Lamdera.Wire3", "probe_body", args: child_ctx.params)

case Expr.compile(flat_body, child_ctx, child_b) do
  {:ok, reg, b1} ->
    IO.puts("body OK reg=#{reg} blocks=#{length(b1.blocks)} lambdas=#{length(b1.lambdas)}")

  :unsupported ->
    IO.puts("body unsupported")
end

IO.puts("compile inner succeed lambda...")
case Lambda.compile(lam, ctx, b) do
  {:ok, _, b1} -> IO.puts("lambda OK nested=#{length(b1.lambdas)}")
  :unsupported -> IO.puts("lambda unsupported")
end

IO.puts("compile decodeInt64...")
case Function.lower(decl, "Lamdera.Wire3", decl_map) do
  {:ok, _} -> IO.puts("decodeInt64 OK")
  :unsupported -> IO.puts("decodeInt64 unsupported")
end
