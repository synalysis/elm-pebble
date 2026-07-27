defmodule Elmc.Backend.Plan.Lower.Case.TagSwitch do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case.{ArmMerge, GuardedSwitch}
  alias Elmc.Backend.Plan.Lower.{Expr, PatternBind, UnionCtor}
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.SizeProfile
  alias Elmc.Backend.CCodegen.IRQueries

  # Ok/Err must tag-switch (linear multi-arm lowering runs every arm). Maybe uses
  # compile_maybe_nothing_case; list ctors stay excluded here.
  # True/False must not tag-switch: native-bool ABI is 0/1 while union tags are
  # ELMC_UNION_BASICS_TRUE/FALSE (1/2). Bool cases go through test_bool instead.
  @excluded_names MapSet.new(["Just", "Nothing", "::", "[]", "True", "False"])

  @spec branches?(Types.case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    # Single-constructor peels (`(Quantity r)`, `(Entity node)`, `Frame3d` as
    # bind, …) must not tag-switch: constructor tags are global, and bare
    # payloads are common after prior peels. Those go to GuardedSwitch as
    # untyped unwraps. TagSwitch is for discriminating 2+ constructors.
    ctor_count =
      Enum.count(branches, fn branch ->
        match?(%{pattern: %{kind: :constructor}}, branch)
      end)

    tagged? =
      Enum.any?(branches, fn branch ->
        match?(%{pattern: %{kind: :constructor, tag: tag}} when is_integer(tag), branch)
      end)

    result =
      ctor_count >= 2 and tagged? and
        Enum.all?(branches, fn branch ->
          case Map.get(branch, :pattern) do
            %{kind: :wildcard} -> true
            %{kind: :constructor} = pattern -> switchable_pattern?(pattern)
            _ -> false
          end
        end)

    result
  end

  def branches?(_), do: false

  @spec compile(Types.ir_expr(), Types.case_branches(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile(subject, branches, ctx, b) do
    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         {switch_reg, b_peel} <- maybe_peel_enum_tag(subject, subj_reg, b1) do
      compile_cfg(switch_reg, branches, ctx, b_peel)
    else
      _ -> :unsupported
    end
  end

  @spec maybe_peel_enum_tag(Types.expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr() | nil

  defp maybe_peel_enum_tag(subject, subj_reg, b) do
    opts = Process.get(:elmc_codegen_opts, %{})

    if SizeProfile.enum_tag_peel?(opts) and enum_call_subject?(subject) do
      Builder.emit_boxed_tag_peel(b, subj_reg)
    else
      {subj_reg, b}
    end
  end

  @spec enum_call_subject?(map() | term()) :: boolean()

  defp enum_call_subject?(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    enum_return_type?(target)
  end

  defp enum_call_subject?(%{op: :call, target: {mod, name}, args: args})
       when is_binary(mod) and is_binary(name) and is_list(args) do
    enum_return_type?("#{mod}.#{name}")
  end

  defp enum_call_subject?(%{op: :call, name: name, args: args})
       when is_binary(name) and is_list(args) do
    enum_return_type?(name)
  end

  defp enum_call_subject?(_), do: false

  @spec enum_return_type?(String.t()) :: boolean()

  defp enum_return_type?(target) when is_binary(target) do
    decl = lookup_call_decl(target)
    type = Map.get(decl || %{}, :type)

    is_binary(type) and enum_type?(type)
  end

  @spec enum_type?(String.t()) :: boolean()

  defp enum_type?(type) when is_binary(type) do
    return =
      type
      |> String.replace(" ", "")
      |> String.split("->")
      |> List.last()

    enums = Process.get(:elmc_enum_types, MapSet.new())

    MapSet.member?(enums, return) or
      MapSet.member?(enums, short_name(return))
  end

  @spec lookup_call_decl(String.t()) :: Types.ir_expr()

  defp lookup_call_decl(target) do
    decls = Process.get(:elmc_program_decls, %{})

    case String.split(target, ".", parts: 2) do
      [mod, name] -> Map.get(decls, {mod, name})
      [name] -> Enum.find_value(decls, fn {{_mod, n}, decl} -> if n == name, do: decl end)
    end
  end

  @spec compile_cfg(Types.ir_expr(), list(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_cfg(subj_reg, branches, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)
    {tagged, default_br} = split_branches(branches)
    entry_id = b.current_block.id
    b_sealed = Builder.finish_block(b, :none)
    {merge_reg, b_sealed} = Builder.fresh_reg(b_sealed)

    with {:ok, tagged_results, _default_reg, default_arm_id, arm_exits, b_arms} <-
           compile_arm_blocks(tagged, default_br, subj_reg, ctx, b_sealed, merge_reg),
         merge_id = skip_reserved(b_arms.next_block, saved_pending),
         b_br = patch_arm_exits(b_arms, arm_exits, merge_id),
         switch_arms =
           Enum.map(tagged_results, fn {tag, _reg, arm_id, ctor} -> {tag, arm_id, ctor} end),
         default_block_id = default_arm_id || merge_id,
         b_entry =
           Builder.patch_terminator(
             b_br,
             entry_id,
             {:switch_tag, subj_reg, switch_arms, default_block_id}
           ),
         b_merge_start = Builder.begin_block(b_entry, merge_id),
         {:ok, merge, b_merge} <- ArmMerge.finish_merge(b_merge_start, merge_reg, merge_id) do
      {:ok, merge, %{b_merge | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  @spec split_branches(list()) :: Types.ir_expr()

  defp split_branches(branches) do
    tagged = Enum.filter(branches, fn br -> match?(%{pattern: %{kind: :constructor}}, br) end)
    default = Enum.find(branches, fn br -> match?(%{pattern: %{kind: :wildcard}}, br) end)
    {tagged, default}
  end

  @spec compile_arm_blocks(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_arm_blocks(tagged, default_br, subj_reg, ctx, b, merge_reg) do
    with {:ok, tagged_results, arm_exits, b1} <-
           compile_tagged_arms(tagged, subj_reg, ctx, b, merge_reg, []),
         {:ok, default_arm_id, default_exit, b2} <-
           compile_default_arm(default_br, subj_reg, ctx, b1, merge_reg) do
      {:ok, tagged_results, nil, default_arm_id, arm_exits ++ List.wrap(default_exit), b2}
    else
      _ -> :unsupported
    end
  end

  @spec compile_tagged_arms(list(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), term()) :: Types.ir_expr()

  defp compile_tagged_arms(tagged, subj_reg, ctx, b, merge_reg, acc) when is_list(tagged) do
    tagged
    |> group_branches_by_tag(ctx)
    |> Enum.sort_by(fn {tag, _} -> tag end)
    |> compile_tag_groups(subj_reg, ctx, b, merge_reg, acc)
  end

  @spec group_branches_by_tag(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp group_branches_by_tag(tagged, ctx) do
    tagged
    |> Enum.group_by(fn branch -> pattern_tag(branch.pattern, ctx) end)
    |> Enum.map(fn {tag, branches} -> {tag, branches} end)
  end

  @spec compile_tag_groups(term(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), term()) :: Types.ir_expr()

  defp compile_tag_groups([], _subj, _ctx, b, _merge_reg, acc), do: {:ok, Enum.reverse(acc), [], b}

  defp compile_tag_groups([{tag, [branch]} | rest], subj_reg, ctx, b, merge_reg, acc) do
    arm_id = b.next_block
    b_arm = Builder.begin_cfg_arm_block(b, arm_id)

    with {:ok, reg, ^tag, b1} <- compile_one_arm(branch, subj_reg, ctx, b_arm),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b1, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b2 = Builder.finish_block(b_pub, :none),
         {:ok, more, exits, b3} <-
           compile_tag_groups(rest, subj_reg, ctx, b2, merge_reg, [{tag, reg, arm_id, ctor_name(branch)} | acc]) do
      {:ok, more, [exit_id | exits], b3}
    else
      _ -> :unsupported
    end
  end

  defp compile_tag_groups([{tag, branches} | rest], subj_reg, ctx, b, merge_reg, acc)
       when length(branches) > 1 do
    arm_id = b.next_block
    b_arm = Builder.begin_cfg_arm_block(b, arm_id)

    with {:ok, reg, ^tag, b1} <- compile_nested_duplicate_tag_arm(branches, subj_reg, ctx, b_arm),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b1, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b2 = Builder.finish_block(b_pub, :none),
         {:ok, more, exits, b3} <-
           compile_tag_groups(rest, subj_reg, ctx, b2, merge_reg, [
             {tag, reg, arm_id, ctor_name(hd(branches))} | acc
           ]) do
      {:ok, more, [exit_id | exits], b3}
    else
      _ -> :unsupported
    end
  end

  # Same outer tag, different nested payloads (e.g. Scene3d `UnlitMaterial _ (Constant …)`
  # vs `UnlitMaterial UseMeshUvs (Texture { data })`). Discriminant-only inner switches
  # drop bindings in non-discriminant columns; GuardedSwitch matches/binds full patterns.
  @spec compile_nested_duplicate_tag_arm(list(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_nested_duplicate_tag_arm(branches, subj_reg, ctx, b) do
    branch_ctx = Context.for_branch_arm(ctx)
    representative = hd(branches)
    tag = pattern_tag(representative.pattern, ctx)
    subject_name = "__dup_tag_subject__"
    subject = %{op: :var, name: subject_name}
    ctx1 = Context.put_local(branch_ctx, subject_name, subj_reg)
    b1 = Builder.bind_local(b, subject_name, subj_reg)

    case GuardedSwitch.compile(subject, branches, ctx1, b1) do
      {:ok, reg, b2} when is_integer(tag) -> {:ok, reg, tag, b2}
      _ -> :unsupported
    end
  end

  @spec compile_default_arm(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_default_arm(nil, _subj, _ctx, b, _merge_reg), do: {:ok, nil, nil, b}

  defp compile_default_arm(branch, subj_reg, ctx, b, merge_reg) do
    arm_id = b.next_block
    b_arm = Builder.begin_cfg_arm_block(b, arm_id)

    with {:ok, reg, _tag, b1} <- compile_one_arm(branch, subj_reg, ctx, b_arm),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b1, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b2 = Builder.finish_block(b_pub, :none) do
      {:ok, arm_id, exit_id, b2}
    else
      _ -> :unsupported
    end
  end

  @spec compile_one_arm(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_one_arm(branch, subj_reg, ctx, b) do
    pattern = Map.get(branch, :pattern, %{})
    expr = Map.get(branch, :expr)
    branch_ctx = Context.for_branch_arm(ctx)

    case pattern do
      %{kind: :wildcard} ->
        case Expr.compile(expr, branch_ctx, b) do
          {:ok, reg, b1} -> {:ok, reg, nil, b1}
          :unsupported ->
            record_case_arm_unsupported(ctx, pattern, expr, :wildcard_arm)
            :unsupported
        end

      %{kind: :constructor} = ctor_pattern ->
        tag = pattern_tag(ctor_pattern, ctx)

        if is_integer(tag) do
          with {:ok, arm_ctx, b1} <- branch_ctx_for_pattern(branch_ctx, ctor_pattern, subj_reg, b),
               {:ok, reg, b2} <- Expr.compile(expr, arm_ctx, b1) do
            {:ok, reg, tag, b2}
          else
            _ ->
              record_case_arm_unsupported(ctx, ctor_pattern, expr, :ctor_arm)
              :unsupported
          end
        else
          :unsupported
        end

      _ ->
        :unsupported
    end
  end

  @spec record_case_arm_unsupported(map(), Types.pattern(), Types.expr(), atom()) :: Types.ir_expr()

  defp record_case_arm_unsupported(ctx, pattern, expr, kind) when is_map(ctx) do
    key = {Map.get(ctx, :module), Map.get(ctx, :function_name)}

    ctor =
      case pattern do
        %{kind: :constructor, resolved_name: name} when is_binary(name) -> name
        %{kind: :constructor, name: name} when is_binary(name) -> name
        _ -> nil
      end

    inner = deepest_unsupported_reason(expr, ctx)

    reason =
      case inner do
        %{op: inner_op} = inner_reason ->
          %{
            op: :case_arm,
            target: ctor,
            kind: kind,
            inner_op: inner_op,
            inner_target: Map.get(inner_reason, :target) || Map.get(inner_reason, :name)
          }

        _ ->
          %{
            op: :case_arm,
            target: ctor,
            kind: kind,
            inner_op: (is_map(expr) && Map.get(expr, :op)) || nil,
            inner_target: (is_map(expr) && (Map.get(expr, :target) || Map.get(expr, :name))) || nil
          }
      end

    cache = Process.get(:elmc_plan_unsupported_reasons, %{})
    Process.put(:elmc_plan_unsupported_reasons, Map.put_new(cache, key, reason))
  end

  @spec deepest_unsupported_reason(map() | term(), map() | term()) :: Types.ir_expr()

  defp deepest_unsupported_reason(expr, ctx) when is_map(expr) and is_map(ctx) do
    Process.delete(:elmc_plan_unsupported_reasons)

    b =
      Builder.new(Map.get(ctx, :module) || "Main", Map.get(ctx, :function_name) || "probe",
        args: [],
        rc_required: false,
        fallible: true
      )

    case Expr.compile(expr, Context.for_branch_arm(ctx), b) do
      {:ok, _, _} ->
        nil

      :unsupported ->
        Process.get(:elmc_plan_unsupported_reasons, %{})
        |> Enum.find_value(fn {_key, reason} -> reason end)
    end
  end

  defp deepest_unsupported_reason(_, _), do: nil


  @spec patch_arm_exits(Types.ir_expr(), list(), Types.ir_expr()) :: Types.ir_expr()

  defp patch_arm_exits(b, exit_ids, merge_id) when is_list(exit_ids) do
    Enum.reduce(exit_ids, b, fn exit_id, b_acc ->
      Builder.patch_terminator(b_acc, exit_id, {:br, merge_id})
    end)
  end

  @spec skip_reserved(Types.ir_expr(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id

  @spec branch_ctx_for_pattern(Types.ir_expr(), map(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp branch_ctx_for_pattern(ctx, %{kind: :constructor} = pattern, subj_reg, b) do
    PatternBind.bind(pattern, ctx, b, subj_reg)
  end

  @spec switchable_pattern?(map() | term()) :: boolean()

  defp switchable_pattern?(%{kind: :constructor, tag: tag} = pattern) when is_integer(tag) do
    tag_switch_payload?(Map.get(pattern, :arg_pattern)) and
      not excluded_ctor_pattern?(pattern)
  end

  defp switchable_pattern?(_), do: false

  defp excluded_ctor_pattern?(pattern) when is_map(pattern) do
    [Map.get(pattern, :resolved_name), Map.get(pattern, :name)]
    |> Enum.any?(fn
      name when is_binary(name) -> MapSet.member?(@excluded_names, short_name(name))
      _ -> false
    end)
  end

  @spec tag_switch_payload?(Types.ir_expr() | map() | term()) :: boolean()

  defp tag_switch_payload?(nil), do: true
  defp tag_switch_payload?(%{kind: :wildcard}), do: true
  defp tag_switch_payload?(_), do: false

  @spec pattern_tag(map() | term(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp pattern_tag(pattern, ctx) when is_map(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)
    tags = Process.get(:elmc_constructor_tags, %{})

    resolved =
      if is_binary(name) do
        qualified = UnionCtor.qualify(name, ctx)
        IRQueries.lookup_tag(tags, qualified) || IRQueries.lookup_tag(tags, name)
      end

    # Prefer name+module affinity over a baked IR tag. Ambiguous short names
    # (e.g. Group) may have been poisoned to Internal.Compiler.Group (5) in IR
    # while Scene3d.Types.Group is 6.
    cond do
      is_integer(resolved) -> resolved
      match?(%{tag: t} when is_integer(t), pattern) -> pattern.tag
      true -> nil
    end
  end

  defp pattern_tag(_, _), do: nil

  @spec short_name(String.t()) :: Types.ir_expr()

  defp short_name(name), do: name |> String.split(".") |> List.last()

  @spec ctor_name(map() | term()) :: Types.ir_expr()

  defp ctor_name(%{pattern: pattern}) when is_map(pattern), do: union_ctor_name_from_pattern(pattern)
  defp ctor_name(_), do: nil

  @spec union_ctor_name_from_pattern(map() | term()) :: Types.ir_expr()

  defp union_ctor_name_from_pattern(%{resolved_name: name}) when is_binary(name), do: name

  defp union_ctor_name_from_pattern(%{name: name}) when is_binary(name), do: name

  defp union_ctor_name_from_pattern(_), do: nil
end
