defmodule Elmc.Backend.Plan.Lower.Lambda do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.{Host, TypeParsing}
  alias Elmc.Backend.CCodegen.VarAnalysis
  alias Elmc.Backend.Plan.{Builder, Context, EpilogueRelease, Optimize, ParamFieldInference}
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
    free_vars =
      body
      |> VarAnalysis.lambda_capture_free_vars(lambda_args)
      |> MapSet.intersection(resolvable_keys(ctx))
      |> MapSet.difference(MapSet.new(Map.keys(ctx.letrec_refs || %{})))
      |> MapSet.to_list()
      |> Enum.sort()

    used_letrec_refs = used_letrec_ref_names(body, ctx)

    case compile_captures(free_vars, ctx, b) do
      {:ok, capture_regs, b1} ->
        {:ok, capture_regs2, b1a} = prepend_letrec_captures(ctx, b1, capture_regs, used_letrec_refs)

        case lower_lambda_plan(free_vars, lambda_args, body, tuple_prelude, used_letrec_refs, ctx, b1a) do
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

  defp used_letrec_ref_names(body, ctx) do
    letrec_names = Map.keys(ctx.letrec_refs || %{})

    body
    |> VarAnalysis.used_vars()
    |> MapSet.intersection(MapSet.new(letrec_names))
    |> MapSet.to_list()
    |> order_letrec_capture_names(ctx)
  end

  defp order_letrec_capture_names(names, ctx) when is_list(names) do
  self = ctx.letrec_self

    names
    |> Enum.sort()
    |> then(fn sorted ->
      if is_binary(self) and self in sorted do
        [self | List.delete(sorted, self)]
      else
        sorted
      end
    end)
  end

  # `used_names` is the same list (in the same order) that `lower_lambda_plan`
  # uses to assign `letrec_capture_indices` (0, 1, 2, … via `Enum.with_index`).
  # The loaded letrec captures here must land in the closure's `captures[]`
  # array in that exact order — `Enum.reduce` + `[loaded | acc]` prepends each
  # new load, which reverses the *relative* order of multiple letrec captures
  # (last name processed ends up at index 0). With two used letrec refs (for
  # example a self-recursive `go` plus an incidentally-named case-pattern
  # binding sharing the letrec_refs table), `captures[0]` and `captures[1]`
  # silently swap: `forward_ref_load_captured` for `go` reads the wrong slot
  # and the closure calls a stale/unset forward ref instead of recursing into
  # itself (TcoCaptureClober: `addCaptured` closure over `captured` clobbered
  # by the loop accumulator because the self-recursion capture pointed at the
  # wrong forward ref).
  defp prepend_letrec_captures(ctx, b, capture_regs, used_names) when is_list(used_names) do
    {loaded_in_reverse, b1} =
      Enum.reduce(used_names, {[], b}, fn name, {acc, b_acc} ->
        case Context.letrec_ref(ctx, name) do
          ref when is_binary(ref) ->
            {:ok, loaded, b_next} = capture_letrec_ref(ref, ctx, b_acc)
            {[loaded | acc], b_next}

          _ ->
            {acc, b_acc}
        end
      end)

    {:ok, Enum.reverse(loaded_in_reverse) ++ capture_regs, b1}
  end

  defp capture_letrec_ref(ref, %{letrec_in_closure: true} = ctx, b) when is_binary(ref) do
    capture_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    {:ok, loaded_reg, b1} = Expr.compile_forward_ref_load(ref, capture_ctx, b)
    {:ok, owned, b2} = Expr.compile_runtime_builtin(:retain, [loaded_reg], capture_ctx, b1)
    {:ok, owned, b2}
  end

  defp capture_letrec_ref(ref, _ctx, b) when is_binary(ref) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :forward_ref_capture, %{
        dest: dest,
        args: %{ref: ref},
        effects: Types.owned_effects(dest)
      })

    {:ok, dest, b2}
  end

  defp lower_lambda_plan(free_vars, lambda_args, body, tuple_prelude, used_letrec_refs, parent_ctx, b) do
    letrec_cap_params =
      used_letrec_refs
      |> Enum.with_index()
      |> Enum.map(fn {_, idx} -> "__letrec_cap_#{idx}__" end)

    all_params = letrec_cap_params ++ free_vars ++ lambda_args

    # Outer letrec lambdas receive forward-ref *boxes* and share them with the
    # parent via letrec_capture_indices. Nested lambdas inside a letrec closure
    # receive already-loaded *values* (see capture_letrec_ref/3); bind those as
    # ordinary locals so the body does not emit forward_ref_load_captured against
    # a non-box capture (TcoLetFuncClobber withLet: `\x -> cont (n + x)`).
    capturing_values? = parent_ctx.letrec_in_closure == true

    letrec_capture_indices =
      if capturing_values? do
        %{}
      else
        used_letrec_refs
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {name, idx}, acc ->
          case Context.letrec_ref(parent_ctx, name) do
            ref when is_binary(ref) -> Map.put(acc, ref, idx)
            _ -> acc
          end
        end)
      end

    child_letrec_refs =
      if capturing_values? do
        Enum.reduce(used_letrec_refs, parent_ctx.letrec_refs || %{}, fn name, acc ->
          Map.delete(acc, name)
        end)
      else
        parent_ctx.letrec_refs
      end

    lam_idx = length(b.lambdas)
    lam_name = "#{parent_ctx.function_name || "anon"}_lam_#{lam_idx}"

    lambda_param_types = lambda_param_types(parent_ctx, lambda_args)

    # Same as Function.seed_inferred_param_fields: anonymous record field_access
    # on lambda params (e.g. Scene3d.composite `\scene -> scene.entities`) must
    # not fall back to index 0 when the param type is erased in the closure.
    inferred_param_fields =
      Map.merge(
        parent_ctx.inferred_param_fields || %{},
        ParamFieldInference.infer(%{expr: body, args: lambda_args})
      )

    letrec_in_closure? =
      parent_ctx.letrec_in_closure or
        map_size(letrec_capture_indices) > 0 or
        capturing_values? or
        is_binary(parent_ctx.letrec_self)

    child_ctx =
      Context.new(
        module: parent_ctx.module,
        function_name: lam_name,
        decl_map: parent_ctx.decl_map,
        params: all_params,
        rc_required: parent_ctx.rc_required,
        fallible: parent_ctx.fallible,
        function_tail: false,
        letrec_refs: child_letrec_refs,
        letrec_in_closure: letrec_in_closure?,
        letrec_capture_indices: letrec_capture_indices,
        lambda_plan: true,
        local_types: Map.merge(parent_ctx.local_types || %{}, lambda_param_types),
        inferred_param_fields: inferred_param_fields,
        curried_type_offset: (parent_ctx.curried_type_offset || 0) + length(lambda_args)
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
           bind_tuple_prelude(tuple_prelude, letrec_cap_params ++ free_vars, lambda_args, child_ctx, child_b),
         {:ok, child_ctx2, child_b2} <-
           bind_letrec_value_captures(used_letrec_refs, capturing_values?, child_ctx1, child_b1) do
      case Expr.compile(body, child_ctx2, child_b2) do
        {:ok, result_reg, b1} ->
          {b2, ret_reg} = finalize_lambda_result(b1, result_reg, parent_ctx.rc_required)
          b3 = if parent_ctx.rc_required, do: Builder.catch_end(b2), else: b2
          b4 = Builder.emit_ret(b3, ret_reg)

          # EpilogueRelease/Optimize must run here (not only at verification time)
          # so the plan stored in `b.lambdas` matches what phi construction assumed
          # when it decided to inline an arm's value and drop the arm's materializing
          # instruction (see IntPhiNative/TruthyNative phi_arm_drop_instrs). Otherwise
          # codegen reads the *unoptimized* lambda plan, keeps the dropped-in-theory
          # instruction, and its owned/boxed operand gets released before the phi's
          # inlined recompute reads it again (use-after-release).
          child_plan =
            Builder.to_function_plan(b4)
            |> EpilogueRelease.run()
            |> Optimize.run()
            |> Map.put(:lambda_arg_count, length(lambda_args))
            |> Map.put(:letrec_capture_indices, letrec_capture_indices)

          {:ok, child_plan, b}

        _ ->
          record_lambda_body_unsupported(child_ctx2, body)
          :unsupported
      end
    else
      _ ->
        record_lambda_body_unsupported(child_ctx, body)
        :unsupported
    end
  end

  defp bind_letrec_value_captures(_names, false, ctx, b), do: {:ok, ctx, b}
  defp bind_letrec_value_captures([], true, ctx, b), do: {:ok, ctx, b}

  defp bind_letrec_value_captures(names, true, ctx, b) when is_list(names) do
    Enum.reduce_while(Enum.with_index(names), {:ok, ctx, b}, fn {name, idx}, {:ok, ctx_acc, b_acc} ->
      param = "__letrec_cap_#{idx}__"

      case Builder.get_or_load_param(b_acc, idx, param) do
        {reg, b1} when is_integer(reg) ->
          ctx1 = Context.put_local(ctx_acc, name, reg)
          b2 = Builder.bind_local(b1, name, reg)
          {:cont, {:ok, ctx1, b2}}

        _ ->
          {:halt, :unsupported}
      end
    end)
  end

  defp bind_tuple_prelude([], _capture_prefix, _lambda_args, ctx, b), do: {:ok, ctx, b}

  defp bind_tuple_prelude(prelude, capture_prefix, lambda_args, ctx, b) do
    Enum.reduce_while(prelude, {:ok, ctx, b}, fn {name, which, tuple_var},
                                                 {:ok, ctx_acc, b_acc} ->
      case Enum.find_index(lambda_args, &(&1 == tuple_var)) do
        idx when is_integer(idx) ->
          {tuple_reg, b1} =
            Builder.get_or_load_param(b_acc, length(capture_prefix) + idx, tuple_var)
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

    # Always retain-dup capture regs before make_closure's transfer-consume.
    # Nested lambdas share parent free vars (andThen's `callback` / `decodeA`).
    # Duping only "named locals" in the nested builder leaves parent regs to be
    # zeroed, so the outer closure captures INT 0 and skipFrozenViewsPrefix
    # decodes at offset 0 (Page Data Error).
    {capture_regs, b1a} = Builder.dup_all_regs_for_consume(b1, capture_regs)
    {borrows, consumes} = {[], capture_regs}

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1a, ctx, true)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: ctx.fallible or ctx.rc_required}
      end

    b2 = if wrap_catch?, do: Builder.catch_begin(b1a), else: b1a

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

  defp lambda_param_types(parent_ctx, lambda_args) when is_list(lambda_args) do
    from_root = lambda_param_types_from_root(parent_ctx, lambda_args)
    from_expected = lambda_param_types_from_expected(parent_ctx, lambda_args)
    # Call-site expected types (withMetadata combine, etc.) win over the enclosing
    # root function's curried offset, which does not describe nested lambdas.
    Map.merge(from_root, from_expected)
  end

  defp lambda_param_types_from_root(parent_ctx, lambda_args) do
    with module when is_binary(module) <- parent_ctx.module,
         root when is_binary(root) <- Context.root_function_name(parent_ctx),
         %{type: type} <- Map.get(parent_ctx.decl_map, {module, root}, %{}),
         arg_types when is_list(arg_types) <- TypeParsing.function_arg_types(type),
         offset when is_integer(offset) <- parent_ctx.curried_type_offset || 0 do
      bind_lambda_arg_types(lambda_args, arg_types, offset)
    else
      _ -> %{}
    end
  end

  defp lambda_param_types_from_expected(parent_ctx, lambda_args) do
    case parent_ctx.expected_fn_type do
      type when is_binary(type) ->
        bind_lambda_arg_types(lambda_args, TypeParsing.function_arg_types(type), 0)

      _ ->
        %{}
    end
  end

  defp bind_lambda_arg_types(lambda_args, arg_types, offset)
       when is_list(lambda_args) and is_list(arg_types) and is_integer(offset) do
    lambda_args
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {arg, idx}, acc ->
      case Enum.at(arg_types, offset + idx) do
        arg_type when is_binary(arg_type) ->
          normalized = Host.normalize_type_name(arg_type)

          # Skip type variables (`a`, `b`) — they must not look like concrete
          # record aliases and must not force Float soft-risk either.
          if ElmEx.IR.TypeSignature.type_variable?(normalized) do
            acc
          else
            Map.put(acc, arg, normalized)
          end

        _ ->
          acc
      end
    end)
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
