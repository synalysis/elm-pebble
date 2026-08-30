defmodule Elmc.Backend.Plan.Lower.Case do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.{IntPhiNative, TruthyNative}
  alias Elmc.Backend.Plan.Lower.Case.{CharSwitch, GuardedSwitch, IntSwitch, ListSwitch, TagSwitch}
  alias Elmc.Backend.Plan.Lower.{Expr, PatternBind, PlatformStatic}
  alias Elmc.Backend.Plan.Types

  @spec compile(Types.ir_case_expr(), Context.t(), Builder.t()) :: Types.compile_result()
  def compile(%{platform_static_macro: macro} = expr, ctx, b) when is_binary(macro) do
    PlatformStatic.compile_case(expr, macro, ctx, b)
  end

  def compile(%{subject: subject, branches: branches} = expr, ctx, b) when is_list(branches) do
    subj = subject_expr(subject)

    cond do
      length(branches) >= 2 and maybe_ctor_tuple_case?(subj, branches) ->
        {ctor_br, wild_br} = split_maybe_ctor_tuple_from_branches(branches)
        compile_maybe_ctor_tuple_case(subj, ctor_br, wild_br, ctx, b)

      match?([_, _], branches) ->
        [br1, br2] = branches

        cond do
          nothing_arm?(br1) and catch_all_arm?(br2) ->
            compile_maybe_nothing_case(subj, br1, br2, ctx, b)

          nothing_arm?(br2) and catch_all_arm?(br1) ->
            compile_maybe_nothing_case(subj, br2, br1, ctx, b)

          maybe_just_pair?(br1, br2) ->
            {nothing_br, just_br} = if nothing_arm?(br1), do: {br1, br2}, else: {br2, br1}
            compile_maybe_nothing_case(subj, nothing_br, just_br, ctx, b)

          true ->
            compile_dispatch(expr, subj, branches, ctx, b)
        end

      nested_maybe_ctor_branches?(branches) ->
        compile_nested_maybe_ctor_case(subj, branches, ctx, b)

      true ->
        compile_dispatch(expr, subj, branches, ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  @doc """
  True when branches are one tuple of Just/Nothing leaves plus `_`.

  Covers mixed official 2- and 3-tuples such as `(Just, Nothing)` or
  `(Just, Nothing, Just)`. IR encodes `(a, b, c)` as `:tuple3`; patterns stay
  nested `{a, {b, c}}` and flatten to the same leaf list.

  Used by Expr to peel `let caseSubject = (a, b[, c]) in case caseSubject of …`
  so the case subject is the `tuple2` expr (no heap tuple + GuardedSwitch).
  """
  @spec tuple2_maybe_pair_branches?([map()]) :: boolean()
  def tuple2_maybe_pair_branches?(branches) when is_list(branches) do
    maybe_ctor_tuple_pair_branches?(branches)
  end

  def tuple2_maybe_pair_branches?(_), do: false

  @spec subject_expr(String.t() | map() | term()) :: Types.ir_expr()

  defp subject_expr(name) when is_binary(name), do: %{op: :var, name: name}
  defp subject_expr(expr) when is_map(expr), do: expr
  defp subject_expr(_), do: %{op: :int_literal, value: 0}

  @spec compile_dispatch(
          map(),
          Types.expr(),
          Types.case_branches(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_dispatch(_expr, subject, branches, ctx, b) do
    branches = normalize_case_branches(branches)

    cond do
      ListSwitch.fixed_length_nil_branches?(branches) ->
        ListSwitch.compile_fixed_length_nil(subject, branches, ctx, b)

      ListSwitch.triple_branches?(branches) ->
        ListSwitch.compile_triple(subject, branches, ctx, b)

      ListSwitch.deep_cons_wildcard_branches?(branches) ->
        ListSwitch.compile_deep_cons_wildcard(subject, branches, ctx, b)

      ListSwitch.double_cons_wildcard_branches?(branches) ->
        ListSwitch.compile_double_cons_wildcard(subject, branches, ctx, b)

      ListSwitch.empty_var_branches?(branches) ->
        ListSwitch.compile_empty_var(subject, branches, ctx, b)

      ListSwitch.branches?(branches) -> ListSwitch.compile(subject, branches, ctx, b)
      CharSwitch.branches?(branches) -> CharSwitch.compile(subject, branches, ctx, b)
      TagSwitch.branches?(branches) -> TagSwitch.compile(subject, branches, ctx, b)
      IntSwitch.branches?(branches) -> IntSwitch.compile(subject, branches, ctx, b)
      GuardedSwitch.branches?(branches) -> GuardedSwitch.compile(subject, branches, ctx, b)
      true -> compile_linear_branches(branches, subject, ctx, b)
    end
  end

  @spec compile_nested_maybe_ctor_case(
          Types.expr(),
          Types.case_branches(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_nested_maybe_ctor_case(subject, branches, ctx, b) do
    {fallback_br, just_nested} = split_nested_maybe_branches(branches)

    inner_branches =
      just_nested
      |> Enum.map(&unwrap_just_nested_branch/1)
      |> assign_ctor_tags_when_missing()
      |> maybe_append_wildcard_default(fallback_br)

    payload_name = "__maybe_inner"

    saved_pending = Map.get(b, :pending_merge_block)
    subject_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, b1} <- Expr.compile(subject, subject_ctx, b),
         {:ok, cond_reg, b2} <- emit_test_maybe_nothing(subj_reg, b1),
         then_id = b2.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, then_id, else_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, then_reg, then_exit, b_then} <-
           compile_maybe_branch(Map.get(fallback_br, :expr), ctx, b_reserved, then_id),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         b_else_start = Builder.begin_cfg_arm_block(b_then_done, else_id),
         b_else_pending = %{b_else_start | pending_merge_block: merge_id},
         {:ok, payload_reg, b_payload} <-
           Expr.compile_runtime_builtin(:maybe_just_payload, [subj_reg], ctx, b_else_pending),
         else_ctx = Context.put_local(ctx, payload_name, payload_reg),
         b_bound = Builder.bind_local(b_payload, payload_name, payload_reg),
         {:ok, else_reg, b_else} <-
           TagSwitch.compile(%{op: :var, name: payload_name}, inner_branches, else_ctx, b_bound),
         switch_merge_id = tag_switch_merge_block_id(b_else),
         b_else_done = Builder.patch_terminator(b_else, switch_merge_id, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <-
           emit_merge(cond_reg, then_reg, else_reg, then_id, else_id, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec compile_maybe_nothing_case(
          Types.expr(),
          Types.case_branch(),
          Types.case_branch(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_maybe_nothing_case(subject, arm_a, arm_b, ctx, b) do
    if Context.stream_mode?(ctx) do
      compile_stream_maybe_nothing_case(subject, arm_a, arm_b, ctx, b)
    else
      compile_value_maybe_nothing_case(subject, arm_a, arm_b, ctx, b)
    end
  end

  defp compile_value_maybe_nothing_case(subject, arm_a, arm_b, ctx, b) do
    {nothing_br, other_br} = normalize_maybe_nothing_arms(arm_a, arm_b)
    saved_pending = Map.get(b, :pending_merge_block)
    subject_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, b_subj} <- Expr.compile(subject, subject_ctx, b),
         {:ok, cond_reg, b2} <- emit_test_maybe_nothing(subj_reg, b_subj),
         then_id = b2.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, then_id, else_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, then_reg, then_exit, b_then} <-
           compile_maybe_branch(Map.get(nothing_br, :expr), ctx, b_reserved, then_id),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         {:ok, else_reg, else_exit, b_else} <-
           compile_maybe_else_branch(
             Map.get(other_br, :pattern),
             Map.get(other_br, :expr),
             subj_reg,
             subject,
             ctx,
             b_then_done,
             else_id
           ),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <-
           emit_merge(cond_reg, then_reg, else_reg, then_id, else_id, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp compile_stream_maybe_nothing_case(subject, arm_a, arm_b, ctx, b) do
    {nothing_br, other_br} = normalize_maybe_nothing_arms(arm_a, arm_b)
    saved_pending = Map.get(b, :pending_merge_block)
    subject_ctx = %{Context.for_branch_arm(ctx) | stream_mode: false}

    with {:ok, subj_reg, b_subj} <- Expr.compile(subject, subject_ctx, b),
         {:ok, cond_reg, b2} <- emit_test_maybe_nothing(subj_reg, b_subj),
         then_id = b2.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, then_id, else_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, :stream_void, then_exit, b_then} <-
           compile_maybe_branch(Map.get(nothing_br, :expr), ctx, b_reserved, then_id),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         {:ok, :stream_void, else_exit, b_else} <-
           compile_maybe_else_branch(
             Map.get(other_br, :pattern),
             Map.get(other_br, :expr),
             subj_reg,
             subject,
             ctx,
             b_then_done,
             else_id
           ),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id) do
      {:ok, :stream_void, %{b_merge | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec compile_maybe_ctor_tuple_case(
          map(),
          map(),
          map(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  # `case (ma, mb[, mc]) of (Just/Nothing …) -> …; _ -> …` without a heap tuple.
  # Official 3-tuples are `:tuple3`; older IR still nests `tuple2`.
  defp compile_maybe_ctor_tuple_case(subj, ctor_br, wild_br, ctx, b) do
    if Context.stream_mode?(ctx) do
      compile_stream_maybe_ctor_tuple_case(subj, ctor_br, wild_br, ctx, b)
    else
      compile_value_maybe_ctor_tuple_case(subj, ctor_br, wild_br, ctx, b)
    end
  end

  defp compile_value_maybe_ctor_tuple_case(subj, ctor_br, wild_br, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)
    subject_ctx = Context.for_branch_arm(ctx)

    with {:ok, compiled, pred, b5} <- compile_ctor_tuple_pred(subj, ctor_br, subject_ctx, b),
         then_id = b5.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b5, {:br_if, then_id, else_id, pred}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         b_then_start = Builder.begin_cfg_arm_block(b_reserved, then_id),
         {:ok, then_ctx, b_bound} <- bind_maybe_ctor_tuple_payloads(compiled, ctx, b_then_start),
         {:ok, then_reg, then_exit, b_then} <-
           compile_maybe_branch_in_current(Map.get(ctor_br, :expr), then_ctx, b_bound),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         {:ok, else_reg, else_exit, b_else} <-
           compile_maybe_branch(Map.get(wild_br, :expr), ctx, b_then_done, else_id),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <-
           emit_merge(pred, then_reg, else_reg, then_id, else_id, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp compile_stream_maybe_ctor_tuple_case(subj, ctor_br, wild_br, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)
    subject_ctx = %{Context.for_branch_arm(ctx) | stream_mode: false}

    with {:ok, compiled, pred, b5} <- compile_ctor_tuple_pred(subj, ctor_br, subject_ctx, b),
         then_id = b5.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b5, {:br_if, then_id, else_id, pred}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         b_then_start = Builder.begin_cfg_arm_block(b_reserved, then_id),
         {:ok, then_ctx, b_bound} <- bind_maybe_ctor_tuple_payloads(compiled, ctx, b_then_start),
         {:ok, :stream_void, then_exit, b_then} <-
           compile_maybe_branch_in_current(Map.get(ctor_br, :expr), then_ctx, b_bound),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         {:ok, :stream_void, else_exit, b_else} <-
           compile_maybe_branch(Map.get(wild_br, :expr), ctx, b_then_done, else_id),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id) do
      {:ok, :stream_void, %{b_merge | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec compile_maybe_branch_in_current(Types.expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | Types.result_slot(), non_neg_integer(), Builder.t()} | :unsupported

  defp compile_maybe_branch_in_current(expr, ctx, b) do
    arm_ctx = Context.for_branch_arm(ctx)

    case Expr.compile(expr, arm_ctx, b) do
      {:ok, reg, b1} ->
        exit_id = b1.current_block.id
        {:ok, reg, exit_id, Builder.finish_block(b1, :none)}

      :unsupported ->
        :unsupported
    end
  end

  @spec emit_bool_and(Types.reg(), Types.reg(), Builder.t()) :: {:ok, Types.reg(), Builder.t()}

  defp emit_bool_and(left, right, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :bool_and, %{
        dest: dest,
        args: %{left: left, right: right},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [left, right],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  @spec emit_test_maybe_just(Types.reg(), Builder.t()) :: {:ok, Types.reg(), Builder.t()}

  defp emit_test_maybe_just(subj_reg, b) do
    with {:ok, nothing_reg, b1} <- emit_test_maybe_nothing(subj_reg, b) do
      {zero, b2} = Builder.emit_const_int(b1, 0)
      {dest, b3} = Builder.fresh_reg(b2)

      {_, b4} =
        Builder.emit(b3, :compare, %{
          dest: dest,
          args: %{kind: :eq, left: nothing_reg, right: zero},
          effects: %{
            produces: {:owned, dest},
            consumes: [],
            borrows: [nothing_reg, zero],
            fallible: false
          }
        })

      {:ok, dest, b4}
    end
  end

  @spec maybe_ctor_tuple_case?(map(), [map()]) :: boolean()

  defp maybe_ctor_tuple_case?(subj, branches) do
    match?(%{op: op} when op in [:tuple2, :tuple3], subj) and maybe_ctor_tuple_pair_branches?(branches) and
      match?(
        {:ok, _},
        ctor_tuple_leaf_pairs(subj, elem(split_maybe_ctor_tuple_from_branches(branches), 0))
      )
  end

  # One Just/Nothing-leaf tuple arm plus one or more catch-alls. The frontend
  # sometimes duplicates the `_` default (`(Just, Nothing, Just) / _ / _`).
  @spec maybe_ctor_tuple_pair_branches?([map()]) :: boolean()

  defp maybe_ctor_tuple_pair_branches?(branches) when is_list(branches) do
    ctors = Enum.filter(branches, &maybe_ctor_tuple_arm?/1)
    wilds = Enum.filter(branches, &catch_all_arm?/1)
    length(ctors) == 1 and length(wilds) >= 1 and length(ctors) + length(wilds) == length(branches)
  end

  @spec split_maybe_ctor_tuple_from_branches([map()]) :: {map(), map()}

  defp split_maybe_ctor_tuple_from_branches(branches) do
    {Enum.find(branches, &maybe_ctor_tuple_arm?/1), Enum.find(branches, &catch_all_arm?/1)}
  end

  @spec maybe_ctor_tuple_arm?(map() | term()) :: boolean()

  defp maybe_ctor_tuple_arm?(%{pattern: pattern}) do
    leaves = flatten_tuple_pattern_leaves(pattern)
    length(leaves) >= 2 and Enum.all?(leaves, &maybe_ctor_leaf_pattern?/1)
  end

  defp maybe_ctor_tuple_arm?(_), do: false

  @spec maybe_ctor_leaf_pattern?(map() | term()) :: boolean()

  defp maybe_ctor_leaf_pattern?(pattern),
    do: just_arm_pattern?(pattern) or nothing_pattern?(pattern)

  # Nested `tuple2(a, tuple2(b, c))`, official `:tuple3`, and nested
  # `{a, {b, c}}` patterns flatten to the same leaf list as a 3-tuple of Maybes.
  @spec flatten_tuple2_expr(map() | term()) :: [map()]

  defp flatten_tuple2_expr(%{op: :tuple3, a: a, b: b, c: c}) do
    flatten_tuple2_expr(a) ++ flatten_tuple2_expr(b) ++ flatten_tuple2_expr(c)
  end

  defp flatten_tuple2_expr(%{op: :tuple2, left: left, right: right}) do
    flatten_tuple2_expr(left) ++ flatten_tuple2_expr(right)
  end

  defp flatten_tuple2_expr(expr), do: [expr]

  @spec flatten_tuple_pattern_leaves(map() | term()) :: [map()]

  defp flatten_tuple_pattern_leaves(%{kind: :tuple, elements: elems}) when is_list(elems) do
    Enum.flat_map(elems, &flatten_tuple_pattern_leaves/1)
  end

  defp flatten_tuple_pattern_leaves(pattern), do: [pattern]

  @spec ctor_tuple_leaf_pairs(map(), map()) :: {:ok, [{map(), map()}]} | :error

  defp ctor_tuple_leaf_pairs(subj, ctor_br) do
    exprs = flatten_tuple2_expr(subj)
    pats = flatten_tuple_pattern_leaves(Map.get(ctor_br, :pattern))

    if length(exprs) >= 2 and length(exprs) == length(pats) do
      {:ok, Enum.zip(exprs, pats)}
    else
      :error
    end
  end

  @spec compile_ctor_tuple_pred(map(), map(), Context.t(), Builder.t()) ::
          {:ok, [{map(), map(), Types.reg()}], Types.reg(), Builder.t()} | :unsupported

  defp compile_ctor_tuple_pred(subj, ctor_br, ctx, b) do
    with {:ok, pairs} <- ctor_tuple_leaf_pairs(subj, ctor_br),
         {:ok, compiled, b1} <- compile_ctor_tuple_elems(pairs, ctx, b, []),
         {:ok, pred, b2} <- emit_ctor_tuple_and(compiled, b1) do
      {:ok, compiled, pred, b2}
    else
      _ -> :unsupported
    end
  end

  @spec compile_ctor_tuple_elems([{map(), map()}], Context.t(), Builder.t(), [
          {map(), map(), Types.reg()}
        ]) :: {:ok, [{map(), map(), Types.reg()}], Builder.t()} | :unsupported

  defp compile_ctor_tuple_elems([], _ctx, b, acc), do: {:ok, Enum.reverse(acc), b}

  defp compile_ctor_tuple_elems([{expr, pat} | rest], ctx, b, acc) do
    case Expr.compile(expr, ctx, b) do
      {:ok, reg, b1} -> compile_ctor_tuple_elems(rest, ctx, b1, [{expr, pat, reg} | acc])
      :unsupported -> :unsupported
    end
  end

  @spec emit_ctor_tuple_and([{map(), map(), Types.reg()}], Builder.t()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported

  defp emit_ctor_tuple_and([{_expr, pat, reg} | rest], b) do
    with {:ok, first, b1} <- emit_ctor_leaf_pred(pat, reg, b) do
      Enum.reduce_while(rest, {:ok, first, b1}, fn {_e, p, r}, {:ok, acc, bb} ->
        case emit_ctor_leaf_pred(p, r, bb) do
          {:ok, t, bb1} ->
            {:ok, next, bb2} = emit_bool_and(acc, t, bb1)
            {:cont, {:ok, next, bb2}}

          :unsupported ->
            {:halt, :unsupported}
        end
      end)
    else
      _ -> :unsupported
    end
  end

  defp emit_ctor_tuple_and([], _b), do: :unsupported

  @spec emit_ctor_leaf_pred(map(), Types.reg(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported

  defp emit_ctor_leaf_pred(pat, reg, b) do
    cond do
      just_arm_pattern?(pat) -> emit_test_maybe_just(reg, b)
      nothing_pattern?(pat) -> emit_test_maybe_nothing(reg, b)
      true -> :unsupported
    end
  end

  @spec bind_maybe_ctor_tuple_payloads([{map(), map(), Types.reg()}], Context.t(), Builder.t()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported

  defp bind_maybe_ctor_tuple_payloads([], ctx, b), do: {:ok, ctx, b}

  defp bind_maybe_ctor_tuple_payloads([{expr, pat, reg} | rest], ctx, b) do
    cond do
      just_arm_pattern?(pat) ->
        {:ok, _payload, b1, ctx1} = bind_maybe_payload(ctx, pat, reg, expr, b)
        bind_maybe_ctor_tuple_payloads(rest, ctx1, b1)

      nothing_pattern?(pat) ->
        bind_maybe_ctor_tuple_payloads(rest, ctx, b)

      true ->
        :unsupported
    end
  end

  @spec nothing_pattern?(map() | term()) :: boolean()

  defp nothing_pattern?(pattern), do: nothing_arm?(%{pattern: pattern})

  @spec compile_maybe_branch(Types.expr(), Context.t(), Builder.t(), non_neg_integer()) ::
          {:ok, Types.reg() | Types.result_slot(), non_neg_integer(), Builder.t()} | :unsupported

  defp compile_maybe_branch(expr, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    case Expr.compile(expr, arm_ctx, b_arm) do
      {:ok, reg, b1} ->
        exit_id = b1.current_block.id
        {:ok, reg, exit_id, Builder.finish_block(b1, :none)}

      :unsupported ->
        :unsupported
    end
  end

  @spec compile_maybe_else_branch(
          Types.pattern(),
          Types.expr(),
          Types.reg(),
          Types.expr() | nil,
          Context.t(),
          Builder.t(),
          non_neg_integer()
        ) :: {:ok, Types.reg() | Types.result_slot(), non_neg_integer(), Builder.t()} | :unsupported

  defp compile_maybe_else_branch(pattern, expr, subj_reg, subject_expr, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    with {:ok, _payload_reg, b1, else_ctx} <-
           bind_maybe_payload(arm_ctx, pattern, subj_reg, subject_expr, b_arm),
         {:ok, reg, b2} <- Expr.compile(expr, else_ctx, b1) do
      exit_id = b2.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b2, :none)}
    else
      _ -> :unsupported
    end
  end

  @spec skip_reserved(non_neg_integer(), non_neg_integer() | nil) :: non_neg_integer()

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id

  @spec emit_merge(
          Types.reg(),
          Types.reg(),
          Types.reg(),
          non_neg_integer(),
          non_neg_integer(),
          Builder.t()
        ) :: {:ok, Types.reg(), Builder.t()}
  defp emit_merge(cond_reg, then_reg, else_reg, then_arm_block, else_arm_block, b) do
    {merge, b1} = Builder.fresh_reg(b)
    instrs = builder_instrs(b1)

    {truthy_native?, then_shape, else_shape} =
      TruthyNative.phi_shapes?(instrs, then_reg, else_reg)

    {native_int_phi?, int_then_shape, int_else_shape} =
      if truthy_native? do
        {false, :unknown, :unknown}
      else
        IntPhiNative.native_int_phi_shapes?(instrs, then_reg, else_reg)
      end

    phi_consumes = Builder.phi_branch_consumes(b1, [cond_reg])

    args =
      %{then: then_reg, else: else_reg, cond: cond_reg}
      |> maybe_put_truthy_native(truthy_native?, then_shape, else_shape, then_arm_block, else_arm_block)
      |> maybe_put_native_int_phi(
        native_int_phi?,
        int_then_shape,
        int_else_shape,
        then_arm_block,
        else_arm_block
      )

    {_, b2} =
      Builder.emit(b1, :phi, %{
        dest: merge,
        args: args,
        effects: %{
          produces: {:owned, merge},
          consumes: phi_consumes,
          borrows: [],
          fallible: false
        }
      })

    {:ok, merge, b2}
  end

  defp maybe_put_truthy_native(args, false, _, _, _, _), do: args

  defp maybe_put_truthy_native(args, true, then_shape, else_shape, then_arm_block, else_arm_block) do
    Map.merge(args, %{
      truthy_native: true,
      then_shape: then_shape,
      else_shape: else_shape,
      then_arm_block: then_arm_block,
      else_arm_block: else_arm_block
    })
  end

  defp maybe_put_native_int_phi(args, false, _, _, _, _), do: args

  defp maybe_put_native_int_phi(args, true, then_shape, else_shape, then_arm_block, else_arm_block) do
    Map.merge(args, %{
      native_int_phi: true,
      then_shape: then_shape,
      else_shape: else_shape,
      then_arm_block: then_arm_block,
      else_arm_block: else_arm_block
    })
  end

  defp builder_instrs(%{blocks: blocks, current_block: %{instrs: cur}}) do
    Enum.flat_map(blocks, & &1.instrs) ++ cur
  end

  @spec compile_linear_branches(Types.case_branches(), Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_linear_branches(branches, subject, ctx, b) do
    cond do
      # Respect TagSwitch.branches?/1 exclusions (True/False, Maybe, lists).
      # A raw tag-count check would re-enter TagSwitch.compile/4 for bools.
      TagSwitch.branches?(branches) ->
        TagSwitch.compile(subject, branches, ctx, b)

      record_pattern_branches?(branches) ->
        compile_record_pattern_case(subject, branches, ctx, b)

      GuardedSwitch.branches?(branches) ->
        GuardedSwitch.compile(subject, branches, ctx, b)

      true ->
        :unsupported
    end
  end

  @spec record_pattern_branches?(list()) :: boolean()

  defp record_pattern_branches?(branches) when is_list(branches) do
    branches != [] and
      Enum.all?(branches, fn branch ->
        match?(%{pattern: %{kind: :record, fields: fields}} when is_list(fields), branch)
      end)
  end

  @spec compile_record_pattern_case(
          Types.expr(),
          Types.case_branches(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_record_pattern_case(subject, branches, ctx, b) do
    subject_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, b1} <- Expr.compile(subject_expr(subject), subject_ctx, b),
         {:ok, reg, b2} <- compile_record_pattern_branches(branches, subj_reg, ctx, b1) do
      {:ok, reg, b2}
    else
      _ -> :unsupported
    end
  end

  @spec compile_record_pattern_branches(
          Types.case_branches(),
          Types.reg(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_reg_result()

  defp compile_record_pattern_branches([%{pattern: pattern, expr: expr}], subj_reg, ctx, b) do
    arm_ctx = Context.for_branch_arm(ctx)

    with {:ok, ctx1, b1} <- PatternBind.bind(pattern, arm_ctx, b, subj_reg),
         {:ok, reg, b2} <- Expr.compile(expr, ctx1, b1) do
      {:ok, reg, b2}
    else
      _ -> :unsupported
    end
  end

  defp compile_record_pattern_branches(_, _, _, _), do: :unsupported

  @spec normalize_case_branches(list()) :: list()

  defp normalize_case_branches(branches) when is_list(branches) do
    Enum.map(branches, fn branch ->
      case Map.get(branch, :pattern) do
        %{kind: :qualified_constructor} = pattern ->
          %{branch | pattern: Map.put(pattern, :kind, :constructor)}

        pattern ->
          %{branch | pattern: pattern}
      end
    end)
  end

  @spec emit_test_maybe_nothing(Types.reg(), Builder.t()) :: {:ok, Types.reg(), Builder.t()}

  defp emit_test_maybe_nothing(subj_reg, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_maybe_nothing, %{
        dest: reg,
        args: %{reg: subj_reg},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [subj_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  @spec nothing_arm?(map() | term()) :: boolean()

  defp nothing_arm?(%{pattern: %{kind: :constructor, name: name}}) when is_binary(name) do
    short_ctor_name(name) == "Nothing"
  end

  defp nothing_arm?(%{pattern: %{kind: :qualified_constructor, name: name}}) when is_binary(name) do
    short_ctor_name(name) == "Nothing"
  end

  defp nothing_arm?(%{pattern: %{resolved_name: name}}) when is_binary(name) do
    short_ctor_name(name) == "Nothing"
  end

  defp nothing_arm?(_), do: false

  @spec normalize_maybe_nothing_arms(Types.case_branch(), Types.case_branch()) ::
          {Types.case_branch(), Types.case_branch()}

  defp normalize_maybe_nothing_arms(arm_a, arm_b) do
    cond do
      nothing_arm?(arm_a) -> {arm_a, arm_b}
      nothing_arm?(arm_b) -> {arm_b, arm_a}
      true -> {arm_a, arm_b}
    end
  end

  @spec catch_all_arm?(map() | term()) :: boolean()

  defp catch_all_arm?(%{pattern: %{kind: :var}}), do: true
  defp catch_all_arm?(%{pattern: %{kind: :wildcard}}), do: true

  defp catch_all_arm?(%{pattern: %{kind: :constructor, bind: bind}}) when is_binary(bind),
    do: true

  defp catch_all_arm?(_), do: false

  @spec short_ctor_name(String.t()) :: String.t()

  defp short_ctor_name(name) do
    name |> String.split(".") |> List.last()
  end

  @spec bind_pattern_pair(Context.t(), Builder.t(), Types.pattern(), Types.reg()) ::
          {Context.t(), Builder.t()}

  defp bind_pattern_pair(ctx, b, %{kind: :tuple, elements: elements}, subj_reg)
       when is_list(elements) do
    case PatternBind.bind(%{kind: :tuple, elements: elements}, ctx, b, subj_reg) do
      {:ok, ctx1, b1} -> {ctx1, b1}
      :unsupported -> {ctx, b}
    end
  end

  defp bind_pattern_pair(ctx, b, %{kind: :constructor, bind: bind, name: _name} = pattern, subj_reg)
       when is_binary(bind) do
    case PatternBind.bind(pattern, ctx, b, subj_reg) do
      {:ok, ctx1, b1} -> {ctx1, b1}
      :unsupported -> {ctx, b}
    end
  end

  defp bind_pattern_pair(ctx, b, %{kind: :constructor} = pattern, subj_reg) do
    case PatternBind.bind(pattern, ctx, b, subj_reg) do
      {:ok, ctx1, b1} -> {ctx1, b1}
      :unsupported -> {ctx, b}
    end
  end

  defp bind_pattern_pair(ctx, b, %{kind: :var, name: name}, subj_reg) when is_binary(name) do
    case PatternBind.bind(%{kind: :var, name: name}, ctx, b, subj_reg) do
      {:ok, ctx1, b1} -> {ctx1, b1}
      :unsupported -> {Context.put_local(ctx, name, subj_reg), Builder.bind_local(b, name, subj_reg)}
    end
  end

  defp bind_pattern_pair(ctx, b, %{kind: :wildcard}, _subj_reg), do: {ctx, b}
  defp bind_pattern_pair(ctx, b, _, _), do: {ctx, b}

  @spec bind_maybe_payload(
          Context.t(),
          Types.pattern(),
          Types.reg(),
          Types.expr() | nil,
          Builder.t()
        ) :: {:ok, Types.reg(), Builder.t(), Context.t()}

  defp bind_maybe_payload(ctx, pattern, subj_reg, subject_expr, b) do
    cond do
      just_arm_pattern?(pattern) and unused_just_payload?(pattern) ->
        {ctx1, b1} = bind_pattern_alias(ctx, b, pattern, subj_reg)
        {:ok, subj_reg, b1, ctx1}

      just_arm_pattern?(pattern) ->
        {:ok, payload_reg, b1} = Expr.compile_runtime_builtin(:maybe_just_payload, [subj_reg], ctx, b)
        # Concrete Maybe payload type (e.g. CurrentDateTime) — not the ctor's
        # type-var `a`. Without this, `now.minute` after `Just now` picks the
        # smallest ambiguous shape (TickSpec.minute@0 = year) and MinuteChanged
        # overwrites year → perpetual companion refetch → double-free.
        ctx0 = PatternBind.enrich_just_payload_type(ctx, pattern, subject_expr)
        {ctx1, b2} = bind_just_payload_pattern(ctx0, b1, pattern, payload_reg)
        # `Just x` stores the payload name in `:bind`. Only `(Just …) as alias`
        # should keep the outer Maybe in `:bind` while `:arg_pattern` holds the
        # inner pattern — alias then, otherwise `Tuple.first x` would see the
        # Maybe wrapper (no `.first`) and bind NULL/0.
        {ctx2, b3} =
          if is_map(Map.get(pattern, :arg_pattern)) do
            bind_pattern_alias(ctx1, b2, pattern, subj_reg)
          else
            {ctx1, b2}
          end

        {:ok, payload_reg, b3, ctx2}

      unwrap_just_pattern?(pattern) ->
        {:ok, payload_reg, b1} = Expr.compile_runtime_builtin(:maybe_just_payload, [subj_reg], ctx, b)
        ctx0 = PatternBind.enrich_just_payload_type(ctx, pattern, subject_expr)
        {ctx1, b2} = bind_pattern_pair(ctx0, b1, pattern, payload_reg)
        {:ok, payload_reg, b2, ctx1}

      true ->
        {ctx1, b2} = bind_pattern_pair(ctx, b, pattern, subj_reg)
        {:ok, subj_reg, b2, ctx1}
    end
  end

  # `(Just _) as found` stores the alias on `bind` via build_pattern_alias.
  @spec bind_pattern_alias(Context.t(), Builder.t(), Types.pattern(), Types.reg()) ::
          {Context.t(), Builder.t()}

  defp bind_pattern_alias(ctx, b, pattern, subject_reg) do
    case Map.get(pattern, :bind) do
      name when is_binary(name) ->
        {Context.put_local(ctx, name, subject_reg), Builder.bind_local(b, name, subject_reg)}

      _ ->
        {ctx, b}
    end
  end

  # After `maybe_just_payload`, the subject is the Just payload — do not run
  # constructor payload extraction again on a `Just …` pattern (that would call
  # `maybe_just_payload` on a bare record and bind NULL fields).
  @spec bind_just_payload_pattern(Context.t(), Builder.t(), Types.pattern(), Types.reg()) ::
          {Context.t(), Builder.t()}

  defp bind_just_payload_pattern(ctx, b, %{kind: :constructor, arg_pattern: inner}, payload_reg)
       when not is_nil(inner) do
    bind_pattern_pair(ctx, b, inner, payload_reg)
  end

  defp bind_just_payload_pattern(ctx, b, %{kind: :constructor, bind: bind}, payload_reg)
       when is_binary(bind) do
    case PatternBind.bind(%{kind: :var, name: bind}, ctx, b, payload_reg) do
      {:ok, ctx1, b1} -> {ctx1, b1}
      :unsupported -> {Context.put_local(ctx, bind, payload_reg), Builder.bind_local(b, bind, payload_reg)}
    end
  end

  defp bind_just_payload_pattern(ctx, b, _pattern, payload_reg) do
    bind_pattern_pair(ctx, b, %{kind: :wildcard}, payload_reg)
  end

  @spec maybe_just_pair?(Types.case_branch(), Types.case_branch()) :: boolean()

  defp maybe_just_pair?(br1, br2) do
    (nothing_arm?(br1) and just_arm?(br2)) or (nothing_arm?(br2) and just_arm?(br1))
  end

  @spec just_arm?(map()) :: boolean()

  defp just_arm?(%{pattern: pattern}), do: just_arm_pattern?(pattern)

  @spec just_arm_pattern?(map() | term()) :: boolean()

  defp just_arm_pattern?(%{kind: :constructor, name: name}) when is_binary(name),
    do: short_ctor_name(name) == "Just"

  defp just_arm_pattern?(%{kind: :qualified_constructor, name: name}) when is_binary(name),
    do: short_ctor_name(name) == "Just"

  defp just_arm_pattern?(%{resolved_name: name}) when is_binary(name),
    do: short_ctor_name(name) == "Just"

  defp just_arm_pattern?(_), do: false

  @spec unwrap_just_pattern?(map() | term()) :: boolean()

  defp unwrap_just_pattern?(%{kind: :var}), do: true
  defp unwrap_just_pattern?(%{kind: :wildcard}), do: true

  defp unwrap_just_pattern?(%{kind: :constructor, bind: bind}) when is_binary(bind),
    do: true

  defp unwrap_just_pattern?(_), do: false

  @spec unused_just_payload?(map() | term()) :: boolean()

  defp unused_just_payload?(%{kind: :constructor, arg_pattern: %{kind: :wildcard}}), do: true
  defp unused_just_payload?(%{kind: :constructor, arg_pattern: nil, bind: nil}), do: true
  defp unused_just_payload?(_), do: false

  @spec nested_maybe_ctor_branches?(list()) :: boolean()

  defp nested_maybe_ctor_branches?(branches) when is_list(branches) do
    fallback_count = Enum.count(branches, &maybe_ctor_fallback_arm?/1)
    just_nested = Enum.filter(branches, &just_nested_ctor_arm?/1)

    fallback_count == 1 and length(just_nested) == length(branches) - 1 and length(branches) >= 2
  end

  @spec maybe_ctor_fallback_arm?(Types.case_branch()) :: boolean()

  defp maybe_ctor_fallback_arm?(branch), do: nothing_arm?(branch) or catch_all_arm?(branch)

  @spec just_nested_ctor_arm?(map()) :: boolean()

  defp just_nested_ctor_arm?(%{pattern: pattern}), do: just_nested_ctor_pattern?(pattern)

  @spec just_nested_ctor_pattern?(map() | term()) :: boolean()

  defp just_nested_ctor_pattern?(%{kind: :constructor} = outer) do
    just_arm_pattern?(outer) and match?(%{kind: :constructor}, Map.get(outer, :arg_pattern))
  end

  defp just_nested_ctor_pattern?(_), do: false

  @spec split_nested_maybe_branches(Types.case_branches()) ::
          {Types.case_branch() | nil, Types.case_branches()}

  defp split_nested_maybe_branches(branches) do
    fallback = Enum.find(branches, &maybe_ctor_fallback_arm?/1)
    nested = Enum.reject(branches, &maybe_ctor_fallback_arm?/1)
    {fallback, nested}
  end

  @spec unwrap_just_nested_branch(Types.case_branch()) :: Types.case_branch()

  defp unwrap_just_nested_branch(%{pattern: %{arg_pattern: inner}, expr: expr}) do
    %{pattern: inner, expr: expr}
  end

  @spec assign_ctor_tags_when_missing(Types.case_branches()) :: Types.case_branches()

  defp assign_ctor_tags_when_missing(branches) when is_list(branches) do
    if Enum.all?(branches, &missing_ctor_tag?/1) do
      Enum.with_index(branches, fn branch, idx ->
        update_in(branch, [:pattern, :tag], fn
          nil -> idx
          tag -> tag
        end)
      end)
    else
      branches
    end
  end

  @spec missing_ctor_tag?(map() | term()) :: boolean()

  defp missing_ctor_tag?(%{pattern: %{kind: :constructor, tag: nil}}), do: true
  defp missing_ctor_tag?(_), do: false

  @spec maybe_append_wildcard_default(Types.case_branches(), Types.case_branch()) ::
          Types.case_branches()

  defp maybe_append_wildcard_default(branches, %{pattern: %{kind: :wildcard}} = fallback_br) do
    branches ++ [%{pattern: %{kind: :wildcard}, expr: Map.get(fallback_br, :expr)}]
  end

  defp maybe_append_wildcard_default(branches, _fallback_br), do: branches

  @spec tag_switch_merge_block_id(Builder.t()) :: non_neg_integer() | nil

  defp tag_switch_merge_block_id(b) do
    Map.get(b, :tag_switch_merge_block) ||
      Enum.find_value(b.blocks, fn blk ->
        if Enum.any?(blk.instrs, &(&1.op == :switch_ctor_tag)), do: blk.id
      end)
  end
end
