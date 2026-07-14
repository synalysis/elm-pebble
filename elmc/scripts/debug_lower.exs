# Usage: cd elmc && mix run scripts/debug_lower.exs Pages.Internal.Platform perform

alias Elmc.Backend.Plan
alias Elmc.Backend.Plan.Debug
alias Elmc.Backend.Plan.{Builder, Context, EpilogueRelease, Optimize, Verify}
alias Elmc.Backend.Plan.Lower.Expr
alias Elmc.Backend.CCodegen.IRQueries

[module, name] = System.argv()

{:ok, project} = ElmEx.Frontend.Bridge.load_project(Path.expand("../../elm_pebble_dev", __DIR__))
{:ok, ir0} = ElmEx.IR.Lowerer.lower_project(project)
ir = ir0 |> ElmEx.IR.PipeChain.desugar_project() |> ElmEx.IR.DeadCode.strip("Main")
decl_map = IRQueries.function_decl_map(ir)
Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
Process.put(:elmc_module_ports, IRQueries.module_ports_map(ir))
Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

decl = Map.fetch!(decl_map, {module, name})
expr = Map.get(decl, :expr) || %{op: :int_literal, value: 0}
args = Map.get(decl, :args, []) |> List.wrap()

ctx =
  Context.new(
    module: module,
    function_name: name,
    decl_map: decl_map,
    params: args,
    rc_required: false,
    fallible: false,
    function_tail: true
  )

b0 = Builder.new(module, name, args: args, rc_required: false, fallible: false)

b =
  Enum.reduce(Enum.with_index(args), b0, fn {param, idx}, b_acc ->
    {_reg, b1} = Builder.get_or_load_param(b_acc, idx, param)
    b1
  end)

case Expr.compile(expr, ctx, b) do
  {:ok, ret_reg, b1} ->
    plan =
      b1
      |> Builder.emit_ret(ret_reg)
      |> Builder.to_function_plan()
      |> EpilogueRelease.run()
      |> Optimize.run()

    case Verify.run(plan) do
      :ok ->
        lambda_fail =
          Enum.find_value(Enum.with_index(plan.lambdas), fn {lam, idx} ->
            case Verify.run(EpilogueRelease.run(lam) |> Optimize.run()) do
              :ok -> nil
              {:error, r, m} -> {idx, r, m, lam}
            end
          end)

        case lambda_fail do
          nil ->
            IO.puts("OK")

          {idx, r, m, lam} ->
            IO.puts("lambda #{idx} VERIFY FAIL #{inspect({r, m})}")
            IO.puts(Debug.dump(lam))
        end

      {:error, r, m} ->
        IO.puts("VERIFY FAIL #{inspect({r, m})}")
        IO.puts(Debug.dump(plan))
    end

  :unsupported ->
    IO.inspect(Process.get(:elmc_plan_unsupported_reasons))
end
