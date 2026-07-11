defmodule Elmc.Backend.Plan.Lower.Call do
  @moduledoc false

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.{Cmd, Expr, Lambda, SpecialValues}
  alias Elmc.Backend.Plan.Types

  @spec compile_call(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | nil, Builder.t()} | :unsupported
  def compile_call(%{op: op} = expr, ctx, b)
      when op in [:qualified_call, :call] do
    target = Map.get(expr, :target) || Map.get(expr, :name)
    args = Map.get(expr, :args, [])

    cond do
      batch_target?(target) ->
        compile_batch_call(target, args, ctx, b)

      true ->
        compile_fn_call(expr, target, args, ctx, b)
    end
  end

  def compile_call(_, _, _), do: :unsupported

  defp compile_fn_call(expr, target, args, ctx, b) do
    cond do
      ui_to_ui_node?(target) ->
        compile_ui_to_ui_node(args, ctx, b)

      true ->
        compile_fn_call_default(expr, target, args, ctx, b)
    end
  end

  defp ui_to_ui_node?(target) when is_binary(target),
    do: target in ["Pebble.Ui.toUiNode", "PebbleUi.toUiNode", "Ui.toUiNode"]

  defp ui_to_ui_node?(_), do: false

  defp compile_ui_to_ui_node([ops], ctx, b) do
    with {:ok, [ops_reg], b1} <- Expr.compile_args([ops], ctx, b) do
      Expr.compile_runtime_builtin(:retain, [ops_reg], ctx, b1)
    end
  end

  defp compile_ui_to_ui_node(_, _, _), do: :unsupported

  defp compile_fn_call_default(_expr, target, args, ctx, b) do
    case call_rewrite(target, args) do
      %{op: :pebble_cmd} = rewritten ->
        Cmd.compile(rewritten, ctx, b)

      nil ->
        compile_fn_call_special_or_target(target, args, ctx, b)

      rewritten ->
        case compile_special_rewrite(rewritten, args, ctx, b) do
          :unsupported -> compile_fn_call_special_or_target(target, args, ctx, b)
          other -> other
        end
    end
  end

  defp compile_fn_call_special_or_target(target, args, ctx, b) do
    {module, name} = parse_target(target, ctx, ctx.decl_map)

    case SpecialValues.special_value_from_target("#{module}.#{name}", args) do
      nil ->
        compile_fn_call_target(module, name, args, ctx, b)

      rewritten ->
        case compile_special_rewrite(rewritten, args, ctx, b) do
          :unsupported -> compile_fn_call_target(module, name, args, ctx, b)
          other -> other
        end
    end
  end

  defp compile_special_rewrite(%{op: :pebble_cmd} = rewritten, _args, ctx, b),
    do: Cmd.compile(rewritten, ctx, b)

  defp compile_special_rewrite(
         %{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_" <> _} = kind,
         args,
         ctx,
         b
       )
       when is_list(args) do
    Cmd.compile(%{op: :pebble_cmd, kind: kind, params: args}, ctx, b)
  end

  defp compile_special_rewrite(%{op: op} = rewritten, _args, ctx, b)
       when is_atom(op) and op != :unsupported,
       do: Expr.compile(rewritten, ctx, b)

  defp compile_special_rewrite(_rewritten, _args, _ctx, _b), do: :unsupported

  defp call_rewrite(target, args) do
    SpecialValues.special_value_from_target(target, args)
  end

  @spec compile_closure_call_from_reg(integer(), [map()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_closure_call_from_reg(callee_reg, args, ctx, b) when is_integer(callee_reg) do
    do_compile_closure_call(callee_reg, args, ctx, b)
  end

  defp compile_fn_call_target(module, name, args, ctx, b) do
    cond do
      oversaturated_call?(ctx, module, name, args) ->
        compile_oversaturated_call(module, name, args, ctx, b)

      true ->
        with {:ok, callee_reg, b_callee} <- closure_callee_reg(name, ctx, b),
             true <- args != [] do
          compile_closure_call(callee_reg, args, ctx, b_callee)
        else
          _ ->
            with {:ok, decl} <- Map.fetch(ctx.decl_map, {module, name}),
                 param_names <- Map.get(decl, :args, []),
                 true <- length(args) > 0 and length(args) < length(param_names),
                 {:ok, reg, b1} <- compile_curried_lambda(module, name, param_names, args, ctx, b) do
              {:ok, reg, b1}
            else
              _ ->
                with {:ok, arg_regs, b1} <- Expr.compile_args(args, ctx, b) do
                  {dest, b2} = dest_for_call(ctx, b1)
                  compile_fn_call_emit(module, name, arg_regs, dest, ctx, b2, args)
                else
                  _ -> :unsupported
                end
            end
        end
    end
  end

  defp oversaturated_call?(ctx, module, name, args) when is_list(args) do
    case Map.fetch(ctx.decl_map, {module, name}) do
      {:ok, %{args: param_names}} when is_list(param_names) and length(param_names) > 0 ->
        length(args) > length(param_names)

      _ ->
        false
    end
  end

  defp compile_oversaturated_call(module, name, args, ctx, b) do
    {:ok, %{args: param_names}} = Map.fetch(ctx.decl_map, {module, name})
    arity = length(param_names)
    {prefix, suffix} = Enum.split(args, arity)

    with {:ok, prefix_regs, b1} <- Expr.compile_args(prefix, ctx, b),
         {dest, b2} = dest_for_call(ctx, b1),
         {:ok, callee_reg, b3} when is_integer(callee_reg) <-
           compile_fn_call_emit(module, name, prefix_regs, dest, ctx, b2, prefix) do
      compile_closure_call(callee_reg, suffix, ctx, b3)
    else
      _ -> :unsupported
    end
  end

  defp closure_callee_reg(name, ctx, b) when is_binary(name) do
    case Context.letrec_ref(ctx, name) do
      ref when is_binary(ref) ->
        compile_forward_ref_load(ref, ctx, b)

      _ ->
        closure_callee_reg_local(name, ctx, b)
    end
  end

  defp closure_callee_reg_local(name, ctx, b) when is_binary(name) do
    case Context.local_reg(ctx, name) do
      reg when is_integer(reg) ->
        {:ok, reg, b}

      _ ->
        case Enum.find_index(ctx.params, &(&1 == name)) do
          idx when is_integer(idx) ->
            {reg, b1} = Builder.get_or_load_param(b, idx, name)
            {:ok, reg, b1}

          _ ->
            :error
        end
    end
  end

  defp compile_forward_ref_load(ref, ctx, b) when is_binary(ref) do
    {dest, b1} = Builder.fresh_reg(b)

    op =
      if Map.get(ctx, :letrec_in_closure) do
        :forward_ref_load_captured
      else
        :forward_ref_load
      end

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: dest,
        args: %{ref: ref},
        effects: Types.owned_effects(dest)
      })

    {:ok, dest, b2}
  end

  defp compile_closure_call(callee_reg, args, ctx, b) do
    do_compile_closure_call(callee_reg, args, ctx, b)
  end

  defp do_compile_closure_call(callee_reg, args, ctx, b) do
    with {:ok, arg_regs, b1} <- Expr.compile_args(args, ctx, b) do
      {dest, b2} = dest_for_call(ctx, b1)
      {borrows, consumes} = Builder.partition_call_args(b2, [callee_reg | arg_regs])

      effects =
        if is_integer(dest) do
          Types.fallible_effects(dest, borrows, consumes)
        else
          %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
        end

      wrap_catch? = Builder.wrap_fallible_instr_catch?(b2, ctx, true)
      b3 = if wrap_catch?, do: Builder.catch_begin(b2), else: b2

      {_, b4} =
        Builder.emit(b3, :call_closure, %{
          dest: dest,
          args: %{callee: callee_reg, args: arg_regs},
          effects: effects
        })

      b5 = if wrap_catch?, do: Builder.catch_end(b4), else: b4
      result = if is_integer(dest), do: dest, else: dest
      {:ok, result, b5}
    else
      _ -> :unsupported
    end
  end

  defp compile_curried_lambda(module, name, param_names, partial_args, ctx, b) do
    remaining = Enum.drop(param_names, length(partial_args))
    qualified = "#{module}.#{name}"

    body = %{
      op: :qualified_call,
      target: qualified,
      args: partial_args ++ Enum.map(remaining, &%{op: :var, name: &1})
    }

    Lambda.compile_lambda(remaining, body, [], ctx, b)
  end

  defp compile_batch_call(target, args, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with [list_expr | _] <- args,
         {:ok, list_reg, b1} <- compile_batch_list_arg(list_expr, operand_ctx, b) do
      Expr.compile_runtime_builtin(batch_builtin_id(target), [list_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_batch_list_arg(%{op: :list_literal, items: items}, ctx, b),
    do: Elmc.Backend.Plan.Lower.List.compile_literal(items, ctx, b)

  defp compile_batch_list_arg(expr, ctx, b), do: Expr.compile(expr, ctx, b)

  defp batch_target?(target) when is_binary(target) do
    String.ends_with?(target, ".batch") or target == "batch"
  end

  defp batch_target?(_), do: false

  defp batch_builtin_id(target) when is_binary(target) do
    cond do
      subscription_batch_target?(target) -> :sub_batch
      true -> :cmd_batch
    end
  end

  defp subscription_batch_target?(target) when is_binary(target) do
    target in [
      "Sub.batch",
      "Pebble.Events.batch",
      "Elm.Kernel.PebbleWatch.batch"
    ]
  end

  @spec compile_top_level_ref(String.t(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_top_level_ref(name, ctx, b) when is_binary(name) do
    module = ctx.module || "Main"

    case Map.fetch(ctx.decl_map, {module, name}) do
      {:ok, %{args: []}} ->
        {dest, b1} = dest_for_call(ctx, b)
        compile_fn_call_emit(module, name, [], dest, ctx, b1)

      {:ok, %{args: param_names}} when is_list(param_names) and param_names != [] ->
        compile_top_level_closure(module, name, param_names, ctx, b)

      :error ->
        :unsupported
    end
  end

  defp compile_top_level_closure(module, name, param_names, ctx, b) do
    qualified = "#{module}.#{name}"

    body = %{
      op: :qualified_call,
      target: qualified,
      args: Enum.map(param_names, &%{op: :var, name: &1})
    }

    Lambda.compile_lambda(param_names, body, [], ctx, b)
  end

  @doc false
  def parse_target(target, ctx, decl_map \\ nil) when is_binary(target) do
    decl_map = decl_map || Map.get(ctx, :decl_map, %{})

    case String.split(target, ".") do
      [name] ->
        {ctx.module || "Main", name}

      parts ->
        name = List.last(parts)
        full_module = parts |> Enum.drop(-1) |> Enum.join(".")

        if Map.has_key?(decl_map, {full_module, name}) do
          {full_module, name}
        else
          case String.split(target, ".", parts: 2) do
            [mod, rest] -> {mod, rest}
            [single] -> {ctx.module || "Main", single}
          end
        end
    end
  end

  defp dest_for_call(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out ->
        {:fn_out, b}

      :branch_out ->
        {:branch_out, b}

      :scratch ->
        Builder.fresh_reg(b)
    end
  end

  @doc false
  def compile_fn_call_emit(module, name, arg_regs, dest, ctx, b, arg_exprs \\ []) do
    {arg_regs, b0} =
      if is_list(arg_exprs) and arg_exprs != [] do
        Builder.reload_stale_param_args(b, ctx.params, arg_regs, arg_exprs)
      else
        {arg_regs, b}
      end

    {borrows, consumes} = Builder.partition_call_args(b0, arg_regs)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
      end

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b0, ctx, true)

    b1 =
      if wrap_catch? do
        Builder.catch_begin(b0)
      else
        b0
      end

    {_, b2} =
      Builder.emit(b1, :call_fn, %{
        dest: dest,
        args: %{module: module, name: name, args: arg_regs},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2

  result =
    case dest do
      d when is_integer(d) -> d
      :fn_out -> :fn_out
      :branch_out -> :branch_out
    end

    {:ok, result, b3}
  end
end
