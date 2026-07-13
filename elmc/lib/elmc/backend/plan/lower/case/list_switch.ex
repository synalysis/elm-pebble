defmodule Elmc.Backend.Plan.Lower.Case.ListSwitch do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Expr, ListIntType}
  alias Elmc.Backend.Plan.Types

  @spec branches?(Types.case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    length(branches) == 2 and cons_branch(branches) != nil and empty_branch(branches) != nil
  end

  def branches?(_), do: false

  @spec empty_var_branches?(Types.case_branches()) :: boolean()
  def empty_var_branches?(branches) when is_list(branches) do
    length(branches) == 2 and empty_branch(branches) != nil and
      (var_branch(branches) != nil or wildcard_branch(branches) != nil)
  end

  def empty_var_branches?(_), do: false

  @spec compile_empty_var(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_empty_var(subject, branches, ctx, b) do
    empty = empty_branch(branches)
    var = var_branch(branches) || wildcard_branch(branches)

    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         saved_pending = Map.get(b1, :pending_merge_block),
         {:ok, cond_reg, b2} <- emit_test_list_empty(subj_reg, b1),
         empty_id = b2.next_block,
         var_id = empty_id + 1,
         merge_id = skip_reserved(var_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, empty_id, var_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, empty_reg, empty_exit, b_empty} <-
           compile_arm(Map.get(empty, :expr), ctx, b_reserved, empty_id),
         b_empty_done = Builder.patch_terminator(b_empty, empty_exit, {:br, merge_id}),
         {:ok, var_reg, var_exit, b_var} <-
           compile_nonempty_var_arm(var, subj_reg, ctx, b_empty_done, var_id),
         b_var_done = Builder.patch_terminator(b_var, var_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_var_done, merge_id),
         {:ok, merge, b_out} <- emit_merge(cond_reg, empty_reg, var_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec double_cons_wildcard_branches?(Types.case_branches()) :: boolean()
  def double_cons_wildcard_branches?(branches) when is_list(branches) do
    length(branches) == 2 and double_cons_branch(branches) != nil and wildcard_branch(branches) != nil
  end

  def double_cons_wildcard_branches?(_), do: false

  @spec compile_double_cons_wildcard(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
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
             subject,
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
             subject,
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

  @spec triple_branches?(Types.case_branches()) :: boolean()
  def triple_branches?(branches) when is_list(branches) do
    length(branches) == 3 and
      empty_branch(branches) != nil and
      double_cons_branch(branches) != nil and
      single_cons_empty_tail_branch(branches) != nil
  end

  def triple_branches?(_), do: false

  @spec fixed_length_nil_branches?(Types.case_branches()) :: boolean()
  def fixed_length_nil_branches?(branches) when is_list(branches) and length(branches) >= 2 do
    {fixed, default} = split_fixed_nil_and_default(branches)

    fixed != [] and default != nil and
      Enum.all?(fixed, fn branch -> match?({:ok, _}, parse_cons_nil_vars(Map.get(branch, :pattern))) end) and
      fixed |> Enum.map(fn branch -> elem(parse_cons_nil_vars(Map.get(branch, :pattern)), 1) |> length() end) |> Enum.uniq() |> length() ==
        length(fixed)
  end

  def fixed_length_nil_branches?(_), do: false

  @spec compile_fixed_length_nil(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_fixed_length_nil(subject, branches, ctx, b) do
    {fixed_branches, default_branch} = split_fixed_nil_and_default(branches)

    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         {:ok, arms_by_len} <- fixed_nil_arms_by_length(fixed_branches),
         max_len <- arms_by_len |> Map.keys() |> Enum.max(),
         saved_pending = Map.get(b1, :pending_merge_block),
         {:ok, empty_cond, b2} <- emit_test_list_empty(subj_reg, b1),
         default_id = b2.next_block,
         peel_start_id = default_id + 1,
         merge_id = skip_reserved(peel_start_id + max_len * 2 + 2, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, default_id, peel_start_id, empty_cond}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, default_reg, default_exit, b_default} <-
           compile_arm(Map.get(default_branch, :expr), ctx, b_reserved, default_id),
         b_default_done = Builder.patch_terminator(b_default, default_exit, {:br, merge_id}),
         {:ok, arm_results, b_peel} <-
           compile_fixed_nil_peel_chain(
             arms_by_len,
             max_len,
             subject,
             subj_reg,
             ctx,
             b_default_done,
             peel_start_id,
             default_id
           ),
         b_peel_done =
           Enum.reduce(arm_results, b_peel, fn {_len, _reg, exit_id, _names}, b_acc ->
             Builder.patch_terminator(b_acc, exit_id, {:br, merge_id})
           end),
         b_merge = Builder.begin_block(b_peel_done, merge_id),
         {:ok, merge, b_out} <- emit_fixed_nil_merge(empty_cond, arm_results, default_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec compile_triple(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_triple(subject, branches, ctx, b) do
    empty = empty_branch(branches)
    double = double_cons_branch(branches)
    single = single_cons_empty_tail_branch(branches)

    with {:ok, a_name, b_name, rest_name} <- double_cons_names(double),
         {:ok, only_name} <- single_cons_only_name(single),
         {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         saved_pending = Map.get(b1, :pending_merge_block),
         {:ok, empty_cond, b2} <- emit_test_list_empty(subj_reg, b1),
         empty_id = b2.next_block,
         peel_id = empty_id + 1,
         single_id = peel_id + 1,
         double_id = single_id + 1,
         merge_id = skip_reserved(double_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, empty_id, peel_id, empty_cond}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, empty_reg, empty_exit, b_empty} <-
           compile_arm(Map.get(empty, :expr), ctx, b_reserved, empty_id),
         b_empty_done = Builder.patch_terminator(b_empty, empty_exit, {:br, merge_id}),
         {:ok, t1_empty_cond, single_reg, single_exit, double_reg, double_exit, b_arms} <-
           compile_triple_nonempty_arms(
             Map.get(single, :expr),
             Map.get(double, :expr),
             a_name,
             b_name,
             rest_name,
             only_name,
             subject,
             subj_reg,
             ctx,
             b_empty_done,
             peel_id,
             single_id,
             double_id
           ),
         b_arms_done =
           b_arms
           |> Builder.patch_terminator(single_exit, {:br, merge_id})
           |> Builder.patch_terminator(double_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_arms_done, merge_id),
         {:ok, merge, b_out} <-
           emit_triple_merge(empty_cond, t1_empty_cond, empty_reg, single_reg, double_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec compile(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
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
             subject,
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

  defp single_cons_empty_tail_branch(branches) do
    Enum.find(branches, &single_cons_empty_tail_pattern?/1)
  end

  defp single_cons_empty_tail_pattern?(%{pattern: pattern}),
    do: single_cons_empty_tail_pattern?(pattern)

  defp single_cons_empty_tail_pattern?(%{
         resolved_name: "List.::",
         arg_pattern: %{kind: :tuple, elements: [head, tail]}
       }) do
    var_pattern?(head) and empty_list_pattern?(tail)
  end

  defp single_cons_empty_tail_pattern?(%{
         kind: :constructor,
         name: name,
         arg_pattern: %{kind: :tuple, elements: [head, tail]}
       }) do
    short_name(name) == "::" and var_pattern?(head) and empty_list_pattern?(tail)
  end

  defp single_cons_empty_tail_pattern?(_), do: false

  defp empty_list_pattern?(%{kind: :constructor, name: name}), do: short_name(name) == "[]"
  defp empty_list_pattern?(%{resolved_name: "[]"}), do: true
  defp empty_list_pattern?(_), do: false

  defp single_cons_only_name(%{pattern: pattern}) do
    case pattern do
      %{arg_pattern: %{elements: [head, _tail]}} -> {:ok, var_name(head)}
      _ -> :error
    end
  end

  defp wildcard_branch(branches) do
    Enum.find(branches, fn branch -> wildcard_pattern?(Map.get(branch, :pattern)) end)
  end

  defp var_branch(branches) do
    Enum.find(branches, fn branch -> var_pattern_only?(Map.get(branch, :pattern)) end)
  end

  defp var_pattern_only?(%{kind: :var, name: name}) when is_binary(name), do: true
  defp var_pattern_only?(_), do: false

  defp double_cons_branch(branches) do
    Enum.find(branches, &double_cons_pattern?/1)
  end

  defp wildcard_pattern?(%{kind: :wildcard}), do: true
  defp wildcard_pattern?(%{kind: :var}), do: true
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
  defp var_pattern?(%{kind: :wildcard}), do: true
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
  defp var_name(%{kind: :wildcard}), do: "_"
  defp var_name(_), do: "head"

  defp compile_arm(expr, ctx, b, block_id) do
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

  defp compile_cons_arm(expr, head_name, tail_name, subject, subj_reg, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)
    {[head_arg, tail_arg], b_dup} = Builder.dup_regs_for_consume(b_arm, [subj_reg, subj_reg])

    peel =
      if ListIntType.list_int_subject?(ctx, subject) do
        :int_list
      else
        :maybe_list
      end

    with {:ok, head_reg, tail_reg, b_bound} <-
           peel_cons_regs(peel, head_arg, tail_arg, arm_ctx, b_dup),
         ctx1 <-
           arm_ctx
           |> Context.put_local(head_name, head_reg)
           |> Context.put_local(tail_name, tail_reg),
         b5 <-
           b_bound
           |> Builder.bind_local(head_name, head_reg)
           |> Builder.bind_local(tail_name, tail_reg),
         {:ok, reg, b6} <- Expr.compile(expr, ctx1, b5) do
      exit_id = b6.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b6, :none)}
    else
      _ -> :unsupported
    end
  end

  defp compile_nonempty_var_arm(%{pattern: pattern, expr: expr}, subj_reg, ctx, b, block_id) do
    compile_nonempty_var_arm(pattern, expr, subj_reg, ctx, b, block_id)
  end

  defp compile_nonempty_var_arm(%{kind: :var, name: name}, expr, subj_reg, ctx, b, block_id)
       when is_binary(name) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    ctx1 = Context.put_local(arm_ctx, name, subj_reg)
    b1 = Builder.bind_local(b_arm, name, subj_reg)

    case Expr.compile(expr, ctx1, b1) do
      {:ok, reg, b2} ->
        exit_id = b2.current_block.id
        {:ok, reg, exit_id, Builder.finish_block(b2, :none)}

      :unsupported ->
        :unsupported
    end
  end

  defp compile_nonempty_var_arm(%{kind: :wildcard}, expr, _subj_reg, ctx, b, block_id) do
    compile_arm(expr, ctx, b, block_id)
  end

  defp compile_nonempty_var_arm(_, _, _, _, _, _), do: :unsupported

  defp peel_cons_regs(peel, head_arg, tail_arg, ctx, b) do
    ctx = Context.for_branch_arm(ctx)
    peel_cons_regs_impl(peel, head_arg, tail_arg, ctx, b)
  end

  defp peel_cons_regs_impl(:int_list, head_arg, tail_arg, ctx, b) do
    with {:ok, head_reg, b1} <-
           Expr.compile_runtime_builtin(:int_list_head_int, [head_arg], ctx, b),
         {:ok, tail_reg, b2} <-
           Expr.compile_runtime_builtin(:int_list_tail, [tail_arg], ctx, b1) do
      {:ok, head_reg, tail_reg, b2}
    end
  end

  defp peel_cons_regs_impl(:maybe_list, head_arg, tail_arg, ctx, b) do
    with {:ok, head_maybe, b1} <- Expr.compile_runtime_builtin(:list_head, [head_arg], ctx, b),
         {:ok, head_reg, b2} <- Expr.compile_runtime_builtin(:maybe_just_payload, [head_maybe], ctx, b1),
         {:ok, tail_maybe, b3} <- Expr.compile_runtime_builtin(:list_tail, [tail_arg], ctx, b2),
         {:ok, tail_reg, b4} <- Expr.compile_runtime_builtin(:maybe_just_payload, [tail_maybe], ctx, b3) do
      {:ok, head_reg, tail_reg, b4}
    end
  end

  defp compile_double_cons_peek(
         subject,
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
    peel = if ListIntType.list_int_subject?(ctx, subject), do: :int_list, else: :maybe_list

    with {:ok, _head_reg, tail_reg, b_bound} <- peel_cons_regs(peel, head_arg, tail_arg, ctx, b_dup),
         {:ok, empty_tail_reg, b5} <- emit_test_list_empty(tail_reg, b_bound) do
      exit_id = b5.current_block.id
      b6 = Builder.finish_block(b5, {:br_if, wild2_id, cons_id, empty_tail_reg})
      {:ok, empty_tail_reg, exit_id, b6}
    end
  end

  @dialyzer {:nowarn_function, compile_double_cons_arm: 9}
  defp compile_double_cons_arm(expr, a_name, b_name, rest_name, subject, subj_reg, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)
    {[subj_a, subj_b], b0} = Builder.dup_regs_for_consume(b_arm, [subj_reg, subj_reg])
    peel = if ListIntType.list_int_subject?(ctx, subject), do: :int_list, else: :maybe_list

    case peel_cons_regs(peel, subj_a, subj_b, arm_ctx, b0) do
      {:ok, a_reg, t1_reg, b1} ->
        {[t1_a, t1_b], b2} = Builder.dup_regs_for_consume(b1, [t1_reg, t1_reg])

        case peel_cons_regs(peel, t1_a, t1_b, arm_ctx, b2) do
          {:ok, b_reg, rest_reg, b_bound} ->
            ctx1 =
              arm_ctx
              |> Context.put_local(a_name, a_reg)
              |> Context.put_local(b_name, b_reg)
              |> Context.put_local(rest_name, rest_reg)

            b6 =
              b_bound
              |> Builder.bind_local(a_name, a_reg)
              |> Builder.bind_local(b_name, b_reg)
              |> Builder.bind_local(rest_name, rest_reg)

            case Expr.compile(expr, ctx1, b6) do
              {:ok, reg, b7} ->
                exit_id = b7.current_block.id
                {:ok, reg, exit_id, Builder.finish_block(b7, :none)}

              :unsupported ->
                :unsupported
            end
        end
    end
  end

  defp split_fixed_nil_and_default(branches) do
    fixed =
      Enum.filter(branches, fn branch ->
        match?({:ok, _}, parse_cons_nil_vars(Map.get(branch, :pattern)))
      end)

    default = Enum.find(branches, &wildcard_pattern?(Map.get(&1, :pattern)))

    {fixed, default}
  end

  defp fixed_nil_arms_by_length(fixed_branches) do
  arms =
    Enum.reduce_while(fixed_branches, %{}, fn branch, acc ->
      case parse_cons_nil_vars(Map.get(branch, :pattern)) do
        {:ok, names} ->
          len = length(names)

          if Map.has_key?(acc, len) do
            {:halt, :error}
          else
            {:cont, Map.put(acc, len, {names, Map.get(branch, :expr)})}
          end

        :error ->
          {:halt, :error}
      end
    end)

  case arms do
    :error -> :error
    map when map_size(map) > 0 -> {:ok, map}
    _ -> :error
  end
  end

  defp parse_cons_nil_vars(pattern), do: parse_cons_nil_chain(pattern, true)

  defp parse_cons_nil_chain(pattern, top_level?) do
    case unwrap_cons(pattern) do
      {:cons, head, tail} ->
        with {:ok, head_name} <- pattern_var_name(head),
             {:ok, rest} <- parse_cons_nil_chain(tail, false) do
          {:ok, [head_name | rest]}
        end

      :empty ->
        if top_level?, do: :error, else: {:ok, []}

      :not_cons ->
        :error
    end
  end

  defp unwrap_cons(%{resolved_name: "List.::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}),
    do: {:cons, head, tail}

  defp unwrap_cons(%{
         kind: :constructor,
         name: name,
         arg_pattern: %{kind: :tuple, elements: [head, tail]}
       }) do
    if short_name(name) == "::", do: {:cons, head, tail}, else: :not_cons
  end

  defp unwrap_cons(%{resolved_name: "[]"}), do: :empty

  defp unwrap_cons(%{kind: :constructor, name: name}) do
    if short_name(name) == "[]", do: :empty, else: :not_cons
  end

  defp unwrap_cons(_), do: :not_cons

  defp pattern_var_name(%{kind: :var, name: name}) when is_binary(name), do: {:ok, name}
  defp pattern_var_name(_), do: :error

  defp compile_fixed_nil_peel_chain(arms_by_len, max_len, subject, subj_reg, ctx, b, block_id, default_id) do
  peel_to_depth(arms_by_len, max_len, subject, subj_reg, ctx, b, block_id, default_id, 1, subj_reg, [])
  end

  defp peel_to_depth(_arms_by_len, _max_len, _subject, _subj_reg, _ctx, b, _block_id, _default_id, depth, _tail_reg, _bound)
       when depth > 64 do
  {:ok, [], b}
  end

  defp peel_to_depth(arms_by_len, max_len, subject, subj_reg, ctx, b, block_id, default_id, depth, tail_reg, bound) do
  b_arm = Builder.begin_cfg_arm_block(b, block_id)
  peel = if ListIntType.list_int_subject?(ctx, subject), do: :int_list, else: :maybe_list
  {[head_arg, tail_arg], b_dup} = Builder.dup_regs_for_consume(b_arm, [tail_reg, tail_reg])

  with {:ok, head_reg, next_tail, b1} <- peel_cons_regs(peel, head_arg, tail_arg, ctx, b_dup),
       {:ok, empty_tail, b2} <- emit_test_list_empty(next_tail, b1),
       bound_at_depth = bound ++ [{depth, head_reg}],
       match_id = block_id + 1,
       continue_id = block_id + 2,
       b_branch = Builder.finish_block(b2, {:br_if, match_id, continue_id, empty_tail}),
       {:ok, match_results, b_match} <-
         compile_fixed_nil_match_arm(
           arms_by_len,
           depth,
           bound_at_depth,
           ctx,
           b_branch,
           match_id,
           default_id,
           empty_tail
         ),
       {:ok, cont_results, b_cont} <-
         compile_fixed_nil_continue_peel(
           arms_by_len,
           max_len,
           subject,
           subj_reg,
           ctx,
           b_branch,
           continue_id,
           default_id,
           depth,
           next_tail,
           bound_at_depth
         ) do
    {:ok, match_results ++ cont_results, max(b_cont, b_match)}
  else
    _ -> :unsupported
  end
  end

  defp compile_fixed_nil_match_arm(arms_by_len, depth, bound, ctx, b, match_id, default_id, empty_tail) do
  b_match = Builder.begin_cfg_arm_block(b, match_id)

  if Map.has_key?(arms_by_len, depth) do
    {names, expr} = Map.fetch!(arms_by_len, depth)

    with {:ok, reg, exit, b_arm} <- compile_fixed_nil_bound_arm(expr, names, bound, ctx, b_match, match_id) do
      {:ok, [{depth, reg, exit, empty_tail}], b_arm}
    end
  else
    b_done = Builder.finish_block(b_match, {:br, default_id})
    {:ok, [], b_done}
  end
  end

  defp compile_fixed_nil_continue_peel(arms_by_len, max_len, subject, subj_reg, ctx, b, continue_id, default_id, depth, next_tail, bound) do
  b_cont = Builder.begin_cfg_arm_block(b, continue_id)

  if depth >= max_len do
    b_done = Builder.finish_block(b_cont, {:br, default_id})
    {:ok, [], b_done}
  else
    peel_to_depth(arms_by_len, max_len, subject, subj_reg, ctx, b_cont, continue_id, default_id, depth + 1, next_tail, bound)
  end
  end

  defp compile_fixed_nil_bound_arm(expr, names, bound, ctx, b, block_id) do
  b_arm = if b.current_block.id == block_id, do: b, else: Builder.begin_cfg_arm_block(b, block_id)
  arm_ctx = Context.for_branch_arm(ctx)

  {arm_ctx, b_local} =
    Enum.reduce(Enum.zip(names, bound), {arm_ctx, b_arm}, fn {name, {_depth, reg}}, {c_acc, b_acc} ->
      {Context.put_local(c_acc, name, reg), Builder.bind_local(b_acc, name, reg)}
    end)

  case Expr.compile(expr, arm_ctx, b_local) do
    {:ok, reg, b1} ->
      exit = b1.current_block.id
      {:ok, reg, exit, Builder.finish_block(b1, :none)}

    :unsupported ->
      :unsupported
  end
  end

  defp emit_fixed_nil_merge(empty_cond, arm_results, default_reg, b) do
  sorted = Enum.sort_by(arm_results, fn {len, _, _, _} -> len end, :desc)

  {inner_reg, b_inner} =
    Enum.reduce(sorted, {default_reg, b}, fn {_len, reg, _exit, cond}, {acc_reg, b_acc} ->
      {:ok, merged, b1} = emit_merge(cond, reg, acc_reg, b_acc)
      {merged, b1}
    end)

  emit_merge(empty_cond, default_reg, inner_reg, b_inner)
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

  defp compile_triple_nonempty_arms(
         single_expr,
         double_expr,
         a_name,
         b_name,
         rest_name,
         only_name,
         subject,
         subj_reg,
         ctx,
         b,
         peel_id,
         single_id,
         double_id
       ) do
    b_peel = Builder.begin_cfg_arm_block(b, peel_id)
    peel = if ListIntType.list_int_subject?(ctx, subject), do: :int_list, else: :maybe_list
    {[head_arg, tail_arg], b_dup} = Builder.dup_regs_for_consume(b_peel, [subj_reg, subj_reg])

    with {:ok, a_reg, t1_reg, b_bound} <- peel_cons_regs(peel, head_arg, tail_arg, ctx, b_dup),
         {:ok, t1_empty_cond, b_t1} <- emit_test_list_empty(t1_reg, b_bound),
         arm_ctx =
           ctx
           |> Context.put_local(a_name, a_reg)
           |> Context.put_local(only_name, a_reg),
         b_locals =
           b_t1
           |> Builder.bind_local(a_name, a_reg)
           |> Builder.bind_local(only_name, a_reg),
         b_branch = Builder.finish_block(b_locals, {:br_if, single_id, double_id, t1_empty_cond}),
         {:ok, single_reg, single_exit, _b_single} <-
           compile_arm(single_expr, arm_ctx, b_branch, single_id),
         {:ok, double_reg, double_exit, b_double} <-
           compile_double_cons_tail_arm(
             double_expr,
             a_name,
             b_name,
             rest_name,
             a_reg,
             t1_reg,
             subject,
             arm_ctx,
             b_branch,
             double_id
           ) do
      {:ok, t1_empty_cond, single_reg, single_exit, double_reg, double_exit, b_double}
    else
      _ -> :unsupported
    end
  end

  defp compile_double_cons_tail_arm(
         expr,
         a_name,
         b_name,
         rest_name,
         a_reg,
         t1_reg,
         subject,
         ctx,
         b,
         block_id
       ) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    peel = if ListIntType.list_int_subject?(ctx, subject), do: :int_list, else: :maybe_list
    {[t1_a, t1_b], b0} = Builder.dup_regs_for_consume(b_arm, [t1_reg, t1_reg])

    with {:ok, b_reg, rest_reg, b_bound} <- peel_cons_regs(peel, t1_a, t1_b, ctx, b0),
         ctx1 <-
           ctx
           |> Context.put_local(a_name, a_reg)
           |> Context.put_local(b_name, b_reg)
           |> Context.put_local(rest_name, rest_reg),
         b_locals =
           b_bound
           |> Builder.bind_local(a_name, a_reg)
           |> Builder.bind_local(b_name, b_reg)
           |> Builder.bind_local(rest_name, rest_reg),
         {:ok, reg, b_expr} <- Expr.compile(expr, Context.for_branch_arm(ctx1), b_locals) do
      exit_id = b_expr.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b_expr, :none)}
    else
      _ -> :unsupported
    end
  end

  defp emit_triple_merge(empty_cond, t1_empty_cond, empty_reg, single_reg, double_reg, b) do
    with {:ok, inner, b1} <- emit_merge(t1_empty_cond, single_reg, double_reg, b),
         {:ok, outer, b2} <- emit_merge(empty_cond, empty_reg, inner, b1) do
      {:ok, outer, b2}
    end
  end

  defp emit_nested_merge(empty_subj_reg, wild_reg, empty_tail_reg, wild2_reg, cons_reg, b) do
    with {:ok, inner, b1} <- emit_merge(empty_tail_reg, wild2_reg, cons_reg, b),
         {:ok, outer, b2} <- emit_merge(empty_subj_reg, wild_reg, inner, b1) do
      {:ok, outer, b2}
    end
  end
end
