defmodule Elmc.Backend.Plan.Lower.Case do
  @moduledoc false

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Case.{GuardedSwitch, IntSwitch, ListSwitch, TagSwitch}
  alias Elmc.Backend.Plan.Lower.{Expr, PatternBind}
  alias Elmc.Backend.Plan.Types

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out | nil, Builder.t()} | :unsupported
  def compile(%{subject: subject, branches: [br1, br2]}, ctx, b)
      when is_map(br1) and is_map(br2) do
    cond do
      nothing_arm?(br1) and catch_all_arm?(br2) ->
        compile_maybe_nothing_case(subject_expr(subject), br1, br2, ctx, b)

      nothing_arm?(br2) and catch_all_arm?(br1) ->
        compile_maybe_nothing_case(subject_expr(subject), br2, br1, ctx, b)

      maybe_just_pair?(br1, br2) ->
        {nothing_br, just_br} = if nothing_arm?(br1), do: {br1, br2}, else: {br2, br1}
        compile_maybe_nothing_case(subject_expr(subject), nothing_br, just_br, ctx, b)

      true ->
        compile_dispatch(
          %{subject: subject_expr(subject), branches: [br1, br2]},
          subject_expr(subject),
          [br1, br2],
          ctx,
          b
        )
    end
  end

  def compile(%{subject: subject, branches: branches} = expr, ctx, b) when is_list(branches) do
    subj = subject_expr(subject)

    cond do
      nested_maybe_ctor_branches?(branches) ->
        compile_nested_maybe_ctor_case(subj, branches, ctx, b)

      true ->
        compile_dispatch(expr, subj, branches, ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  defp subject_expr(name) when is_binary(name), do: %{op: :var, name: name}
  defp subject_expr(expr) when is_map(expr), do: expr
  defp subject_expr(_), do: %{op: :int_literal, value: 0}

  defp compile_dispatch(_expr, subject, branches, ctx, b) do
    branches = normalize_case_branches(branches)

    cond do
      ListSwitch.fixed_length_nil_branches?(branches) ->
        ListSwitch.compile_fixed_length_nil(subject, branches, ctx, b)

      ListSwitch.triple_branches?(branches) ->
        ListSwitch.compile_triple(subject, branches, ctx, b)

      ListSwitch.double_cons_wildcard_branches?(branches) ->
        ListSwitch.compile_double_cons_wildcard(subject, branches, ctx, b)

      ListSwitch.empty_var_branches?(branches) ->
        ListSwitch.compile_empty_var(subject, branches, ctx, b)

      ListSwitch.branches?(branches) -> ListSwitch.compile(subject, branches, ctx, b)
      TagSwitch.branches?(branches) -> TagSwitch.compile(subject, branches, ctx, b)
      IntSwitch.branches?(branches) -> IntSwitch.compile(subject, branches, ctx, b)
      GuardedSwitch.branches?(branches) -> GuardedSwitch.compile(subject, branches, ctx, b)
      true -> compile_linear_branches(branches, subject, ctx, b)
    end
  end

  defp compile_nested_maybe_ctor_case(subject, branches, ctx, b) do
    {fallback_br, just_nested} = split_nested_maybe_branches(branches)

    inner_branches =
      just_nested
      |> Enum.map(&unwrap_just_nested_branch/1)
      |> assign_ctor_tags_when_missing()
      |> maybe_append_wildcard_default(fallback_br)

    payload_name = "__maybe_inner"

    saved_pending = Map.get(b, :pending_merge_block)

    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
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
         {:ok, merge, b_out} <- emit_merge(cond_reg, then_reg, else_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp compile_maybe_nothing_case(subject, nothing_br, other_br, ctx, b) do
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
             ctx,
             b_then_done,
             else_id
           ),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <- emit_merge(cond_reg, then_reg, else_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

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

  defp compile_maybe_else_branch(pattern, expr, subj_reg, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    with {:ok, _payload_reg, b1, else_ctx} <- bind_maybe_payload(arm_ctx, pattern, subj_reg, b_arm),
         {:ok, reg, b2} <- Expr.compile(expr, else_ctx, b1) do
      exit_id = b2.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b2, :none)}
    else
      _ -> :unsupported
    end
  end

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id

  defp emit_merge(cond_reg, then_reg, else_reg, b) do
    {merge, b1} = Builder.fresh_reg(b)

    phi_consumes =
      Builder.phi_branch_consumes(b, [then_reg, else_reg, cond_reg])

    {_, b2} =
      Builder.emit(b1, :phi, %{
        dest: merge,
        args: %{then: then_reg, else: else_reg, cond: cond_reg},
        effects: %{
          produces: {:owned, merge},
          consumes: phi_consumes,
          borrows: [],
          fallible: false
        }
      })

    {:ok, merge, b2}
  end

  defp compile_linear_branches(branches, subject, ctx, b) do
    cond do
      tagged_constructor_branches?(branches) ->
        TagSwitch.compile(subject, branches, ctx, b)

      GuardedSwitch.branches?(branches) ->
        GuardedSwitch.compile(subject, branches, ctx, b)

      true ->
        :unsupported
    end
  end

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

  defp tagged_constructor_branches?(branches) when is_list(branches) do
    Enum.count(branches, fn branch ->
      case Map.get(branch, :pattern) do
        %{kind: :constructor, tag: tag} when is_integer(tag) -> true
        _ -> false
      end
    end) >= 2
  end

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

  defp catch_all_arm?(%{pattern: %{kind: :var}}), do: true
  defp catch_all_arm?(%{pattern: %{kind: :wildcard}}), do: true

  defp catch_all_arm?(%{pattern: %{kind: :constructor, bind: bind}}) when is_binary(bind),
    do: true

  defp catch_all_arm?(_), do: false

  defp short_ctor_name(name) do
    name |> String.split(".") |> List.last()
  end

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
    {Context.put_local(ctx, name, subj_reg), Builder.bind_local(b, name, subj_reg)}
  end

  defp bind_pattern_pair(ctx, b, %{kind: :wildcard}, _subj_reg), do: {ctx, b}
  defp bind_pattern_pair(ctx, b, _, _), do: {ctx, b}

  defp bind_maybe_payload(ctx, pattern, subj_reg, b) do
    cond do
      just_arm_pattern?(pattern) and unused_just_payload?(pattern) ->
        {:ok, subj_reg, b, ctx}

      just_arm_pattern?(pattern) ->
        {:ok, payload_reg, b1} = Expr.compile_runtime_builtin(:maybe_just_payload, [subj_reg], ctx, b)
        {ctx1, b2} = bind_just_payload_pattern(ctx, b1, pattern, payload_reg)
        {:ok, payload_reg, b2, ctx1}

      unwrap_just_pattern?(pattern) ->
        {:ok, payload_reg, b1} = Expr.compile_runtime_builtin(:maybe_just_payload, [subj_reg], ctx, b)
        {ctx1, b2} = bind_pattern_pair(ctx, b1, pattern, payload_reg)
        {:ok, payload_reg, b2, ctx1}

      true ->
        {ctx1, b2} = bind_pattern_pair(ctx, b, pattern, subj_reg)
        {:ok, subj_reg, b2, ctx1}
    end
  end

  # After `maybe_just_payload`, the subject is the Just payload — do not run
  # constructor payload extraction again on a `Just …` pattern (that would call
  # `maybe_just_payload` on a bare record and bind NULL fields).
  defp bind_just_payload_pattern(ctx, b, %{kind: :constructor, arg_pattern: inner}, payload_reg)
       when not is_nil(inner) do
    bind_pattern_pair(ctx, b, inner, payload_reg)
  end

  defp bind_just_payload_pattern(ctx, b, %{kind: :constructor, bind: bind}, payload_reg)
       when is_binary(bind) do
    {Context.put_local(ctx, bind, payload_reg), Builder.bind_local(b, bind, payload_reg)}
  end

  defp bind_just_payload_pattern(ctx, b, _pattern, payload_reg) do
    bind_pattern_pair(ctx, b, %{kind: :wildcard}, payload_reg)
  end

  defp maybe_just_pair?(br1, br2) do
    (nothing_arm?(br1) and just_arm?(br2)) or (nothing_arm?(br2) and just_arm?(br1))
  end

  defp just_arm?(%{pattern: pattern}), do: just_arm_pattern?(pattern)

  defp just_arm_pattern?(%{kind: :constructor, name: name}) when is_binary(name),
    do: short_ctor_name(name) == "Just"

  defp just_arm_pattern?(%{kind: :qualified_constructor, name: name}) when is_binary(name),
    do: short_ctor_name(name) == "Just"

  defp just_arm_pattern?(%{resolved_name: name}) when is_binary(name),
    do: short_ctor_name(name) == "Just"

  defp just_arm_pattern?(_), do: false

  defp unwrap_just_pattern?(%{kind: :var}), do: true
  defp unwrap_just_pattern?(%{kind: :wildcard}), do: true

  defp unwrap_just_pattern?(%{kind: :constructor, bind: bind}) when is_binary(bind),
    do: true

  defp unwrap_just_pattern?(_), do: false

  defp unused_just_payload?(%{kind: :constructor, arg_pattern: %{kind: :wildcard}}), do: true
  defp unused_just_payload?(%{kind: :constructor, arg_pattern: nil, bind: nil}), do: true
  defp unused_just_payload?(_), do: false

  defp nested_maybe_ctor_branches?(branches) when is_list(branches) do
    fallback_count = Enum.count(branches, &maybe_ctor_fallback_arm?/1)
    just_nested = Enum.filter(branches, &just_nested_ctor_arm?/1)

    fallback_count == 1 and length(just_nested) == length(branches) - 1 and length(branches) >= 2
  end

  defp maybe_ctor_fallback_arm?(branch), do: nothing_arm?(branch) or catch_all_arm?(branch)

  defp just_nested_ctor_arm?(%{pattern: pattern}), do: just_nested_ctor_pattern?(pattern)

  defp just_nested_ctor_pattern?(%{kind: :constructor} = outer) do
    just_arm_pattern?(outer) and match?(%{kind: :constructor}, Map.get(outer, :arg_pattern))
  end

  defp just_nested_ctor_pattern?(_), do: false

  defp split_nested_maybe_branches(branches) do
    fallback = Enum.find(branches, &maybe_ctor_fallback_arm?/1)
    nested = Enum.reject(branches, &maybe_ctor_fallback_arm?/1)
    {fallback, nested}
  end

  defp unwrap_just_nested_branch(%{pattern: %{arg_pattern: inner}, expr: expr}) do
    %{pattern: inner, expr: expr}
  end

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

  defp missing_ctor_tag?(%{pattern: %{kind: :constructor, tag: nil}}), do: true
  defp missing_ctor_tag?(_), do: false

  defp maybe_append_wildcard_default(branches, %{pattern: %{kind: :wildcard}} = fallback_br) do
    branches ++ [%{pattern: %{kind: :wildcard}, expr: Map.get(fallback_br, :expr)}]
  end

  defp maybe_append_wildcard_default(branches, _fallback_br), do: branches

  defp tag_switch_merge_block_id(b) do
    Map.get(b, :tag_switch_merge_block) ||
      Enum.find_value(b.blocks, fn blk ->
        if Enum.any?(blk.instrs, &(&1.op == :switch_ctor_tag)), do: blk.id
      end)
  end
end
