defmodule Elmc.Backend.Plan.Lower.Case.TagSwitch do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case.ArmMerge
  alias Elmc.Backend.Plan.Lower.{Expr, PatternBind}
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.SizeProfile

  # Ok/Err must tag-switch (linear multi-arm lowering runs every arm). Maybe uses
  # compile_maybe_nothing_case; list ctors stay excluded here.
  @excluded_names MapSet.new(["Just", "Nothing", "::", "[]"])

  @spec branches?(Types.case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    tagged? =
      Enum.any?(branches, fn branch ->
        match?(%{pattern: %{kind: :constructor, tag: tag}} when is_integer(tag), branch)
      end)

    tagged? and
      Enum.all?(branches, fn branch ->
        case Map.get(branch, :pattern) do
          %{kind: :wildcard} -> true
          %{kind: :constructor} = pattern -> switchable_pattern?(pattern)
          _ -> false
        end
      end)
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

  defp maybe_peel_enum_tag(subject, subj_reg, b) do
    opts = Process.get(:elmc_codegen_opts, %{})

    if SizeProfile.enum_tag_peel?(opts) and enum_call_subject?(subject) do
      Builder.emit_boxed_tag_peel(b, subj_reg)
    else
      {subj_reg, b}
    end
  end

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

  defp enum_return_type?(target) when is_binary(target) do
    decl = lookup_call_decl(target)
    type = Map.get(decl || %{}, :type)

    is_binary(type) and enum_type?(type)
  end

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

  defp lookup_call_decl(target) do
    decls = Process.get(:elmc_program_decls, %{})

    case String.split(target, ".", parts: 2) do
      [mod, name] -> Map.get(decls, {mod, name})
      [name] -> Enum.find_value(decls, fn {{_mod, n}, decl} -> if n == name, do: decl end)
    end
  end

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

  defp split_branches(branches) do
    tagged = Enum.filter(branches, fn br -> match?(%{pattern: %{kind: :constructor}}, br) end)
    default = Enum.find(branches, fn br -> match?(%{pattern: %{kind: :wildcard}}, br) end)
    {tagged, default}
  end

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

  defp compile_tagged_arms([], _subj, _ctx, b, _merge_reg, acc), do: {:ok, Enum.reverse(acc), [], b}

  defp compile_tagged_arms([branch | rest], subj_reg, ctx, b, merge_reg, acc) do
    arm_id = b.next_block
    b_arm = Builder.begin_cfg_arm_block(b, arm_id)

    with {:ok, reg, tag, b1} <- compile_one_arm(branch, subj_reg, ctx, b_arm),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b1, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b2 = Builder.finish_block(b_pub, :none),
         {:ok, more, exits, b3} <-
           compile_tagged_arms(rest, subj_reg, ctx, b2, merge_reg, [{tag, reg, arm_id, ctor_name(branch)} | acc]) do
      {:ok, more, [exit_id | exits], b3}
    else
      _ -> :unsupported
    end
  end

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
        tag = pattern_tag(ctor_pattern)

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


  defp patch_arm_exits(b, exit_ids, merge_id) when is_list(exit_ids) do
    Enum.reduce(exit_ids, b, fn exit_id, b_acc ->
      Builder.patch_terminator(b_acc, exit_id, {:br, merge_id})
    end)
  end

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id

  defp branch_ctx_for_pattern(ctx, %{bind: bind} = pattern, subj_reg, b) when is_binary(bind) do
    case Map.get(pattern, :arg_pattern) do
      arg_pattern when is_map(arg_pattern) ->
        if payload_bind?(pattern) do
          case PatternBind.bind(
                 %{kind: :constructor, bind: bind, arg_pattern: nil, name: Map.get(pattern, :name)},
                 ctx,
                 b,
                 subj_reg
               ) do
            {:ok, ctx1, b1} -> {:ok, ctx1, b1}
            _ -> :unsupported
          end
        else
          PatternBind.bind(
            %{
              kind: :constructor,
              bind: bind,
              arg_pattern: arg_pattern,
              name: Map.get(pattern, :name),
              resolved_name: Map.get(pattern, :resolved_name),
              tag: Map.get(pattern, :tag)
            },
            ctx,
            b,
            subj_reg
          )
        end

      _ ->
        if payload_bind?(pattern) do
          case PatternBind.bind(
                 %{kind: :constructor, bind: bind, arg_pattern: nil, name: Map.get(pattern, :name)},
                 ctx,
                 b,
                 subj_reg
               ) do
            {:ok, ctx1, b1} -> {:ok, ctx1, b1}
            _ -> :unsupported
          end
        else
          case PatternBind.bind(%{kind: :var, name: bind}, ctx, b, subj_reg) do
            {:ok, ctx1, b1} -> {:ok, ctx1, b1}
            :unsupported -> {:ok, Context.put_local(ctx, bind, subj_reg), Builder.bind_local(b, bind, subj_reg)}
          end
        end
    end
  end

  defp branch_ctx_for_pattern(ctx, %{arg_pattern: %{kind: :var, name: name}} = pattern, subj_reg, b)
       when is_binary(name) do
    branch_ctx_for_pattern(ctx, Map.put(pattern, :bind, name), subj_reg, b)
  end

  defp branch_ctx_for_pattern(ctx, %{arg_pattern: arg_pattern} = pattern, subj_reg, b)
       when is_map(arg_pattern) do
    PatternBind.bind(%{kind: :constructor, arg_pattern: arg_pattern, name: Map.get(pattern, :name)}, ctx, b, subj_reg)
  end

  defp branch_ctx_for_pattern(ctx, _pattern, _subj_reg, b), do: {:ok, ctx, b}

  defp payload_bind?(%{arg_pattern: nil}), do: true
  defp payload_bind?(%{arg_pattern: %{kind: :var}}), do: true
  defp payload_bind?(_), do: false

  defp switchable_pattern?(%{kind: :constructor, name: name, tag: tag}) when is_integer(tag) do
    is_nil(name) or not MapSet.member?(@excluded_names, short_name(name))
  end

  defp switchable_pattern?(%{kind: :constructor, tag: tag}) when is_integer(tag), do: true
  defp switchable_pattern?(_), do: false

  defp pattern_tag(%{tag: tag}) when is_integer(tag), do: tag

  defp pattern_tag(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)

    if is_binary(name) do
      tags = Process.get(:elmc_constructor_tags, %{})

      Map.get(tags, name) ||
        Map.get(tags, short_name(name)) ||
        lookup_qualified_tag(name, tags)
    end
  end

  defp lookup_qualified_tag(name, tags) do
    Enum.find_value(tags, fn {key, tag} ->
      if String.ends_with?(key, "." <> short_name(name)), do: tag
    end)
  end

  defp short_name(name), do: name |> String.split(".") |> List.last()

  defp ctor_name(%{pattern: pattern}) when is_map(pattern), do: union_ctor_name_from_pattern(pattern)
  defp ctor_name(_), do: nil

  defp union_ctor_name_from_pattern(%{resolved_name: name}) when is_binary(name), do: name

  defp union_ctor_name_from_pattern(%{name: name}) when is_binary(name), do: name

  defp union_ctor_name_from_pattern(_), do: nil
end
