defmodule Elmc.Backend.Plan.Lower.Case.GuardedSwitch do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case.ArmMerge
  alias Elmc.Backend.Plan.Lower.{Expr, PatternBind, PatternMatch}
  alias Elmc.Backend.Plan.Types

  @spec branches?(Types.case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    length(branches) >= 1 and
      Enum.all?(branches, fn branch ->
        guardable_pattern?(Map.get(branch, :pattern))
      end)
  end

  def branches?(_), do: false

  @spec compile(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile(subject, branches, ctx, b) do
    branches = normalize_branch_patterns(branches)

    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         b_sealed = seal_entry_block(b1) do
      compile_cfg(subj_reg, branches, ctx, b_sealed)
    else
      _ -> :unsupported
    end
  end

  @spec seal_entry_block(Types.ir_expr()) :: Types.ir_expr()

  defp seal_entry_block(b) do
    if b.current_block.instrs != [] or b.current_block.terminator != :none do
      Builder.finish_block(b, :none)
    else
      b
    end
  end

  @spec compile_cfg(Types.ir_expr(), list(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_cfg(subj_reg, branches, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)
    {tested, default_br} = split_branches(branches)
    {merge_reg, b0} = Builder.fresh_reg(b)
    entry_id = b0.current_block.id

    with {:ok, arm_exits, default_block_id, b_chain} <-
           compile_test_chain(tested, subj_reg, ctx, b0, merge_reg, entry_id),
         {:ok, default_exit, b_default} <-
           compile_default_arm(
             default_br,
             branches,
             subj_reg,
             ctx,
             b_chain,
             default_block_id,
             merge_reg
           ),
         merge_id = skip_reserved(b_default.next_block, saved_pending),
         b_reserved = %{b_default | next_block: max(b_default.next_block, merge_id + 1)},
         b_br = patch_arm_exits(b_reserved, arm_exits ++ List.wrap(default_exit), merge_id),
         b_merge_start = Builder.begin_block(b_br, merge_id),
         {:ok, merge, b_merge} <- ArmMerge.finish_merge(b_merge_start, merge_reg, merge_id) do
      {:ok, merge, %{b_merge | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  # Single-constructor patterns (`(Quantity r) = …`, `(Entity node)`,
  # `(Frame3d rec)`, argument peels, …) are untyped unwraps: bind the payload
  # without a tag gate. Constructor tags are *global* in elmc (many types share
  # tag 1), and peels may already have produced a bare record/float payload —
  # requiring `union_tag_matches` then falls through to `int_literal 0` and
  # poisons Scene3d entity lists.
  #
  # Exhaustive *multi*-constructor cases must still test *every* arm, including
  # the last. Treating the last constructor as an untagged default peels
  # garbage as that constructor (e.g. Scene3d `Transformed`) and can recurse
  # forever.
  @spec split_branches(term() | list()) :: Types.ir_expr()

  defp split_branches([only]) do
    {[], only}
  end

  defp split_branches(branches) do
    {catch_alls, specific} =
      Enum.split_with(branches, fn branch ->
        catch_all_pattern?(Map.get(branch, :pattern))
      end)

    cond do
      catch_alls == [] ->
        {branches, :impossible}

      specific == [] ->
        {[], List.last(catch_alls)}

      true ->
        {specific, List.last(catch_alls)}
    end
  end

  @spec catch_all_pattern?(map() | term()) :: boolean()

  defp catch_all_pattern?(%{kind: kind}) when kind in [:wildcard, :var], do: true
  defp catch_all_pattern?(_), do: false

  @spec compile_test_chain(term(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_test_chain([], _subj, _ctx, b, _merge, default_id),
    do: {:ok, [], default_id, b}

  defp compile_test_chain([branch | rest], subj_reg, ctx, b, merge_reg, test_block_id) do
    b_test =
      if b.current_block.id == test_block_id do
        b
      else
        Builder.begin_block(b, test_block_id)
      end

    with {:ok, cond_reg, b1} <-
           PatternMatch.match_condition(Map.get(branch, :pattern), subj_reg, b_test),
         arm_id = b1.next_block,
         else_id = arm_id + 1,
         b1 = %{b1 | next_block: max(b1.next_block, else_id + 1)},
         b_sealed = Builder.finish_block(b1, {:br_if, arm_id, else_id, cond_reg}),
         {:ok, arm_exit, b_arm} <- compile_arm(branch, subj_reg, ctx, b_sealed, arm_id, merge_reg),
         {:ok, more_exits, next_default, b_else} <-
           compile_test_chain(rest, subj_reg, ctx, b_arm, merge_reg, else_id) do
      {:ok, [arm_exit | more_exits], next_default, b_else}
    else
      _ -> :unsupported
    end
  end

  # Impossible under well-typed data. Prefer a passive arm's body (no subject
  # bindings — e.g. EmptyNode skip) so callers can continue; otherwise a null
  # handle (Maybe Nothing, empty, etc.).
  @spec compile_default_arm(Types.ir_expr(), list() | Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_default_arm(:impossible, branches, subj_reg, ctx, b, arm_id, merge_reg) do
    fallback_expr =
      Enum.find_value(branches, fn branch ->
        if passive_pattern?(Map.get(branch, :pattern)), do: Map.get(branch, :expr)
      end)

    branch =
      case fallback_expr do
        nil ->
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}

        expr ->
          %{pattern: %{kind: :wildcard}, expr: expr}
      end

    compile_arm(branch, subj_reg, ctx, b, arm_id, merge_reg)
  end

  defp compile_default_arm(branch, _branches, subj_reg, ctx, b, arm_id, merge_reg)
       when is_map(branch) do
    compile_arm(branch, subj_reg, ctx, b, arm_id, merge_reg)
  end

  @spec passive_pattern?(map() | term()) :: boolean()

  defp passive_pattern?(%{kind: kind}) when kind in [:wildcard, :var], do: true

  # A constructor arm is passive only when it binds nothing from the subject.
  # `UseTexture materialColorData` has `bind` set and `arg_pattern: nil` (unary
  # payload) — that must NOT be treated as passive, or the impossible-default
  # fallback recompiles the arm under a wildcard and leaves the payload unbound
  # for nested lambdas (Scene3d textured/bumpy mesh helpers).
  defp passive_pattern?(%{kind: :constructor, bind: bind}) when is_binary(bind), do: false

  defp passive_pattern?(%{kind: :constructor} = pattern) do
    passive_payload?(Map.get(pattern, :arg_pattern))
  end

  defp passive_pattern?(_), do: false

  @spec passive_payload?(Types.ir_expr() | map() | term()) :: boolean()

  defp passive_payload?(nil), do: true
  defp passive_payload?(%{kind: :wildcard}), do: true

  defp passive_payload?(%{kind: :tuple, elements: elements}) when is_list(elements) do
    Enum.all?(elements, &passive_payload?/1)
  end

  defp passive_payload?(%{kind: :var}), do: false
  defp passive_payload?(%{kind: :constructor, bind: bind}) when is_binary(bind), do: false

  defp passive_payload?(%{kind: :constructor} = pattern) do
    passive_payload?(Map.get(pattern, :arg_pattern))
  end

  defp passive_payload?(_), do: false

  @spec compile_arm(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_arm(branch, subj_reg, ctx, b, arm_id, merge_reg) do
    b_arm =
      if b.current_block.id == arm_id do
        b
      else
        Builder.begin_block(b, arm_id)
      end

    pattern = Map.get(branch, :pattern, %{})
    expr = Map.get(branch, :expr)

    with {:ok, arm_ctx, b1} <- bind_pattern(Context.for_branch_arm(ctx), b_arm, pattern, subj_reg),
         {:ok, reg, b2} <- Expr.compile(expr, arm_ctx, b1),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b2, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b_done = Builder.finish_block(b_pub, :none) do
      {:ok, exit_id, b_done}
    else
      _ -> :unsupported
    end
  end

  @spec bind_pattern(Types.ir_expr(), Types.ir_expr(), Types.pattern(), Types.ir_expr()) :: Types.ir_expr()

  defp bind_pattern(ctx, b, pattern, subj_reg) do
    case PatternBind.bind(pattern, ctx, b, subj_reg) do
      {:ok, ctx1, b1} -> {:ok, ctx1, b1}
      :unsupported -> :unsupported
    end
  end

  @spec patch_arm_exits(Types.ir_expr(), list(), Types.ir_expr()) :: Types.ir_expr()

  defp patch_arm_exits(b, exit_ids, merge_id) when is_list(exit_ids) do
    exit_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(b, fn exit_id, b_acc ->
      Builder.patch_terminator(b_acc, exit_id, {:br, merge_id})
    end)
  end

  @spec guardable_pattern?(map() | term()) :: boolean()

  defp guardable_pattern?(%{kind: kind})
       when kind in [:tuple, :constructor, :qualified_constructor, :wildcard, :var, :int, :string, :char],
       do: true

  defp guardable_pattern?(_), do: false

  @spec normalize_branch_patterns(list()) :: list()

  defp normalize_branch_patterns(branches) when is_list(branches) do
    Enum.map(branches, fn branch ->
      case Map.get(branch, :pattern) do
        %{kind: :qualified_constructor} = pattern ->
          %{branch | pattern: Map.put(pattern, :kind, :constructor)}

        pattern ->
          %{branch | pattern: pattern}
      end
    end)
  end

  @spec skip_reserved(Types.ir_expr(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id
end
