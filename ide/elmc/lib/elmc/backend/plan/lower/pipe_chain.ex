defmodule Elmc.Backend.Plan.Lower.PipeChain do
  @moduledoc false

  # Plan lowering for flat `pipe_chain` IR.
  #
  # `ElmEx.IR.PipeChain.desugar/1` intentionally leaves long *homogeneous* chains
  # as `:pipe_chain` so backends can flatten them to a loop. Plan Expr used to
  # call desugar then recurse — that is an infinite loop for those chains.
  # Mirror `CCodegen.PipeChainCompile`: compact repeat for homogeneous direct
  # callees, otherwise iterative step compilation (never nested desugar recurse).

  alias ElmEx.IR.PipeChain, as: IRPipe
  alias Elmc.Backend.Plan.{Builder, Context, Types}
  alias Elmc.Backend.Plan.Lower.Expr

  @pipeline_flatten_threshold 16
  @pipe_acc "__pipe_acc"

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, integer() | :fn_out | :branch_out, Builder.t()} | :unsupported | term()
  def compile(%{op: :pipe_chain, steps: steps, base: base}, ctx, b) when is_list(steps) do
    {homogeneous_prefix, rest} = split_homogeneous_prefix(steps)

    cond do
      length(homogeneous_prefix) >= @pipeline_flatten_threshold ->
        compile_homogeneous(hd(homogeneous_prefix), length(homogeneous_prefix), base, rest, ctx, b)

      length(steps) < @pipeline_flatten_threshold ->
        steps
        |> then(&IRPipe.desugar(%{op: :pipe_chain, steps: &1, base: base}))
        |> Expr.compile(ctx, b)

      true ->
        compile_iterative(steps, base, ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  defp compile_homogeneous(step, count, base, rest, ctx, b) do
    case direct_top_level_fn(step, ctx) do
      {module, name} ->
        scratch_ctx = Context.for_branch_arm(ctx)
        # When more pipe steps follow, keep the repeat result in a scratch reg.
        repeat_ctx = if rest == [], do: ctx, else: scratch_ctx

        with {:ok, base_reg, b1} <- Expr.compile(base, scratch_ctx, b),
             {:ok, acc_reg, b2} <-
               emit_pipe_apply_repeat(module, name, count, base_reg, repeat_ctx, b1) do
          case rest do
            [] ->
              finalize_pipe_result(acc_reg, ctx, b2)

            rest_steps ->
              compile_iterative_from_reg(rest_steps, acc_reg, ctx, b2)
          end
        else
          _ -> :unsupported
        end

      :error ->
        compile_iterative(List.duplicate(step, count) ++ rest, base, ctx, b)
    end
  end

  defp compile_iterative(steps, base, ctx, b) do
    scratch_ctx = Context.for_branch_arm(ctx)

    with {:ok, acc_reg, b1} <- Expr.compile(base, scratch_ctx, b) do
      compile_iterative_from_reg(steps, acc_reg, ctx, b1)
    end
  end

  defp compile_iterative_from_reg(steps, acc_reg, ctx, b) do
    scratch_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(steps, {:ok, acc_reg, b}, fn step, {:ok, acc, b_acc} ->
      b_bound = Builder.bind_local(b_acc, @pipe_acc, acc)
      step_expr = IRPipe.append_pipe_arg(step, %{op: :var, name: @pipe_acc})

      case Expr.compile(step_expr, scratch_ctx, b_bound) do
        {:ok, next_reg, b_next} when is_integer(next_reg) and next_reg != acc ->
          b_rel = Builder.emit_release(b_next, acc)
          {:cont, {:ok, next_reg, b_rel}}

        {:ok, next_reg, b_next} ->
          {:cont, {:ok, next_reg, b_next}}

        :unsupported ->
          {:halt, :unsupported}
      end
    end)
    |> case do
      {:ok, final_reg, b_final} -> finalize_pipe_result(final_reg, ctx, b_final)
      :unsupported -> :unsupported
    end
  end

  defp emit_pipe_apply_repeat(module, name, count, base_reg, ctx, b)
       when is_binary(module) and is_binary(name) and is_integer(count) and count > 0 and
              is_integer(base_reg) do
    {dest, b1} = dest_for_pipe(ctx, b)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, [], [base_reg])
      else
        %{produces: nil, consumes: [base_reg], borrows: [], fallible: true}
      end

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)
    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

    {_, b3} =
      Builder.emit(b2, :pipe_apply_repeat, %{
        dest: dest,
        args: %{module: module, name: name, count: count, base: base_reg},
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3

    result =
      case dest do
        d when is_integer(d) -> d
        :fn_out -> :fn_out
        :branch_out -> :branch_out
      end

    {:ok, result, b4}
  end

  defp finalize_pipe_result(reg, ctx, b) when is_integer(reg) do
    case Context.dest_for_call(ctx) do
      :fn_out ->
        b1 = Builder.emit_publish_fn_out(b, reg)
        {:ok, :fn_out, b1}

      :branch_out ->
        {_, b1} =
          Builder.emit(b, :publish, %{
            dest: :branch_out,
            args: %{source: reg},
            effects: %{produces: nil, consumes: [reg], borrows: [], fallible: false}
          })

        {:ok, :branch_out, b1}

      _ ->
        {:ok, reg, b}
    end
  end

  defp finalize_pipe_result(reg, _ctx, b) when reg in [:fn_out, :branch_out], do: {:ok, reg, b}

  defp dest_for_pipe(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      _ -> Builder.fresh_reg(b)
    end
  end

  defp direct_top_level_fn(%{op: :call, name: name, args: args}, ctx)
       when is_binary(name) and (args == [] or is_nil(args)) do
    {ctx.module || "Main", name}
  end

  defp direct_top_level_fn(%{op: :var, name: name}, ctx) when is_binary(name) do
    {ctx.module || "Main", name}
  end

  defp direct_top_level_fn(%{op: :qualified_ref, target: target}, _ctx) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [module, name] -> {module, name}
      _ -> :error
    end
  end

  defp direct_top_level_fn(%{op: :qualified_call, target: target, args: args}, _ctx)
       when is_binary(target) and (args == [] or is_nil(args)) do
    case String.split(target, ".", parts: 2) do
      [module, name] -> {module, name}
      _ -> :error
    end
  end

  defp direct_top_level_fn(_, _), do: :error

  defp split_homogeneous_prefix([]), do: {[], []}

  defp split_homogeneous_prefix([first | rest]) do
    {same, other} = Enum.split_while(rest, &(&1 == first))
    {[first | same], other}
  end
end
