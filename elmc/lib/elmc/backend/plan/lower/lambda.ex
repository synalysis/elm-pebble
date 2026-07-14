defmodule Elmc.Backend.Plan.Lower.Lambda do
  @moduledoc false

  alias Elmc.Backend.CCodegen.VarAnalysis
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Expr, Tuple}
  alias Elmc.Backend.Plan.Types

  @type tuple_binding :: {String.t(), :first | :second, String.t()}

  @spec compile(Types.ir_expr(), Context.t(), Builder.t()) :: Types.compile_result_required()
  def compile(%{op: :lambda, args: lambda_args, body: body}, ctx, b) do
    {args, flat_body, tuple_prelude} = flatten_curried(lambda_args || [], body, [])
    compile_lambda(args, flat_body, tuple_prelude, ctx, b)
  end

  def compile(_, _, _), do: :unsupported

  @partial_ops %{
    "__neq__" => :neq,
    "__eq__" => :eq
  }

  @partial_binops ~w(__add__ __sub__ __mul__ __idiv__)

  @spec partial_operator_var?(String.t()) :: boolean()
  def partial_operator_var?(name) when is_binary(name), do: name in @partial_binops

  @spec compile_partial(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_partial(%{op: :call, name: name, args: [bound]}, ctx, b)
      when name in @partial_binops do
    compile_lambda(
      ["x"],
      %{
        op: :call,
        name: name,
        args: [bound, %{op: :var, name: "x"}]
      },
      [],
      ctx,
      b
    )
  end

  def compile_partial(%{op: :call, name: name, args: []}, ctx, b)
      when name in @partial_binops do
    compile_lambda(
      ["a", "b"],
      %{
        op: :call,
        name: name,
        args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
      },
      [],
      ctx,
      b
    )
  end

  def compile_partial(%{op: :call, name: name, args: [rhs]}, ctx, b) when is_binary(name) do
    case Map.get(@partial_ops, name) do
      kind when kind in [:neq, :eq] ->
        compile_lambda(
          ["a"],
          %{
            op: :compare,
            kind: kind,
            left: %{op: :var, name: "a"},
            right: rhs
          },
          [],
          ctx,
          b
        )

      _ ->
        :unsupported
    end
  end

  def compile_partial(_, _, _), do: :unsupported

  defp flatten_curried(args, %{op: :lambda, args: inner_args, body: inner_body}, prelude) do
    flatten_curried(args ++ (inner_args || []), inner_body, prelude)
  end

  defp flatten_curried(args, body, prelude) do
    case body do
      %{
        op: :let_in,
        name: dx,
        value_expr: %{op: :tuple_first_expr, arg: %{op: :var, name: tuple_var}},
        in_expr: %{
          op: :let_in,
          name: dy,
          value_expr: %{
            op: :tuple_second_expr,
            arg: %{op: :var, name: tuple_var2}
          },
          in_expr: %{op: :lambda, args: inner_args, body: inner_body}
        }
      } when tuple_var2 == tuple_var ->
        flatten_curried(
          args ++ (inner_args || []),
          inner_body,
          prelude ++ [{dx, :first, tuple_var}, {dy, :second, tuple_var}]
        )

      _ ->
        {args, body, prelude}
    end
  end

  @spec compile_lambda([String.t()], Types.ir_expr(), [tuple_binding()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_lambda(lambda_args, body, tuple_prelude, ctx, b)
      when is_list(lambda_args) and is_map(body) and is_list(tuple_prelude) do
    lambda_arg_set = MapSet.new(lambda_args)

    free_vars =
      body
      |> VarAnalysis.used_vars()
      |> MapSet.difference(lambda_arg_set)
      |> MapSet.intersection(resolvable_keys(ctx))
      |> MapSet.difference(MapSet.new(Map.keys(ctx.letrec_refs || %{})))
      |> MapSet.to_list()
      |> Enum.sort()

    case compile_captures(free_vars, ctx, b) do
      {:ok, capture_regs, b1} ->
        {:ok, capture_regs2, b1a} = prepend_letrec_capture(ctx, b1, capture_regs)

        case lower_lambda_plan(free_vars, lambda_args, body, tuple_prelude, ctx, b1a) do
          {:ok, child_plan, b2} ->
            idx = length(b2.lambdas)
            b3 = %{b2 | lambdas: b2.lambdas ++ [child_plan]}
            emit_closure(idx, capture_regs2, lambda_args, ctx, b3)

          _ ->
            record_lambda_unsupported(ctx, :lower_lambda_plan)
            :unsupported
        end

      _ ->
        record_lambda_unsupported(ctx, :compile_captures)
        :unsupported
    end
  end

  def compile_lambda(_, _, _, _, _), do: :unsupported

  defp compile_captures(vars, ctx, b) do
    capture_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    Enum.reduce_while(vars, {:ok, [], b}, fn name, {:ok, acc, b_acc} ->
      case Expr.compile(%{op: :var, name: name}, capture_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) ->
          {:ok, owned, b2} = Expr.compile_runtime_builtin(:retain, [reg], capture_ctx, b1)
          {:cont, {:ok, acc ++ [owned], b2}}

        _ ->
          {:halt, :unsupported}
      end
    end)
  end

  defp prepend_letrec_capture(%{letrec_self: name} = ctx, b, capture_regs)
       when is_binary(name) do
    case Context.letrec_ref(ctx, name) do
      ref when is_binary(ref) ->
        {dest, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :forward_ref_capture, %{
            dest: dest,
            args: %{ref: ref},
            effects: Types.owned_effects(dest)
          })

        {:ok, [dest | capture_regs], b2}

      _ ->
        {:ok, capture_regs, b}
    end
  end

  defp prepend_letrec_capture(_ctx, b, capture_regs), do: {:ok, capture_regs, b}

  defp lower_lambda_plan(free_vars, lambda_args, body, tuple_prelude, parent_ctx, b) do
    all_params =
      if is_binary(parent_ctx.letrec_self) do
        ["__letrec_ref__" | free_vars ++ lambda_args]
      else
        free_vars ++ lambda_args
      end

    lam_idx = length(b.lambdas)
    lam_name = "#{parent_ctx.function_name || "anon"}_lam_#{lam_idx}"

    child_ctx =
      Context.new(
        module: parent_ctx.module,
        function_name: lam_name,
        decl_map: parent_ctx.decl_map,
        params: all_params,
        rc_required: parent_ctx.rc_required,
        fallible: parent_ctx.fallible,
        function_tail: false,
        letrec_refs: parent_ctx.letrec_refs,
        letrec_in_closure: parent_ctx.letrec_self != nil,
        local_types: parent_ctx.local_types || %{}
      )

    child_b =
      Builder.new(parent_ctx.module || "Main", lam_name,
        args: all_params,
        rc_required: parent_ctx.rc_required,
        fallible: parent_ctx.fallible
      )

    child_b =
      if parent_ctx.rc_required do
        Builder.catch_begin(child_b)
      else
        child_b
      end

    with {:ok, child_ctx1, child_b1} <-
           bind_tuple_prelude(tuple_prelude, free_vars, lambda_args, child_ctx, child_b) do
      case Expr.compile(body, child_ctx1, child_b1) do
        {:ok, result_reg, b1} ->
          {b2, ret_reg} = finalize_lambda_result(b1, result_reg, parent_ctx.rc_required)
          b3 = if parent_ctx.rc_required, do: Builder.catch_end(b2), else: b2
          b4 = Builder.emit_ret(b3, ret_reg)

          child_plan =
            Builder.to_function_plan(b4)
            |> Map.put(:lambda_arg_count, length(lambda_args))

          {:ok, child_plan, b}

        _ ->
          record_lambda_body_unsupported(child_ctx1, body)
          :unsupported
      end
    else
      _ ->
        record_lambda_body_unsupported(child_ctx, body)
        :unsupported
    end
  end

  defp bind_tuple_prelude([], _free_vars, _lambda_args, ctx, b), do: {:ok, ctx, b}

  defp bind_tuple_prelude(prelude, free_vars, lambda_args, ctx, b) do
    Enum.reduce_while(prelude, {:ok, ctx, b}, fn {name, which, tuple_var},
                                                 {:ok, ctx_acc, b_acc} ->
      case Enum.find_index(lambda_args, &(&1 == tuple_var)) do
        idx when is_integer(idx) ->
          {tuple_reg, b1} = Builder.get_or_load_param(b_acc, length(free_vars) + idx, tuple_var)
          ctx1 = Context.put_local(ctx_acc, tuple_var, tuple_reg)
          b2 = Builder.bind_local(b1, tuple_var, tuple_reg)

          proj_op =
            case which do
              :first -> :tuple_first_expr
              :second -> :tuple_second_expr
            end

          case Tuple.compile(%{op: proj_op, arg: %{op: :var, name: tuple_var}}, ctx1, b2) do
            {:ok, reg, b3} when is_integer(reg) ->
              {:cont, {:ok, Context.put_local(ctx1, name, reg), Builder.bind_local(b3, name, reg)}}

            _ ->
              {:halt, :unsupported}
          end

        _ ->
          {:halt, :unsupported}
      end
    end)
  end

  defp finalize_lambda_result(b, :fn_out, _), do: {b, :fn_out}

  defp finalize_lambda_result(b, result_reg, true) when is_integer(result_reg) do
    {Builder.emit_publish_fn_out(b, result_reg), :fn_out}
  end

  defp finalize_lambda_result(b, result_reg, _), do: {b, result_reg}

  defp emit_closure(index, capture_regs, lambda_args, ctx, b) do
    {dest, b1} =
      case Context.dest_for_call(ctx) do
        :fn_out -> {:fn_out, b}
        :branch_out -> {:branch_out, b}
        :scratch -> Builder.fresh_reg(b)
      end

    {borrows, consumes} = Builder.partition_call_args(b1, capture_regs)

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: ctx.fallible or ctx.rc_required}
      end

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1

    {_, b3} =
      Builder.emit(b2, :make_closure, %{
        dest: dest,
        args: %{index: index, arity: length(lambda_args), captures: capture_regs},
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3
    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  defp resolvable_keys(ctx) do
    MapSet.new(ctx.params ++ Map.keys(ctx.locals))
  end

  defp record_lambda_unsupported(ctx, step) when is_map(ctx) do
    key = {Map.get(ctx, :module), Map.get(ctx, :function_name)}

    reason = %{
      op: :lambda,
      target: nil,
      kind: step
    }

    cache = Process.get(:elmc_plan_unsupported_reasons, %{})
    Process.put(:elmc_plan_unsupported_reasons, Map.put_new(cache, key, reason))
  end

  defp record_lambda_body_unsupported(ctx, body) when is_map(ctx) and is_map(body) do
    key = {Map.get(ctx, :module), Map.get(ctx, :function_name)}

    reason = %{
      op: Map.get(body, :op) || :unknown,
      target: Map.get(body, :target) || Map.get(body, :name),
      kind: :lambda_body
    }

    cache = Process.get(:elmc_plan_unsupported_reasons, %{})
    Process.put(:elmc_plan_unsupported_reasons, Map.put_new(cache, key, reason))
  end

  defp record_lambda_body_unsupported(_ctx, _body), do: :ok

end
