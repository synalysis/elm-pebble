defmodule Elmc.Backend.Plan.Lower.Case.ListSwitch do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec branches?(list()) :: boolean()
  def branches?(branches) when is_list(branches) do
    length(branches) == 2 and cons_branch(branches) != nil and empty_branch(branches) != nil
  end

  def branches?(_), do: false

  @spec double_cons_wildcard_branches?(list()) :: boolean()
  def double_cons_wildcard_branches?(branches) when is_list(branches) do
    length(branches) == 2 and double_cons_branch(branches) != nil and wildcard_branch(branches) != nil
  end

  def double_cons_wildcard_branches?(_), do: false

  @spec compile_double_cons_wildcard(map(), list(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_double_cons_wildcard(subject, branches, ctx, b) do
    cons = double_cons_branch(branches)
    wild = wildcard_branch(branches)

    with {:ok, a_name, b_name, rest_name} <- double_cons_names(cons),
         {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         saved_pending = Map.get(b1, :pending_merge_block),
         {:ok, empty_subj_reg, b2} <- emit_test_list_empty(subj_reg, b1),
         wild_id = b2.next_block,
         peek_id = wild_id + 1,
         wild2_id = peek_id + 1,
         cons_id = wild2_id + 1,
         merge_id = skip_reserved(cons_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, wild_id, peek_id, empty_subj_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, wild_reg, wild_exit, b_wild} <-
           compile_arm(Map.get(wild, :expr), ctx, b_reserved, wild_id),
         b_wild_done = Builder.patch_terminator(b_wild, wild_exit, {:br, merge_id}),
         {:ok, empty_tail_reg, _peek_exit, b_peek} <-
           compile_double_cons_peek(
             subj_reg,
             a_name,
             b_name,
             rest_name,
             wild2_id,
             cons_id,
             ctx,
             b_wild_done,
             peek_id
           ),
         {:ok, wild2_reg, wild2_exit, b_wild2} <-
           compile_arm(Map.get(wild, :expr), ctx, b_peek, wild2_id),
         b_wild2_done = Builder.patch_terminator(b_wild2, wild2_exit, {:br, merge_id}),
         {:ok, cons_reg, cons_exit, b_cons} <-
           compile_double_cons_arm(
             Map.get(cons, :expr),
             a_name,
             b_name,
             rest_name,
             subj_reg,
             ctx,
             b_wild2_done,
             cons_id
           ),
         b_cons_done = Builder.patch_terminator(b_cons, cons_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_cons_done, merge_id),
         {:ok, merge, b_out} <-
           emit_nested_merge(empty_subj_reg, wild_reg, empty_tail_reg, wild2_reg, cons_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec compile(map(), list(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile(subject, branches, ctx, b) do
    cons = cons_branch(branches)
    empty = empty_branch(branches)

    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         {head_name, tail_name} <- cons_names(cons),
         saved_pending = Map.get(b1, :pending_merge_block),
         {:ok, cond_reg, b2} <- emit_test_list_empty(subj_reg, b1),
         then_id = b2.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, then_id, else_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, empty_reg, empty_exit, b_empty} <-
           compile_arm(Map.get(empty, :expr), ctx, b_reserved, then_id),
         b_empty_done = Builder.patch_terminator(b_empty, empty_exit, {:br, merge_id}),
         {:ok, cons_reg, cons_exit, b_cons} <-
           compile_cons_arm(
             Map.get(cons, :expr),
             head_name,
             tail_name,
             subj_reg,
             ctx,
             b_empty_done,
             else_id
           ),
         b_cons_done = Builder.patch_terminator(b_cons, cons_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_cons_done, merge_id),
         {:ok, merge, b_out} <-
           emit_merge(cond_reg, empty_reg, cons_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp cons_branch(branches) do
    Enum.find(branches, &cons_pattern?/1)
  end

  defp empty_branch(branches) do
    Enum.find(branches, &empty_pattern?/1)
  end

  defp wildcard_branch(branches) do
    Enum.find(branches, &wildcard_pattern?/1)
  end

  defp double_cons_branch(branches) do
    Enum.find(branches, &double_cons_pattern?/1)
  end

  defp wildcard_pattern?(%{pattern: %{kind: :wildcard}}), do: true
  defp wildcard_pattern?(%{pattern: %{kind: :var}}), do: true
  defp wildcard_pattern?(_), do: false

  defp double_cons_pattern?(%{pattern: pattern}), do: double_cons_pattern?(pattern)

  defp double_cons_pattern?(%{
         kind: :constructor,
         name: name,
         arg_pattern: %{kind: :tuple, elements: [_head, tail]}
       }) do
    short_name(name) == "::" and nested_cons_pattern?(tail)
  end

  defp double_cons_pattern?(%{
         resolved_name: "List.::",
         arg_pattern: %{kind: :tuple, elements: [head, tail]}
       }) do
    nested_cons_pattern?(tail) and var_pattern?(head)
  end

  defp double_cons_pattern?(_), do: false

  defp nested_cons_pattern?(%{
         kind: :constructor,
         name: name,
         arg_pattern: %{kind: :tuple, elements: [head, tail]}
       }) do
    short_name(name) == "::" and var_pattern?(head) and var_pattern?(tail)
  end

  defp nested_cons_pattern?(%{
         resolved_name: "List.::",
         arg_pattern: %{kind: :tuple, elements: [head, tail]}
       }) do
    var_pattern?(head) and var_pattern?(tail)
  end

  defp nested_cons_pattern?(_), do: false

  defp var_pattern?(%{kind: :var, name: name}) when is_binary(name), do: true
  defp var_pattern?(_), do: false

  defp double_cons_names(%{pattern: pattern}) do
    case nested_cons_elements(pattern) do
      [a, b, rest] -> {:ok, var_name(a), var_name(b), var_name(rest)}
      _ -> :error
    end
  end

  defp nested_cons_elements(%{arg_pattern: %{elements: [head, tail]}}) do
    case tail do
      %{arg_pattern: %{elements: elements}} -> [head | elements]
      _ -> :error
    end
  end

  defp nested_cons_elements(_), do: :error

  defp cons_pattern?(%{pattern: pattern}), do: cons_pattern?(pattern)

  defp cons_pattern?(%{kind: :constructor, name: name, arg_pattern: %{kind: :tuple, elements: elements}})
       when is_list(elements) and length(elements) == 2 do
    short_name(name) == "::"
  end

  defp cons_pattern?(%{resolved_name: "List.::", arg_pattern: %{kind: :tuple, elements: elements}})
       when is_list(elements) and length(elements) == 2,
       do: true

  defp cons_pattern?(_), do: false

  defp empty_pattern?(%{pattern: %{kind: :constructor, name: name}}),
    do: short_name(name) == "[]"

  defp empty_pattern?(%{pattern: %{resolved_name: "[]"}}), do: true
  defp empty_pattern?(_), do: false

  defp short_name("::"), do: "::"
  defp short_name("[]"), do: "[]"

  defp short_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  defp cons_names(%{pattern: %{arg_pattern: %{elements: [head, tail]}}}) do
    {var_name(head), var_name(tail)}
  end

  defp var_name(%{kind: :var, name: name}) when is_binary(name), do: name
  defp var_name(_), do: "head"

  defp compile_arm(expr, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)

    case Expr.compile(expr, ctx, b_arm) do
      {:ok, reg, b1} ->
        exit_id = b1.current_block.id
        {:ok, reg, exit_id, Builder.finish_block(b1, :none)}

      :unsupported ->
        :unsupported
    end
  end

  defp compile_cons_arm(expr, head_name, tail_name, subj_reg, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    # Head and tail both read the same list; dup before the second use so consume
    # nulling after list_head does not pass NULL to list_tail.
    {[head_arg, tail_arg], b_dup} = Builder.dup_regs_for_consume(b_arm, [subj_reg, subj_reg])

    with {:ok, head_maybe, b1} <- Expr.compile_runtime_builtin(:list_head, [head_arg], ctx, b_dup),
         {:ok, head_reg, b2} <- Expr.compile_runtime_builtin(:maybe_just_payload, [head_maybe], ctx, b1),
         {:ok, tail_maybe, b3} <- Expr.compile_runtime_builtin(:list_tail, [tail_arg], ctx, b2),
         {:ok, tail_reg, b4} <- Expr.compile_runtime_builtin(:maybe_just_payload, [tail_maybe], ctx, b3),
         ctx1 <-
           ctx
           |> Context.put_local(head_name, head_reg)
           |> Context.put_local(tail_name, tail_reg),
         b5 <-
           b4
           |> Builder.bind_local(head_name, head_reg)
           |> Builder.bind_local(tail_name, tail_reg),
         {:ok, reg, b6} <- Expr.compile(expr, ctx1, b5) do
      exit_id = b6.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b6, :none)}
    else
      _ -> :unsupported
    end
  end

  defp compile_double_cons_peek(
         subj_reg,
         _a_name,
         _b_name,
         _rest_name,
         wild2_id,
         cons_id,
         ctx,
         b,
         peek_id
       ) do
    b_arm = Builder.begin_cfg_arm_block(b, peek_id)
    {[head_arg, tail_arg], b_dup} = Builder.dup_regs_for_consume(b_arm, [subj_reg, subj_reg])

    with {:ok, head_maybe, b1} <- Expr.compile_runtime_builtin(:list_head, [head_arg], ctx, b_dup),
         {:ok, _a_reg, b2} <-
           Expr.compile_runtime_builtin(:maybe_just_payload, [head_maybe], ctx, b1),
         {:ok, tail_maybe, b3} <- Expr.compile_runtime_builtin(:list_tail, [tail_arg], ctx, b2),
         {:ok, t1_reg, b4} <-
           Expr.compile_runtime_builtin(:maybe_just_payload, [tail_maybe], ctx, b3),
         {:ok, empty_tail_reg, b5} <- emit_test_list_empty(t1_reg, b4) do
      exit_id = b5.current_block.id
      b6 = Builder.finish_block(b5, {:br_if, wild2_id, cons_id, empty_tail_reg})
      {:ok, empty_tail_reg, exit_id, b6}
    end
  end

  defp compile_double_cons_arm(expr, a_name, b_name, rest_name, subj_reg, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    {[subj_a, subj_b], b0} = Builder.dup_regs_for_consume(b_arm, [subj_reg, subj_reg])

    with {:ok, head_maybe, b1} <- Expr.compile_runtime_builtin(:list_head, [subj_a], ctx, b0),
         {:ok, a_reg, b2} <- Expr.compile_runtime_builtin(:maybe_just_payload, [head_maybe], ctx, b1),
         {:ok, tail_maybe, b3} <- Expr.compile_runtime_builtin(:list_tail, [subj_b], ctx, b2),
         {:ok, t1_reg, b4} <- Expr.compile_runtime_builtin(:maybe_just_payload, [tail_maybe], ctx, b3),
         {[t1_a, t1_b], b5} = Builder.dup_regs_for_consume(b4, [t1_reg, t1_reg]),
         {:ok, b_head_maybe, b6} <- Expr.compile_runtime_builtin(:list_head, [t1_a], ctx, b5),
         {:ok, b_reg, b7} <- Expr.compile_runtime_builtin(:maybe_just_payload, [b_head_maybe], ctx, b6),
         {:ok, rest_maybe, b8} <- Expr.compile_runtime_builtin(:list_tail, [t1_b], ctx, b7),
         {:ok, rest_reg, b9} <-
           Expr.compile_runtime_builtin(:maybe_just_payload, [rest_maybe], ctx, b8),
         ctx1 <-
           ctx
           |> Context.put_local(a_name, a_reg)
           |> Context.put_local(b_name, b_reg)
           |> Context.put_local(rest_name, rest_reg),
         b10 <-
           b9
           |> Builder.bind_local(a_name, a_reg)
           |> Builder.bind_local(b_name, b_reg)
           |> Builder.bind_local(rest_name, rest_reg),
         {:ok, reg, b11} <- Expr.compile(expr, ctx1, b10) do
      exit_id = b11.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b11, :none)}
    else
      _ -> :unsupported
    end
  end

  defp emit_test_list_empty(subj_reg, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_list_empty, %{
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

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id

  defp emit_merge(cond_reg, empty_reg, cons_reg, b) do
    {merge, b1} = Builder.fresh_reg(b)

    phi_consumes =
      Builder.phi_branch_consumes(b1, [empty_reg, cons_reg, cond_reg])

    {_, b2} =
      Builder.emit(b1, :phi, %{
        dest: merge,
        args: %{then: empty_reg, else: cons_reg, cond: cond_reg},
        effects: %{
          produces: {:owned, merge},
          consumes: phi_consumes,
          borrows: [],
          fallible: false
        }
      })

    {:ok, merge, b2}
  end

  defp emit_nested_merge(empty_subj_reg, wild_reg, empty_tail_reg, wild2_reg, cons_reg, b) do
    with {:ok, inner, b1} <- emit_merge(empty_tail_reg, wild2_reg, cons_reg, b),
         {:ok, outer, b2} <- emit_merge(empty_subj_reg, wild_reg, inner, b1) do
      {:ok, outer, b2}
    end
  end
end
