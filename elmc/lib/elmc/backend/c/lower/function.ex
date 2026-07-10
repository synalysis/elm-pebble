defmodule Elmc.Backend.C.Lower.Function do
  @moduledoc """
  Lower verified `%FunctionPlan{}` to C function body text (RC ABI).
  """

  alias Elmc.Backend.C.Lower.{Frame, Instr, Lambda, NativeIntFold, NativeReturn, StringConcat, TagRefs}
  alias Elmc.Backend.CCodegen.{FunctionCallAbi, FunctionEmit, Fusion}
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.Optimize
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.SizeProfile

  @min_switch_arms 3

  @spec emit(FunctionPlan.t(), keyword()) :: String.t()
  def emit(%FunctionPlan{} = plan, opts \\ []) do
    fusion_c = Map.get(plan, :fusion_c)

    cond do
      is_binary(fusion_c) and fusion_c != "" ->
        String.trim(fusion_c)

      Keyword.get(opts, :shell, true) ->
        wrap_shell(plan, emit_core(plan, opts))

      true ->
        emit_core(plan, opts)
    end
  end

  @spec emit_core(FunctionPlan.t(), keyword()) :: String.t()
  def emit_core(plan, opts \\ [])

  def emit_core(%FunctionPlan{fusion_c: c}, _opts) when is_binary(c) and c != "", do: String.trim(c)

  def emit_core(%FunctionPlan{} = plan, opts) do
    Process.put(:elmc_plan_rec_values_suffix, 0)
    unless Keyword.get(opts, :closure_mode) do
      Lambda.ensure_emitted!(plan)
    end

    rc? = plan.rc_required
    param_kinds = param_kinds_for_plan(plan)
    decl_map = Process.get(:elmc_program_decls, %{})
    {slots, _slot_count} = Plan.allocate_slots(plan)

    closure_mode = Keyword.get(opts, :closure_mode)

    {native_int_regs, slots} =
      allocate_native_int_param_slots(plan, slots, param_kinds, decl_map, closure_mode)

    {borrow_param_regs, slots} =
      allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, closure_mode)

    closure_borrow_regs = build_closure_borrow_regs(plan, closure_mode)

    const_int_regs = build_const_int_regs(plan)
    fusion_native_literal_regs = build_fusion_native_literal_regs(plan)
    const_c_expr_regs = build_const_c_expr_regs(plan)
    native_scalar_out = Map.get(plan, :native_scalar_return)
    ret_reg = ret_source_reg(plan)
    native_int_only_regs = build_native_int_only_regs(plan, decl_map)

    native_int_only_regs =
      maybe_add_native_ret_reg(native_int_only_regs, plan, ret_reg, native_scalar_out)

    unused_native_int_skip_regs = build_unused_native_int_skip_regs(plan, native_int_only_regs)

    tail_inline_skip_regs =
      plan
      |> build_tail_inline_skip_regs()
      |> MapSet.union(build_record_param_inline_skip_regs(plan, param_kinds))
      |> MapSet.union(build_unused_boxed_param_skip_regs(plan, param_kinds))
      |> MapSet.union(build_overwritten_inline_skip_regs(plan))
      |> MapSet.union(unused_native_int_skip_regs)

    slots = Map.drop(slots, MapSet.to_list(tail_inline_skip_regs))

    native_int_mutable_regs =
      native_int_mutable_regs(plan, native_int_only_regs)
      |> MapSet.difference(unused_native_int_skip_regs)
    native_bool_only_regs =
      build_native_bool_only_regs(plan, decl_map)
      |> MapSet.difference(native_int_only_regs)
      |> maybe_add_native_scalar_ret_bool_reg(ret_reg, native_scalar_out)

    native_bool_mutable_regs = native_bool_mutable_regs(plan, native_bool_only_regs)

    native_int_locals =
      native_int_only_regs
      |> MapSet.difference(MapSet.new(Map.keys(const_int_regs)))
      |> MapSet.difference(MapSet.new(Map.keys(const_c_expr_regs)))
      |> MapSet.difference(MapSet.new(Map.keys(native_int_regs)))
      |> MapSet.difference(unused_native_int_skip_regs)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Map.new(fn reg -> {reg, "plan_native_int_#{reg}"} end)

    native_bool_locals =
      native_bool_only_regs
      |> MapSet.to_list()
      |> Enum.sort()
      |> Map.new(fn reg -> {reg, "plan_native_bool_#{reg}"} end)

    native_int_operand_regs =
      native_int_regs
      |> Map.merge(Map.new(const_int_regs, fn {reg, entry} -> {reg, const_int_c_ref_for_inline(entry, plan.module)} end))
      |> Map.merge(const_c_expr_regs)
      |> Map.merge(native_int_locals)

    slots = finalize_owned_slots_map(plan, slots, native_int_only_regs, native_bool_only_regs, fusion_native_literal_regs)

    native_int_inline =
      NativeIntFold.inline_exprs(plan,
        slots: slots,
        native_int_only_regs: native_int_only_regs,
        native_bool_only_regs: native_bool_only_regs,
        native_int_regs: native_int_operand_regs,
        const_int_regs: const_int_regs,
        native_ret_reg: ret_reg
      )

    native_ret_deferred_regs =
      build_native_ret_deferred_release_regs(plan, slots, native_int_inline, native_int_only_regs)

    native_int_locals =
      native_int_locals
      |> Map.drop(Map.keys(native_int_inline))

    native_int_operand_regs =
      native_int_operand_regs
      |> Map.drop(Map.keys(native_int_inline))

    slot_count = owned_slot_count(slots)

    string_fusion =
      StringConcat.analyze(plan,
        slots: slots,
        borrow_param_regs: borrow_param_regs,
        native_int_only_regs: native_int_only_regs,
        native_int_regs: native_int_operand_regs,
        const_int_regs: const_int_regs,
        native_int_inline: native_int_inline,
        parent_plan: plan
      )

    instr_opts = [
      owned_slot_count: slot_count,
      rc_required: rc?,
      epilogue_lifo: slot_count > 0,
      params: param_names(plan.params),
      param_kinds: param_kinds,
      native_int_regs: native_int_operand_regs,
      borrow_param_regs: borrow_param_regs,
      closure_borrow_regs: closure_borrow_regs,
      const_int_regs: const_int_regs,
      fusion_native_literal_regs: fusion_native_literal_regs,
      native_int_only_regs: native_int_only_regs,
      native_int_mutable_regs: native_int_mutable_regs,
      native_bool_only_regs: native_bool_only_regs,
      native_bool_regs: native_bool_locals,
      native_bool_mutable_regs: native_bool_mutable_regs,
      native_int_inline: native_int_inline,
      native_ret_deferred_regs: native_ret_deferred_regs,
      native_scalar_out: native_scalar_out,
      native_ret_reg: ret_reg,
      fused_string_roots: string_fusion.roots,
      fused_string_skip_regs: string_fusion.skip_regs,
      tail_inline_skip_regs: tail_inline_skip_regs,
      direct_scene_writer: Process.get(:elmc_direct_scene_writer, false),
      scene_writer_var: "writer",
      ownership: Map.get(lookup_decl(plan.module, plan.name) || %{}, :ownership, []),
      lambdas: plan.lambdas || [],
      parent_plan: plan,
      module: plan.module,
      closure_mode: Keyword.get(opts, :closure_mode)
    ]

    explicit_targets = explicit_jump_target_ids(plan.blocks)

    mutable_decls =
      native_int_decl_lines(native_int_locals, native_int_mutable_regs) ++
        native_bool_mutable_decl_lines(native_bool_locals, native_bool_mutable_regs)

    Process.put(:elmc_plan_owned_live, MapSet.new())

    body_lines =
      if state_switch_emit?(plan) do
        emit_state_switch_body(plan, slots, instr_opts, mutable_decls)
      else
        emit_goto_body(plan, slots, instr_opts, mutable_decls, explicit_targets)
      end

    ret_line =
      emit_return(plan, slots, native_scalar_out, emit_borrow_param_nulls(plan, slots), instr_opts)

    deferred_cleanup = emit_deferred_consume_releases(instr_opts, slots)

    (body_lines ++ List.wrap(ret_line) ++ List.wrap(deferred_cleanup))
    |> Enum.reject(&(&1 == ""))
    |> cleanup_cfg_lines()
    |> Enum.join("\n")
  end

  defp emit_goto_body(plan, slots, instr_opts, mutable_decls, explicit_targets) do
    rc? = Keyword.get(instr_opts, :rc_required, true)

    plan.blocks
    |> Enum.with_index()
    |> Enum.flat_map(fn {%Block{id: id, instrs: instrs, terminator: term}, idx} ->
      next_id =
        case Enum.at(plan.blocks, idx + 1) do
          %Block{id: next} -> next
          _ -> nil
        end

      (if labeled_block?(id, explicit_targets), do: [block_label(id)], else: []) ++
        Enum.flat_map(instrs, &emit_instr_lines(&1, slots, instr_opts)) ++
        [emit_terminator(term, slots, rc?, Keyword.put(instr_opts, :next_id, next_id))]
    end)
    |> Enum.reject(&(&1 == ""))
    |> then(&(mutable_decls ++ &1))
  end

  defp state_switch_emit?(%FunctionPlan{} = plan) do
    codegen_opts = Process.get(:elmc_codegen_opts, %{})
    thresholds = SizeProfile.plan_state_switch_thresholds(codegen_opts)

    SizeProfile.plan_emit_mode(codegen_opts) == :state_switch and
      not is_binary(Map.get(plan, :fusion_c)) and
      Map.get(plan, :native_scalar_return) not in [:native_int, :native_bool] and
      length(plan.blocks) >= thresholds.min_blocks and
      plan_emit_owned_slot_count(plan) <= thresholds.max_owned_slots
  end

  defp emit_state_switch_body(%FunctionPlan{blocks: blocks} = plan, slots, instr_opts, mutable_decls) do
    rc? = Keyword.get(instr_opts, :rc_required, true)
    state_labels = TagRefs.build_plan_state_labels(plan)
    instr_opts = Keyword.merge(instr_opts, plan_state_labels: state_labels)
    entry_id = blocks |> List.first() |> Map.get(:id, 0)
    entry_ref = TagRefs.plan_state_ref(plan, entry_id, state_labels)

    cases =
      blocks
      |> Enum.map(fn %Block{id: id, instrs: instrs, terminator: term} ->
        state_ref = TagRefs.plan_state_ref(plan, id, state_labels)

        instr_lines =
          instrs
          |> Enum.flat_map(&emit_instr_lines(&1, slots, instr_opts))
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&("    " <> &1))
          |> Enum.join("\n")

        term_line =
          emit_state_switch_terminator(term, slots, rc?, instr_opts)
          |> String.trim()
          |> then(fn line -> if line == "", do: "", else: "    " <> line end)

        body =
          [instr_lines, term_line]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        "    case #{state_ref}:\n#{body}"
      end)
      |> Enum.join("\n")

    enum = TagRefs.emit_plan_state_enum(plan, state_labels)

    loop = """
    #{enum}
    elmc_int_t __plan_state = #{entry_ref};
    for (;;) {
      switch (__plan_state) {
    #{cases}
        default:
          break;
      }
      if (__plan_state < 0) break;
    }
    """
    |> String.trim()

    mutable_decls ++ [loop]
  end

  defp plan_state_c_ref(opts, block_id) when is_integer(block_id) do
    plan = Keyword.fetch!(opts, :parent_plan)
    labels = Keyword.get(opts, :plan_state_labels, %{})
    TagRefs.plan_state_ref(plan, block_id, labels)
  end

  defp plan_module_from(opts) do
    Keyword.get(opts, :module) ||
      case Keyword.get(opts, :parent_plan) do
        %{module: mod} when is_binary(mod) -> mod
        _ -> nil
      end
  end

  defp union_switch_tag_ref(tag, ctor_name, module) when is_integer(tag) do
    TagRefs.union_tag_ref(tag, ctor_name, module)
  end

  defp const_int_c_ref_for_inline(value, module)

  defp const_int_c_ref_for_inline(value, _module) when is_integer(value), do: Integer.to_string(value)

  defp const_int_c_ref_for_inline({value, ctor}, module) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, module)

  defp emit_state_switch_terminator({:br, target_id}, _slots, _rc?, opts) do
    "__plan_state = #{plan_state_c_ref(opts, target_id)}; break;"
  end

  defp emit_state_switch_terminator({:br_if, then_id, else_id, cond_reg}, slots, _rc?, opts) do
    cond = Instr.branch_cond_expr(cond_reg, slots, opts)
    then_ref = plan_state_c_ref(opts, then_id)
    else_ref = plan_state_c_ref(opts, else_id)
    "__plan_state = (#{cond}) ? #{then_ref} : #{else_ref}; break;"
  end

  defp emit_state_switch_terminator({:switch_tag, subject, arms, default_id}, slots, _rc?, opts) do
    subject_s = Instr.switch_subject_ref(subject, slots, opts)

    cond do
      native_int_switch_subject?(subject, opts) ->
        emit_state_int_switch(subject_s, arms, default_id, opts)

      ctor_int_tag_switch_subject?(subject, opts) ->
        emit_state_int_switch("elmc_as_int(#{subject_s})", arms, default_id, opts)

      true ->
        emit_state_union_switch(subject_s, arms, default_id, opts)
    end
  end

  defp emit_state_switch_terminator({:ret, :fn_out}, _slots, _rc?, _opts) do
    "__plan_state = -1; break;"
  end

  defp emit_state_switch_terminator({:ret, reg}, slots, _rc?, opts) when is_integer(reg) do
    assign =
      case Keyword.get(opts, :native_scalar_out) do
        :native_int ->
          ref = native_int_result_ref(reg, slots, opts)
          "*out = #{ref};"

        :native_bool ->
          ref = native_bool_result_ref(reg, opts)
          "*out = #{ref};"

        _ ->
          ref = slot_ref(reg, slots, opts)
          idx = Map.get(slots, reg)

          if is_integer(idx) do
            "*out = #{ref};\nowned[#{idx}] = NULL;"
          else
            "*out = #{ref};"
          end
      end

    "#{assign}\n    __plan_state = -1; break;"
  end

  defp emit_state_switch_terminator(:none, _slots, _rc?, _opts), do: "__plan_state = -1; break;"
  defp emit_state_switch_terminator(_, _slots, _rc?, _opts), do: "__plan_state = -1; break;"

  defp emit_state_int_switch(subject_s, arms, default_id, opts) do
    if length(arms) >= @min_switch_arms do
      emit_state_int_c_switch(subject_s, arms, default_id, opts)
    else
      emit_state_int_switch_chain(subject_s, arms, default_id, opts)
    end
  end

  defp emit_state_union_switch(subject_s, arms, default_id, opts) do
    if length(arms) >= @min_switch_arms do
      emit_state_union_c_switch(subject_s, arms, default_id, opts)
    else
      emit_state_union_switch_chain(subject_s, arms, default_id, opts)
    end
  end

  defp emit_state_int_switch_chain(subject_s, arms, default_id, opts) do
    arm_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        target_id = TagRefs.switch_arm_target(arm)
        tag_ref = union_switch_tag_ref(tag, TagRefs.switch_arm_ctor(arm), plan_module_from(opts))

        "if (#{subject_s} == #{tag_ref}) { __plan_state = #{plan_state_c_ref(opts, target_id)}; break; }"
      end)

    default_line = state_switch_default_line(default_id, opts)

    (arm_lines ++ List.wrap(default_line)) |> Enum.join("\n    ")
  end

  defp emit_state_union_switch_chain(subject_s, arms, default_id, opts) do
    arm_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        target_id = TagRefs.switch_arm_target(arm)
        tag_ref = union_switch_tag_ref(tag, TagRefs.switch_arm_ctor(arm), plan_module_from(opts))

        "if (elmc_union_tag_matches(#{subject_s}, #{tag_ref})) { __plan_state = #{plan_state_c_ref(opts, target_id)}; break; }"
      end)

    default_line = state_switch_default_line(default_id, opts)

    (arm_lines ++ List.wrap(default_line)) |> Enum.join("\n    ")
  end

  defp emit_state_int_c_switch(subject_s, arms, default_id, opts) do
    case_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        target_id = TagRefs.switch_arm_target(arm)
        tag_ref = union_switch_tag_ref(tag, TagRefs.switch_arm_ctor(arm), plan_module_from(opts))

        "case #{tag_ref}: __plan_state = #{plan_state_c_ref(opts, target_id)}; break;"
      end)

    default_line = state_switch_c_default_line(default_id, opts)

    """
    switch (#{subject_s}) {
      #{Enum.join(case_lines ++ List.wrap(default_line), "\n      ")}
    }
    break;
    """
    |> String.trim()
  end

  defp emit_state_union_c_switch(subject_s, arms, default_id, opts) do
    tag_expr = plan_union_tag_expr(subject_s)

    case_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        target_id = TagRefs.switch_arm_target(arm)
        tag_ref = union_switch_tag_ref(tag, TagRefs.switch_arm_ctor(arm), plan_module_from(opts))

        "case #{tag_ref}: __plan_state = #{plan_state_c_ref(opts, target_id)}; break;"
      end)

    default_line = state_switch_c_default_line(default_id, opts)

    """
    switch (#{tag_expr}) {
      #{Enum.join(case_lines ++ List.wrap(default_line), "\n      ")}
    }
    break;
    """
    |> String.trim()
  end

  defp state_switch_default_line(nil, _opts), do: nil

  defp state_switch_default_line(target_id, opts),
    do: "__plan_state = #{plan_state_c_ref(opts, target_id)}; break;"

  defp state_switch_c_default_line(nil, _opts), do: nil

  defp state_switch_c_default_line(target_id, opts),
    do: "default: __plan_state = #{plan_state_c_ref(opts, target_id)}; break;"

  defp cleanup_cfg_lines(lines) do
    lines
    |> coalesce_consecutive_block_labels()
    |> remove_redundant_cfg_jumps()
    |> remove_unused_block_labels()
  end

  defp remove_unused_block_labels(lines) do
    targets =
      lines
      |> Enum.flat_map(fn line ->
        trimmed = String.trim(line)

        if Regex.match?(~r/^elmc_plan_block_\d+:$/, trimmed) do
          []
        else
          Regex.scan(~r/\belmc_plan_block_(\d+)\b/, line)
          |> Enum.map(fn [_, id_s] -> String.to_integer(id_s) end)
        end
      end)
      |> MapSet.new()

    Enum.reject(lines, fn line ->
      case block_label_id(line) do
        id when is_integer(id) and id > 0 -> not MapSet.member?(targets, id)
        _ -> false
      end
    end)
  end

  defp coalesce_consecutive_block_labels(lines) do
    {out, aliases, pending} =
      Enum.reduce(lines, {[], %{}, []}, fn line, {out, aliases, pending} ->
        case block_label_id(line) do
          id when is_integer(id) ->
            {out, Map.put(aliases, id, id), pending ++ [id]}

          _ ->
            {out, aliases} = flush_pending_labels(out, aliases, pending)
            {out ++ [line], aliases, []}
        end
      end)

    {out, aliases} = flush_pending_labels(out, aliases, pending)
    rewrite_block_label_refs(out, aliases)
  end

  defp flush_pending_labels(out, aliases, []), do: {out, aliases}

  defp flush_pending_labels(out, aliases, pending) do
    pending = Enum.reverse(pending)
    keeper = List.last(pending)

    aliases =
      Enum.reduce(pending, aliases, fn id, map ->
        if id == keeper, do: map, else: Map.put(map, id, keeper)
      end)

    {out ++ [block_label(keeper)], aliases}
  end

  defp block_label_id("/* plan block 0 */"), do: 0

  defp block_label_id(line) when is_binary(line) do
    case Regex.run(~r/^elmc_plan_block_(\d+):$/, String.trim(line)) do
      [_, id_s] -> String.to_integer(id_s)
      _ -> nil
    end
  end

  defp rewrite_block_label_refs(lines, aliases) when map_size(aliases) == 0, do: lines

  defp rewrite_block_label_refs(lines, aliases) do
    Enum.map(lines, fn line ->
      Regex.replace(~r/\belmc_plan_block_(\d+)\b/, line, fn _, id_s ->
        id = String.to_integer(id_s)
        "elmc_plan_block_#{Map.get(aliases, id, id)}"
      end)
    end)
  end

  defp remove_redundant_cfg_jumps(lines) do
    do_remove_redundant_cfg_jumps(lines)
  end

  defp do_remove_redundant_cfg_jumps([]), do: []

  defp do_remove_redundant_cfg_jumps([a, b | rest]) do
    cond do
      unified_branch_to_same_target?(a, b) ->
        do_remove_redundant_cfg_jumps(rest)

      redundant_goto_before_label?(a, b) ->
        do_remove_redundant_cfg_jumps([b | rest])

      if_goto_targets_label?(a, b) ->
        do_remove_redundant_cfg_jumps(rest)

      true ->
        [a | do_remove_redundant_cfg_jumps([b | rest])]
    end
  end

  defp do_remove_redundant_cfg_jumps([a]), do: [a]

  defp unified_branch_to_same_target?(if_line, goto_line) do
    with {:ok, t1} <- if_goto_target(if_line),
         {:ok, t2} <- goto_target(goto_line),
         true <- t1 == t2 do
      true
    else
      _ -> false
    end
  end

  defp redundant_goto_before_label?(goto_line, label_line) do
    with {:ok, target} <- goto_target(goto_line),
         {:ok, ^target} <- block_label_target(label_line) do
      true
    else
      _ -> false
    end
  end

  defp if_goto_targets_label?(if_line, label_line) do
    with {:ok, target} <- if_goto_target(if_line),
         {:ok, ^target} <- block_label_target(label_line) do
      true
    else
      _ -> false
    end
  end

  defp if_goto_target(line) do
    case Regex.run(~r/^if \(.+\) goto (elmc_plan_block_\d+);$/, String.trim(line)) do
      [_, target] -> {:ok, target}
      _ -> :error
    end
  end

  defp goto_target(line) do
    case Regex.run(~r/^goto (elmc_plan_block_\d+);$/, String.trim(line)) do
      [_, target] -> {:ok, target}
      _ -> :error
    end
  end

  defp block_label_target(line) do
    case block_label_id(line) do
      id when is_integer(id) -> {:ok, "elmc_plan_block_#{id}"}
      _ -> :error
    end
  end

  defp block_label(0), do: "/* plan block 0 */"
  defp block_label(id), do: "elmc_plan_block_#{id}:"

  defp labeled_block?(0, _), do: true
  defp labeled_block?(id, explicit_targets), do: MapSet.member?(explicit_targets, id)

  defp explicit_jump_target_ids(blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.flat_map(fn {%Block{terminator: term}, idx} ->
      next_id =
        case Enum.at(blocks, idx + 1) do
          %Block{id: next} -> next
          _ -> nil
        end

      explicit_targets_from_terminator(term, next_id)
    end)
    |> MapSet.new()
  end

  defp explicit_targets_from_terminator({:br, target_id}, next_id) do
    if target_id == next_id, do: [], else: [target_id]
  end

  defp explicit_targets_from_terminator({:br_if, then_id, else_id, _}, next_id) do
    []
    |> maybe_add_target(then_id, then_id != next_id)
    |> maybe_add_target(else_id, else_id != next_id)
  end

  defp explicit_targets_from_terminator({:switch_tag, _, arms, default_id}, next_id) do
    Enum.map(arms, &TagRefs.switch_arm_target/1) ++
      if(default_id != next_id, do: [default_id], else: [])
  end

  defp explicit_targets_from_terminator(_, _), do: []

  defp maybe_add_target(list, _id, false), do: list
  defp maybe_add_target(list, id, true), do: [id | list]

  defp emit_instr_lines(instr, slots, instr_opts) do
    live = Process.get(:elmc_plan_owned_live, MapSet.new())
    {reassignment, live} = owned_reassign_prefix(instr, slots, instr_opts, live)
    code = Instr.emit(instr, slots, instr_opts)
    nulls =
      if tail_fn_out_owned_cleanup_instr?(instr) do
        []
      else
        emit_null_consumed_slots(instr, slots, instr_opts)
      end
    live = update_owned_live_slots(instr, slots, instr_opts, live)
    Process.put(:elmc_plan_owned_live, live)

    [reassignment, code, nulls]
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
  end

  defp owned_reassign_prefix(instr, slots, instr_opts, live) do
    dest = Map.get(instr, :dest)
    operands = plan_value_operand_regs(instr)

    with dest when is_integer(dest) <- dest,
         false <- dest in operands,
         idx when is_integer(idx) <- boxed_owned_index(dest, slots, instr_opts),
         true <- MapSet.member?(live, idx) do
      prefix = "elmc_release(owned[#{idx}]);\nowned[#{idx}] = NULL;"

      {prefix, MapSet.delete(live, idx)}
    else
      _ -> {"", live}
    end
  end

  defp update_owned_live_slots(instr, slots, instr_opts, live) do
    live = clear_consumed_owned_slots(instr, slots, instr_opts, live)

    case Map.get(instr, :dest) do
      dest when is_integer(dest) ->
        case boxed_owned_index(dest, slots, instr_opts) do
          idx when is_integer(idx) -> MapSet.put(live, idx)
          _ -> live
        end

      _ ->
        live
    end
  end

  defp clear_consumed_owned_slots(instr, slots, instr_opts, live) do
    consumes =
      case Map.get(instr, :effects) do
        %{consumes: consumes} when is_list(consumes) -> consumes
        _ -> []
      end

    deferred = Keyword.get(instr_opts, :native_ret_deferred_regs, MapSet.new())
    closure_borrows = Keyword.get(instr_opts, :closure_borrow_regs, MapSet.new())

    consumes
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :native_int_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :native_bool_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :tail_inline_skip_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(deferred, &1))
    |> Enum.reject(&MapSet.member?(closure_borrows, &1))
    |> Enum.uniq()
    |> Enum.reduce(live, fn reg, acc ->
      case boxed_owned_index(reg, slots, instr_opts) do
        idx when is_integer(idx) -> MapSet.delete(acc, idx)
        _ -> acc
      end
    end)
  end

  defp boxed_owned_index(reg, slots, instr_opts) when is_integer(reg) do
    if MapSet.member?(Keyword.get(instr_opts, :native_int_only_regs, MapSet.new()), reg) or
         MapSet.member?(Keyword.get(instr_opts, :native_bool_only_regs, MapSet.new()), reg) or
         MapSet.member?(Keyword.get(instr_opts, :tail_inline_skip_regs, MapSet.new()), reg) do
      nil
    else
      Map.get(slots, reg)
    end
  end

  defp tail_fn_out_owned_cleanup_instr?(%{op: op, dest: dest})
       when op in [:call_runtime, :call_fn, :call_closure] and dest in [:fn_out, :branch_out],
       do: true

  defp tail_fn_out_owned_cleanup_instr?(_), do: false

  defp emit_null_consumed_slots(%{op: :publish}, _slots, _instr_opts), do: []

  defp emit_null_consumed_slots(%{op: :release}, _slots, _instr_opts), do: []

  defp emit_null_consumed_slots(%{effects: %{consumes: consumes}} = instr, slots, instr_opts)
       when is_list(consumes) do
    deferred = Keyword.get(instr_opts, :native_ret_deferred_regs, MapSet.new())
    transfer? = transferring_consume_instr?(instr)

    consumes
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :native_int_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :native_bool_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :tail_inline_skip_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(deferred, &1))
    |> Enum.uniq()
    |> Enum.map(fn reg ->
      case Map.get(slots, reg) do
        i when is_integer(i) ->
          if transfer? do
            "owned[#{i}] = NULL;"
          else
            "elmc_release(owned[#{i}]);\nowned[#{i}] = NULL;"
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp emit_null_consumed_slots(_, _slots, _instr_opts), do: []

  defp transferring_consume_instr?(%{op: :const_static_list, args: %{kind: kind}})
       when kind in [:values, :record_array],
       do: true

  defp transferring_consume_instr?(%{op: :call_runtime, args: %{builtin: id}}) do
    id in [:record_new_take, :record_new_values_ints, :tuple2_take]
  end

  defp transferring_consume_instr?(_), do: false

  defp build_native_ret_deferred_release_regs(
         %FunctionPlan{} = plan,
         slots,
         native_int_inline,
         native_int_only_regs
       ) do
    if Map.get(plan, :native_scalar_return) in [:native_int, :native_bool] do
      case ret_source_reg(plan) do
        ret when is_integer(ret) ->
          if Map.has_key?(native_int_inline, ret) do
            plan
            |> all_defining_instrs(ret)
            |> List.first()
            |> int_arith_owned_operand_regs()
            |> Enum.filter(fn reg ->
              is_integer(reg) and Map.has_key?(slots, reg) and
                not MapSet.member?(native_int_only_regs, reg)
            end)
            |> MapSet.new()
          else
            MapSet.new()
          end

        _ ->
          MapSet.new()
      end
    else
      MapSet.new()
    end
  end

  defp int_arith_owned_operand_regs(%{op: :int_arith, args: %{kind: kind} = args})
       when kind in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars] do
    [Map.get(args, :lhs), Map.get(args, :rhs)]
    |> Enum.filter(&is_integer/1)
  end

  defp int_arith_owned_operand_regs(%{op: :int_arith, args: %{kind: kind, lhs: lhs}})
       when kind in [:add_const, :sub_const] and is_integer(lhs),
       do: [lhs]

  defp int_arith_owned_operand_regs(_), do: []

  defp emit_deferred_consume_releases(instr_opts, slots) do
    instr_opts
    |> Keyword.get(:native_ret_deferred_regs, MapSet.new())
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(fn reg ->
      case Map.get(slots, reg) do
        i when is_integer(i) -> "elmc_release(owned[#{i}]);\nowned[#{i}] = NULL;"
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      lines -> Enum.join(lines, "\n")
    end
  end

  defp emit_terminator({:br_if, then_id, else_id, cond_reg}, slots, _rc?, opts) do
    next_id = Keyword.get(opts, :next_id)
    native_bool? = MapSet.member?(Keyword.get(opts, :native_bool_only_regs, MapSet.new()), cond_reg)
    cond = Instr.branch_cond_expr(cond_reg, slots, opts)

    neg_cond =
      if native_bool? do
        "!#{cond}"
      else
        "#{cond} == 0"
      end

    pos_cond =
      if native_bool? do
        cond
      else
        "#{cond} != 0"
      end

    case {next_id == then_id, next_id == else_id} do
      {true, true} ->
        ""

      {true, false} ->
        "if (#{neg_cond}) goto elmc_plan_block_#{else_id};"

      {false, true} ->
        "if (#{pos_cond}) goto elmc_plan_block_#{then_id};"

      {false, false} ->
        """
        if (#{pos_cond}) {
          goto elmc_plan_block_#{then_id};
        } else {
          goto elmc_plan_block_#{else_id};
        }
        """
        |> String.trim()
    end
  end

  defp emit_terminator({:br, target_id}, _slots, _rc?, opts) do
    if Keyword.get(opts, :next_id) == target_id do
      ""
    else
      "goto elmc_plan_block_#{target_id};"
    end
  end

  defp emit_terminator({:switch_tag, subject, arms, default_id}, slots, _rc?, opts) do
    subject_s = Instr.switch_subject_ref(subject, slots, opts)
    _next_id = Keyword.get(opts, :next_id)

    cond do
      native_int_switch_subject?(subject, opts) ->
        emit_int_switch(subject_s, arms, default_id, opts)

      ctor_int_tag_switch_subject?(subject, opts) ->
        emit_int_switch("elmc_as_int(#{subject_s})", arms, default_id, opts)

      true ->
        emit_union_switch(subject_s, arms, default_id, opts)
    end
  end

  defp emit_terminator({:ret, _}, _slots, _rc?, _opts), do: ""
  defp emit_terminator(:none, _slots, _rc?, _opts), do: ""
  defp emit_terminator(_, _slots, _rc?, _opts), do: ""

  defp ctor_int_tag_switch_subject?(reg, opts) when is_integer(reg) do
    case plan_defining_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :call_fn, args: %{module: mod, name: name}} ->
        ctor_int_tag_return_type?(lookup_decl(mod, name))

      _ ->
        false
    end
  end

  defp ctor_int_tag_return_type?(%{type: type}) when is_binary(type) do
    return =
      type
      |> String.replace(" ", "")
      |> String.split("->")
      |> List.last()

    enums = Process.get(:elmc_enum_types, MapSet.new())

    MapSet.member?(enums, return) or
      MapSet.member?(enums, type_short_name(return))
  end

  defp ctor_int_tag_return_type?(_), do: false

  defp type_short_name(qualified) when is_binary(qualified) do
    qualified |> String.split(".") |> List.last()
  end

  defp native_int_switch_subject?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg) or
      native_param_kind(reg, opts) == :native_int
  end

  defp native_param_kind(reg, opts) do
    case plan_defining_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} ->
        Enum.at(Keyword.get(opts, :param_kinds, []), index)

      _ ->
        nil
    end
  end

  defp emit_int_switch(subject_s, arms, default_id, opts) do
    _next_id = Keyword.get(opts, :next_id)

    if length(arms) >= @min_switch_arms do
      emit_int_c_switch(subject_s, arms, default_id, opts)
    else
      emit_int_switch_chain(subject_s, arms, default_id, opts)
    end
  end

  defp emit_union_switch(subject_s, arms, default_id, opts) do
    if length(arms) >= @min_switch_arms do
      emit_union_c_switch(subject_s, arms, default_id, opts)
    else
      emit_switch_tag_chain(subject_s, arms, default_id, opts)
    end
  end

  defp emit_int_c_switch(subject_s, arms, default_id, opts) do
    next_id = Keyword.get(opts, :next_id)
    module = plan_module_from(opts)

    case_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        block_id = TagRefs.switch_arm_target(arm)
        tag_ref = TagRefs.union_tag_ref(tag, TagRefs.switch_arm_ctor(arm), module)
        "case #{tag_ref}: goto elmc_plan_block_#{block_id};"
      end)

    default_line =
      if default_id == next_id do
        nil
      else
        "default: goto elmc_plan_block_#{default_id};"
      end

    body_lines = case_lines ++ List.wrap(default_line)

    """
    switch (#{subject_s}) {
      #{Enum.join(body_lines, "\n  ")}
    }
    """
    |> String.trim()
  end

  defp emit_union_c_switch(subject_s, arms, default_id, opts) do
    next_id = Keyword.get(opts, :next_id)
    module = plan_module_from(opts)
    tag_expr = plan_union_tag_expr(subject_s)

    case_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        block_id = TagRefs.switch_arm_target(arm)
        tag_ref = TagRefs.union_tag_ref(tag, TagRefs.switch_arm_ctor(arm), module)
        "case #{tag_ref}: goto elmc_plan_block_#{block_id};"
      end)

    default_line =
      if default_id == next_id do
        nil
      else
        "default: goto elmc_plan_block_#{default_id};"
      end

    body_lines = case_lines ++ List.wrap(default_line)

    """
    switch (#{tag_expr}) {
      #{Enum.join(body_lines, "\n  ")}
    }
    """
    |> String.trim()
  end

  defp plan_union_tag_expr(subject_s) do
    "(#{subject_s} && (#{subject_s})->tag == ELMC_TAG_INT ? elmc_as_int(#{subject_s}) : " <>
      "(#{subject_s} && (#{subject_s})->tag == ELMC_TAG_TUPLE2 && (#{subject_s})->payload != NULL ? " <>
      "elmc_as_int(((ElmcTuple2 *)(#{subject_s})->payload)->first) : -1))"
  end

  defp emit_int_switch_chain(subject_s, arms, default_id, opts) do
    next_id = Keyword.get(opts, :next_id)
    module = plan_module_from(opts)

    {prefix, arms} =
      case arms do
        [arm | rest] ->
          case {TagRefs.switch_arm_tag(arm), TagRefs.switch_arm_target(arm), next_id} do
            {tag, ^next_id, _} when not is_nil(next_id) ->
              tag_ref = TagRefs.union_tag_ref(tag, TagRefs.switch_arm_ctor(arm), module)
              {"if (#{subject_s} != #{tag_ref}) ", rest}

            _ ->
              {"", arms}
          end

        _ ->
          {"", arms}
      end

    arm_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        block_id = TagRefs.switch_arm_target(arm)
        tag_ref = TagRefs.union_tag_ref(tag, TagRefs.switch_arm_ctor(arm), module)
        "if (#{subject_s} == #{tag_ref}) goto elmc_plan_block_#{block_id};"
      end)

    default_line =
      if default_id == next_id do
        nil
      else
        "goto elmc_plan_block_#{default_id};"
      end

    inner =
      case {arm_lines, default_line} do
        {[], nil} -> ""
        {[], line} -> line
        {lines, nil} -> join_switch_tag_arms(lines)
        {lines, line} -> join_switch_tag_arms(lines) <> "\nelse " <> line
      end

    case {prefix, inner} do
      {"", ""} -> ""
      {"", body} -> body
      {pre, ""} -> String.trim(pre)
      {pre, body} -> pre <> "{\n  " <> body <> "\n}"
    end
  end

  defp emit_switch_tag_chain(subject_s, arms, default_id, opts) do
    next_id = Keyword.get(opts, :next_id)
    module = plan_module_from(opts)

    {prefix, arms} =
      case arms do
        [arm | rest] ->
          case {TagRefs.switch_arm_tag(arm), TagRefs.switch_arm_target(arm), next_id} do
            {tag, ^next_id, _} when not is_nil(next_id) ->
              tag_ref = TagRefs.union_tag_ref(tag, TagRefs.switch_arm_ctor(arm), module)
              {"if (!elmc_union_tag_matches(#{subject_s}, #{tag_ref})) ", rest}

            _ ->
              {"", arms}
          end

        _ ->
          {"", arms}
      end

    arm_lines =
      Enum.map(arms, fn arm ->
        tag = TagRefs.switch_arm_tag(arm)
        block_id = TagRefs.switch_arm_target(arm)
        tag_ref = TagRefs.union_tag_ref(tag, TagRefs.switch_arm_ctor(arm), module)
        "if (elmc_union_tag_matches(#{subject_s}, #{tag_ref})) goto elmc_plan_block_#{block_id};"
      end)

    default_line =
      if default_id == next_id do
        nil
      else
        "goto elmc_plan_block_#{default_id};"
      end

    inner =
      case {arm_lines, default_line} do
        {[], nil} -> ""
        {[], line} -> line
        {lines, nil} -> join_switch_tag_arms(lines)
        {lines, line} -> join_switch_tag_arms(lines) <> "\nelse " <> line
      end

    case {prefix, inner} do
      {"", ""} -> ""
      {"", body} -> body
      {pre, ""} -> String.trim(pre)
      {pre, body} -> pre <> "{\n  " <> body <> "\n}"
    end
  end

  defp join_switch_tag_arms(lines) do
    lines
    |> Enum.intersperse("\nelse ")
    |> Enum.join("")
  end

  defp wrap_shell(%FunctionPlan{} = plan, core) do
    if Map.get(plan, :native_scalar_value_return) do
      String.trim(core)
    else
      wrap_rc_shell(plan, core)
    end
  end

  defp wrap_rc_shell(%FunctionPlan{rc_required: rc?, fallible: fallible?} = plan, core) do
    {slots, slot_count} = prepared_owned_slots(plan)
    owned = Frame.owned_declaration(plan, slots)
    slot_indices = if slot_count > 0, do: Enum.to_list(0..(slot_count - 1)), else: []
    epilogue = Frame.epilogue_release(slot_indices, slot_count)
    prefix = if rc?, do: ["RC Rc = RC_SUCCESS;", owned], else: List.wrap(owned)
    letrec_decls = letrec_decl_lines(plan.letrec_refs || [])
    letrec_free = letrec_free_lines(plan.letrec_refs || [])

    suffix =
      cond do
        rc? -> letrec_free ++ [epilogue, "return Rc;"]
        slot_count > 0 -> letrec_free
        true -> letrec_free
      end

    needs_catch? = rc? and fallible?

    (letrec_decls ++ prefix ++ [Frame.wrap_catch(needs_catch?, core)] ++ suffix)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp borrow_null_cleanup_lines([]), do: ""

  defp borrow_null_cleanup_lines(nulls) do
    nulls
    |> Enum.map(&"    #{&1}")
    |> Enum.join("\n")
  end

  defp emit_borrow_param_nulls(plan, slots) do
    ownership = Map.get(lookup_decl(plan.module, plan.name) || %{}, :ownership, [])

    if :retain_arg in List.wrap(ownership) do
      []
    else
      decl_map = Process.get(:elmc_program_decls, %{})
      param_kinds = param_kinds_for_plan(plan)
      {borrow_param_regs, _} =
        allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, nil)

      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))
      |> Enum.reject(fn %{dest: reg} -> Map.has_key?(borrow_param_regs, reg) end)
      |> Enum.map(fn %{dest: reg} ->
        case Map.get(slots, reg) do
          i when is_integer(i) -> "owned[#{i}] = NULL;"
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end
  end

  @spec emit_function_def(FunctionPlan.t(), keyword()) :: String.t()
  def emit_function_def(%FunctionPlan{} = plan, opts \\ []) do
    c_name = Util.module_fn_name(plan.module, plan.name)
    args = Enum.map_join(plan.params, ", ", fn p -> "ElmcValue *#{p.name}" end)

    if plan.rc_required do
      """
      static RC #{c_name}(ElmcValue **out, #{args}) {
      #{emit(plan, opts)}
      }
      """
    else
      """
      static ElmcValue *#{c_name}(#{args}) {
      #{emit(plan, opts)}
      }
      """
    end
    |> String.trim()
  end

  @doc false
  @spec prepared_owned_slots(FunctionPlan.t(), keyword()) :: {map(), non_neg_integer()}
  def prepared_owned_slots(%FunctionPlan{} = plan, opts \\ []) do
    slots = prepare_owned_slots_map(plan, opts)
    {slots, owned_slot_count(slots)}
  end

  @doc false
  @spec plan_emit_owned_slot_count(FunctionPlan.t()) :: non_neg_integer()
  def plan_emit_owned_slot_count(%FunctionPlan{} = plan) do
    plan
    |> prepare_owned_slots_map()
    |> owned_slot_count()
  end

  defp prepare_owned_slots_map(%FunctionPlan{} = plan, opts \\ []) do
    param_kinds = param_kinds_for_plan(plan)
    decl_map = Process.get(:elmc_program_decls, %{})
    {slots, _} = Plan.allocate_slots(plan)

    closure_mode = Keyword.get(opts, :closure_mode)

    {_native_int_regs, slots} =
      allocate_native_int_param_slots(plan, slots, param_kinds, decl_map, closure_mode)

    {_borrow_param_regs, slots} =
      allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, closure_mode)

    slots = Map.drop(slots, MapSet.to_list(build_tail_inline_skip_regs(plan)))

    native_int_only_regs = build_native_int_only_regs(plan, decl_map)
    native_bool_only_regs = build_native_bool_only_regs(plan, decl_map)

    finalize_owned_slots_map(plan, slots, native_int_only_regs, native_bool_only_regs)
  end

  defp emit_return(%FunctionPlan{native_scalar_value_return: true, blocks: blocks} = plan, slots, kind, _borrow_nulls, instr_opts)
       when kind in [:native_int, :native_bool] do
    reg = native_ret_reg(plan, blocks)

    case reg do
      r when is_integer(r) ->
        case kind do
          :native_int -> "return #{native_int_result_ref(r, slots, instr_opts)};"
          :native_bool -> "return #{native_bool_result_ref(r, instr_opts)};"
        end

      _ ->
        case kind do
          :native_int -> "return 0;"
          :native_bool -> "return false;"
        end
    end
  end

  defp emit_return(%FunctionPlan{rc_required: false, blocks: blocks} = plan, slots, :native_int, _borrow_nulls, instr_opts) do
    reg = native_ret_reg(plan, blocks)
    slot_count = owned_slot_count(slots)

    src =
      case reg do
        r when is_integer(r) -> native_int_result_ref(r, slots, instr_opts)
        _ -> "0"
      end

    if slot_count > 0 do
      """
      {
        ElmcValue *__ret = elmc_new_int_take(#{src});
        elmc_release_array_lifo(owned, #{slot_count});
        return __ret;
      }
      """
      |> String.trim()
    else
      "return elmc_new_int_take(#{src});"
    end
  end

  defp emit_return(%FunctionPlan{rc_required: false, blocks: blocks} = plan, slots, :native_bool, _borrow_nulls, instr_opts) do
    reg = native_ret_reg(plan, blocks)
    slot_count = owned_slot_count(slots)

    src =
      case reg do
        r when is_integer(r) -> native_bool_result_ref(r, instr_opts)
        _ -> "false"
      end

    if slot_count > 0 do
      """
      {
        ElmcValue *__ret = elmc_new_bool_take(#{src});
        elmc_release_array_lifo(owned, #{slot_count});
        return __ret;
      }
      """
      |> String.trim()
    else
      "return elmc_new_bool_take(#{src});"
    end
  end

  defp emit_return(%FunctionPlan{blocks: blocks} = plan, slots, :native_int, _borrow_nulls, instr_opts) do
    reg = native_ret_reg(plan, blocks)

    case reg do
      r when is_integer(r) ->
        "*out = #{native_int_result_ref(r, slots, instr_opts)};"

      _ ->
        "*out = 0;"
    end
  end

  defp emit_return(%FunctionPlan{blocks: blocks} = plan, _slots, :native_bool, _borrow_nulls, instr_opts) do
    reg = native_ret_reg(plan, blocks)

    case reg do
      r when is_integer(r) ->
        "*out = #{native_bool_result_ref(r, instr_opts)};"

      _ ->
        "*out = false;"
    end
  end

  defp emit_return(%FunctionPlan{rc_required: false, blocks: blocks}, slots, _, borrow_nulls, instr_opts) do
    slot_count = owned_slot_count(slots)
    borrow_cleanup = borrow_null_cleanup_lines(borrow_nulls)

    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        ""

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        native_int? =
          MapSet.member?(Keyword.get(instr_opts, :native_int_only_regs, MapSet.new()), reg)

        if native_int? do
          src = native_int_result_ref(reg, slots, instr_opts)

          if slot_count > 0 do
            """
            {
              ElmcValue *__ret = elmc_new_int_take(#{src});
              elmc_release_array_lifo(owned, #{slot_count});
              return __ret;
            }
            """
            |> String.trim()
          else
            "return elmc_new_int_take(#{src});"
          end
        else
          ref = slot_ref(reg, slots, instr_opts)
          idx = Map.get(slots, reg, 0)

          if slot_count > 0 do
            borrow_cleanup =
              borrow_nulls
              |> Enum.reject(&(&1 == "owned[#{idx}] = NULL;"))
              |> borrow_null_cleanup_lines()

            """
            {
              ElmcValue *__ret = #{ref};
              owned[#{idx}] = NULL;
              #{borrow_cleanup}
              elmc_release_array_lifo(owned, #{slot_count});
              return __ret;
            }
            """
            |> String.trim()
          else
            "return #{ref};"
          end
        end

      _ ->
        if slot_count > 0 do
          """
          #{borrow_cleanup}
          elmc_release_array_lifo(owned, #{slot_count});
          return elmc_int_zero();
          """
          |> String.trim()
        else
          "return elmc_int_zero();"
        end
    end
  end

  defp emit_return(%FunctionPlan{blocks: blocks}, slots, _, _borrow_nulls, instr_opts) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        ""

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        case Map.get(slots, reg) do
          i when is_integer(i) ->
            "*out = #{slot_ref(reg, slots, instr_opts)};\nowned[#{i}] = NULL;"

          nil ->
            "*out = #{slot_ref(reg, slots, instr_opts)};"
        end

      _ ->
        "*out = elmc_int_zero();"
    end
  end

  defp native_ret_reg(_plan, blocks) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        blocks
        |> Enum.flat_map(& &1.instrs)
        |> Enum.find_value(fn
          %{op: :publish, dest: :fn_out, args: %{source: reg}} when is_integer(reg) -> reg
          _ -> nil
        end)

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        reg

      _ ->
        nil
    end
  end

  defp slot_ref(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
      c_arg when is_binary(c_arg) ->
        c_arg

      _ ->
        case Map.get(slots, reg) do
          i when is_integer(i) -> "owned[#{i}]"
          _ -> "tmp_#{reg}"
        end
    end
  end

  defp owned_slot_count(slots) do
    case Map.values(slots) do
      [] -> 0
      values -> Enum.max(values) + 1
    end
  end

  defp finalize_owned_slots_map(%FunctionPlan{} = plan, slots, native_int_only_regs, native_bool_only_regs, fusion_native_literal_regs \\ MapSet.new()) do
    slots
    |> then(&drop_undef_slot_regs(plan, &1))
    |> Map.drop(MapSet.to_list(native_int_only_regs))
    |> Map.drop(MapSet.to_list(native_bool_only_regs))
    |> Map.drop(MapSet.to_list(fusion_native_literal_regs))
    |> compact_slots()
  end

  defp build_fusion_native_literal_regs(%FunctionPlan{} = plan) do
    plan
    |> build_const_int_regs()
    |> Map.keys()
    |> Enum.filter(&fusion_native_literal_reg?(plan, &1))
    |> MapSet.new()
  end

  defp fusion_native_literal_reg?(plan, reg) do
    decl_map = Process.get(:elmc_program_decls, %{})

    consumers =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.reject(&(&1.op == :const_int and &1.dest == reg))
      |> Enum.filter(fn instr ->
        instr
        |> instr_reg_refs(decl_map)
        |> Enum.any?(fn {_kind, r} -> r == reg end)
      end)

    consumers != [] and Enum.all?(consumers, &fusion_native_literal_consumer?(&1, reg))
  end

  defp fusion_native_literal_consumer?(%{op: :call_fn, args: %{module: mod, name: name, args: args}}, reg) do
    case Fusion.rc_native_fusion_arg_kinds({mod, name}) do
      kinds when is_list(kinds) ->
        Enum.zip(args, kinds) |> Enum.any?(fn {r, k} -> r == reg and k in [:native_int, :boxed_int_tag] end)

      _ ->
        false
    end
  end

  defp fusion_native_literal_consumer?(_, _), do: false

  defp drop_undef_slot_regs(%FunctionPlan{} = plan, slots) do
    defined = MapSet.new(all_def_regs(plan))

    Map.filter(slots, fn {reg, _} ->
      MapSet.member?(defined, reg)
    end)
  end

  defp lookup_decl(module, name) do
    Process.get(:elmc_program_decls, %{})
    |> Map.get({module, name})
  end

  defp param_names(params) when is_list(params) do
    Enum.map(params, fn
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> "_"
    end)
  end

  defp param_kinds_for_plan(%FunctionPlan{} = plan) do
    decl = lookup_decl(plan.module, plan.name)
    decl_map = Process.get(:elmc_program_decls, %{})

    cond do
      decl && FunctionEmit.mixed_direct_abi?(decl, plan.module, decl_map) ->
        NativeFunctionCall.arg_kinds(decl, plan.module, decl_map)

      decl && NativeFunctionCall.signature_has_native_args?(decl) ->
        NativeFunctionCall.signature_arg_kinds(decl, plan.module, decl_map)

      true ->
        List.duplicate(:boxed, length(plan.params))
    end
  end

  defp allocate_native_int_param_slots(plan, slots, param_kinds, decl_map, closure_mode) do
    all_native_int_regs =
      build_native_int_param_regs(plan, param_kinds, decl_map, closure_mode)

    boxed_uses = boxed_use_regs(plan, decl_map)

    pure_native_param_regs =
      Map.keys(all_native_int_regs)
      |> Enum.reject(&MapSet.member?(boxed_uses, &1))

    slots = Map.drop(slots, pure_native_param_regs)
    {all_native_int_regs, slots}
  end

  defp build_tail_inline_skip_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(&tail_inline_skip_operand_regs(plan, &1))
    |> MapSet.new()
  end

  defp build_overwritten_inline_skip_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(fn block ->
      Optimize.unread_overwritten_dest_regs(block.instrs, block.terminator)
      |> MapSet.to_list()
    end)
    |> MapSet.new()
  end

  defp build_record_param_inline_skip_regs(%FunctionPlan{params: params} = plan, param_kinds) do
    record_consumes = record_consume_regs(plan)
    param_names = param_names(params)

    record_consumes
    |> MapSet.to_list()
    |> Enum.filter(fn reg ->
      boxed_param_new_int_root(plan, reg, param_kinds, param_names) != nil and
        reg_operand_uses_subset?(plan, reg, record_consumes)
    end)
    |> MapSet.new()
  end

  defp build_unused_native_int_skip_regs(%FunctionPlan{} = plan, native_int_only_regs) do
    native_int_only_regs
    |> MapSet.to_list()
    |> Enum.filter(&unused_native_int_copy_reg?(plan, &1))
    |> MapSet.new()
  end

  defp unused_native_int_copy_reg?(plan, reg) do
    not direct_native_publish?(plan, reg) and
      not native_int_phi_operand?(plan, reg) and
      dead_native_int_copy_def?(plan, reg) and
      native_int_boxed_copy_only?(plan, reg)
  end

  defp dead_native_int_copy_def?(plan, reg) do
    case plan_defining_instr(plan, reg) do
      %{op: :call_runtime, args: %{builtin: :retain}} ->
        true

      %{op: :load_local} ->
        true

      %{op: :int_arith, args: args} ->
        native_int_identity_source(args) != nil

      _ ->
        false
    end
  end

  defp native_int_identity_source(%{kind: :add_const, lhs: lhs, value: 0}), do: lhs
  defp native_int_identity_source(%{kind: :sub_const, lhs: lhs, value: 0}), do: lhs
  defp native_int_identity_source(_), do: nil

  defp native_int_boxed_copy_only?(plan, reg) do
    sites = native_int_reg_use_sites(plan, reg)
    sites != [] and Enum.all?(sites, &boxed_record_tuple_builtin_instr?/1)
  end

  defp native_int_reg_use_sites(plan, reg) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(fn instr ->
      instr
      |> plan_value_operand_regs()
      |> Enum.member?(reg)
    end)
  end

  defp boxed_record_tuple_builtin_instr?(%{op: :call_runtime, args: %{builtin: builtin}})
       when builtin in [:record_new, :record_new_take, :tuple2, :tuple2_take],
       do: true

  defp boxed_record_tuple_builtin_instr?(_), do: false

  defp plan_value_operand_regs(%{op: :phi, args: args}) do
    [Map.get(args, :cond), Map.get(args, :then), Map.get(args, :else)]
    |> Enum.filter(&is_integer/1)
  end

  defp plan_value_operand_regs(%{op: :publish, args: %{source: source}}) when is_integer(source),
    do: [source]

  defp plan_value_operand_regs(%{op: :int_arith, args: args}) do
    [:lhs, :rhs, :base, :value]
    |> Enum.map(&Map.get(args, &1))
    |> Enum.filter(&is_integer/1)
  end

  defp plan_value_operand_regs(%{op: :compare, args: %{left: left, right: right}}) do
    Enum.filter([left, right], &is_integer/1)
  end

  defp plan_value_operand_regs(%{op: :call_runtime, args: %{builtin: :retain, args: [src]}})
       when is_integer(src),
       do: [src]

  defp plan_value_operand_regs(%{op: :load_local, args: %{source: source}}) when is_integer(source),
    do: [source]

  defp plan_value_operand_regs(%{op: :call_runtime, args: %{args: args}}) when is_list(args), do: args

  defp plan_value_operand_regs(%{op: :call_fn, args: %{args: args}}) when is_list(args), do: args

  defp plan_value_operand_regs(%{op: :record_get_int, args: %{base: base}}) when is_integer(base),
    do: [base]

  defp plan_value_operand_regs(%{args: %{lhs: lhs, rhs: rhs}}) when is_integer(lhs) or is_integer(rhs) do
    Enum.filter([lhs, rhs], &is_integer/1)
  end

  defp plan_value_operand_regs(%{args: %{base: base}}) when is_integer(base), do: [base]
  defp plan_value_operand_regs(%{args: %{source: source}}) when is_integer(source), do: [source]
  defp plan_value_operand_regs(%{args: %{subject: subject}}) when is_integer(subject), do: [subject]
  defp plan_value_operand_regs(%{args: %{reg: reg}}) when is_integer(reg), do: [reg]
  defp plan_value_operand_regs(%{args: %{params: params}}) when is_list(params), do: params
  defp plan_value_operand_regs(_), do: []

  defp native_int_phi_operand?(plan, reg) do
    Enum.any?(plan.blocks, fn %{instrs: instrs} ->
      Enum.any?(instrs, fn
        %{op: :phi, args: %{then: ^reg}} -> true
        %{op: :phi, args: %{else: ^reg}} -> true
        _ -> false
      end)
    end)
  end

  defp build_unused_boxed_param_skip_regs(%FunctionPlan{params: params} = plan, param_kinds) do
    param_names = param_names(params)

    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.map(&Map.get(&1, :dest))
    |> Enum.filter(&is_integer/1)
    |> Enum.filter(fn reg ->
      boxed_param_new_int_root(plan, reg, param_kinds, param_names) != nil and
        plan_operand_use_regs(plan, reg) == []
    end)
    |> MapSet.new()
  end

  defp record_consume_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :call_runtime, args: %{builtin: builtin, args: args}}
      when builtin in [:record_new, :record_new_take, :record_new_values_ints] and is_list(args) ->
        args

      _ ->
        []
    end)
    |> MapSet.new()
  end

  defp boxed_param_new_int_root(plan, reg, param_kinds, param_names) when is_integer(reg) do
    case plan_defining_instr(plan, reg) do
      %{op: :load_param, args: %{index: index}} ->
        if Enum.at(param_kinds, index) == :native_int, do: {:param, index}, else: nil

      %{op: :call_runtime, args: %{builtin: :new_int, args: [src]}} when is_integer(src) ->
        if native_param_reg?(plan, src, param_kinds), do: src, else: nil

      %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
        native_param_c_expr?(expr, param_kinds, param_names)

      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        boxed_param_new_int_root(plan, src, param_kinds, param_names)

      _ ->
        nil
    end
  end

  defp boxed_param_new_int_root(_, _, _, _), do: nil

  defp native_param_c_expr?(expr, param_kinds, param_names) do
    param_kinds
    |> Enum.with_index()
    |> Enum.any?(fn
      {:native_int, index} ->
        FunctionCallAbi.param_c_arg(index, param_names) == expr

      _ ->
        false
    end)
  end

  defp native_param_reg?(plan, reg, param_kinds) do
    case plan_defining_instr(plan, reg) do
      %{op: :load_param, args: %{index: index}} ->
        Enum.at(param_kinds, index) == :native_int

      _ ->
        false
    end
  end

  defp reg_operand_uses_subset?(plan, reg, allowed) do
    uses = plan_operand_use_regs(plan, reg)

    uses != [] and Enum.all?(uses, &MapSet.member?(allowed, &1))
  end

  defp plan_operand_use_regs(%FunctionPlan{blocks: blocks}, reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn instr ->
      instr
      |> plan_instr_operand_regs()
      |> Enum.filter(&(&1 == reg))
    end)
    |> Enum.uniq()
  end

  defp plan_instr_operand_regs(%{effects: %{borrows: borrows, consumes: consumes}}) do
    (borrows || []) ++ (consumes || [])
  end

  defp plan_instr_operand_regs(%{args: %{args: args}}) when is_list(args), do: args
  defp plan_instr_operand_regs(%{args: %{lhs: lhs, rhs: rhs}}), do: [lhs, rhs]
  defp plan_instr_operand_regs(%{args: %{base: base}}) when is_integer(base), do: [base]
  defp plan_instr_operand_regs(%{args: %{source: source}}) when is_integer(source), do: [source]
  defp plan_instr_operand_regs(%{args: %{subject: subject}}) when is_integer(subject), do: [subject]
  defp plan_instr_operand_regs(%{args: %{regs: regs}}) when is_list(regs), do: regs
  defp plan_instr_operand_regs(%{args: %{params: params}}) when is_list(params), do: params
  defp plan_instr_operand_regs(_), do: []

  defp tail_inline_skip_operand_regs(plan, %{
         op: :call_runtime,
         dest: dest,
         args: %{builtin: builtin, args: args}
       })
       when builtin in [:tuple2, :tuple2_take] and dest in [:fn_out, :branch_out] do
    Enum.filter(args, &tail_inline_operand?(plan, &1))
  end

  defp tail_inline_skip_operand_regs(_plan, _instr), do: []

  defp tail_inline_operand?(plan, reg) when is_integer(reg) do
    case plan_defining_instr(plan, reg) do
      %{op: :const_int} ->
        true

      %{op: :call_runtime, args: %{builtin: builtin}}
      when builtin in [:tuple2_ints, :new_int] ->
        true

      _ ->
        false
    end
  end

  defp plan_defining_instr(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp plan_defining_instr(_, _), do: nil

  defp allocate_borrow_param_direct_slots(plan, slots, param_kinds, _decl_map, %{capture_count: cap_n})
       when is_integer(cap_n) do
    borrow_regs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))
      |> Enum.map(fn %{dest: reg, args: %{index: index}} -> {reg, index} end)
      |> Enum.uniq_by(fn {reg, _} -> reg end)
      |> Enum.filter(fn {_reg, index} ->
        index >= cap_n and Enum.at(param_kinds, index, :boxed) == :boxed
      end)
      |> Map.new(fn {reg, index} ->
        arg_i = index - cap_n
        {reg, "(argc > #{arg_i} ? args[#{arg_i}] : NULL)"}
      end)

    {borrow_regs, slots}
  end

  defp allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, closure_mode) do
    if match?(%{capture_count: _}, closure_mode) do
      {%{}, slots}
    else
      allocate_borrow_param_direct_slots_impl(plan, slots, param_kinds, decl_map)
    end
  end

  defp build_closure_borrow_regs(plan, %{capture_count: cap_n}) when is_integer(cap_n) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(fn
      %{op: :load_param, args: %{index: idx}} when idx >= cap_n -> true
      _ -> false
    end)
    |> Enum.map(fn %{dest: reg} -> reg end)
    |> MapSet.new()
  end

  defp build_closure_borrow_regs(_plan, _closure_mode), do: MapSet.new()

  defp allocate_borrow_param_direct_slots_impl(plan, slots, param_kinds, decl_map) do
    decl = lookup_decl(plan.module, plan.name)

    if borrow_param_direct_enabled?(decl || %{}) do
      borrow_regs = build_borrow_param_regs(plan, param_kinds, decl_map, nil)
      needs_owned = param_regs_needing_owned_copy(plan, Map.keys(borrow_regs))
      direct_regs = Map.drop(borrow_regs, MapSet.to_list(needs_owned))
      slots = Map.drop(slots, Map.keys(direct_regs))
      {direct_regs, slots}
    else
      {%{}, slots}
    end
  end

  defp borrow_param_direct_enabled?(decl) do
    ownership = List.wrap(Map.get(decl, :ownership, []))
    :retain_arg not in ownership and (:borrow_arg in ownership or ownership == [])
  end

  # Borrowed boxed params can use the C argument directly when the plan never
  # reassigns that param register (for example thin delegates, or read-only borrows).
  # When the register is reused after `case`/`::` destructuring, load_param keeps
  # an owned scratch slot so the same reg can hold derived values later.
  defp param_regs_needing_owned_copy(plan, param_regs) when is_list(param_regs) do
    param_set = MapSet.new(param_regs)

    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :load_param} ->
        []

      %{dest: dest} when is_integer(dest) ->
        if MapSet.member?(param_set, dest), do: [dest], else: []

      _ ->
        []
    end)
    |> MapSet.new()
  end

  defp build_borrow_param_regs(plan, param_kinds, decl_map, closure_mode) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&(&1.op == :load_param))
    |> Enum.map(fn %{dest: reg, args: %{index: index}} -> {reg, index} end)
    |> Enum.uniq_by(fn {reg, _} -> reg end)
    |> Enum.filter(fn {_reg, index} -> Enum.at(param_kinds, index) == :boxed end)
    |> Map.new(fn {reg, index} ->
      {reg, plan_borrow_param_c_ref(plan, index, decl_map, closure_mode)}
    end)
  end

  defp build_native_int_param_regs(plan, param_kinds, decl_map, closure_mode) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&(&1.op == :load_param))
    |> Enum.map(fn %{dest: reg, args: %{index: index}} -> {reg, index} end)
    |> Enum.uniq_by(fn {reg, _} -> reg end)
    |> Enum.filter(fn {_reg, index} -> Enum.at(param_kinds, index) == :native_int end)
    |> Map.new(fn {reg, index} ->
      {reg, plan_native_int_param_c_ref(plan, index, decl_map, closure_mode)}
    end)
  end

  defp plan_borrow_param_c_ref(plan, index, decl_map, closure_mode) do
    case closure_mode do
      %{capture_count: cap} when is_integer(cap) ->
        closure_param_c_ref(index, cap)

      _ ->
        plan_decl_param_c_arg(plan, index, decl_map)
    end
  end

  defp plan_native_int_param_c_ref(plan, index, decl_map, closure_mode) do
    case closure_mode do
      %{capture_count: cap} when is_integer(cap) ->
        closure_native_int_param_ref(index, cap)

      _ ->
        plan_decl_param_c_arg(plan, index, decl_map)
    end
  end

  defp plan_decl_param_c_arg(plan, index, _decl_map) do
    case lookup_decl(plan.module, plan.name) do
      %{args: args} when is_list(args) ->
        FunctionCallAbi.param_c_arg(index, decl_arg_names(args))

      _ ->
        FunctionCallAbi.param_c_arg(index, param_names(plan.params))
    end
  end

  defp closure_param_c_ref(index, capture_count) when index < capture_count do
    "captures[#{index}]"
  end

  defp closure_param_c_ref(index, capture_count) do
    arg_i = index - capture_count
    "(argc > #{arg_i} ? args[#{arg_i}] : NULL)"
  end

  defp closure_native_int_param_ref(index, capture_count) when index < capture_count do
    "elmc_as_int(captures[#{index}])"
  end

  defp closure_native_int_param_ref(index, capture_count) do
    arg_i = index - capture_count
    "elmc_as_int((argc > #{arg_i} ? args[#{arg_i}] : NULL))"
  end

  defp decl_arg_names(args) do
    Enum.map(args, fn
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> "_"
    end)
  end

  defp build_const_int_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :const_int, dest: reg, args: %{value: value} = args} ->
        [{reg, {value, Map.get(args, :union_ctor)}}]

      %{op: :call_runtime, dest: reg, args: %{builtin: :new_int, literal: value}}
      when is_integer(value) ->
        [{reg, {value, nil}}]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp build_const_c_expr_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&(&1.op == :const_c_expr))
    |> Map.new(fn %{dest: reg, args: %{value: value}} -> {reg, value} end)
  end

  defp build_native_int_only_regs(%FunctionPlan{} = plan, decl_map) do
    expand_native_int_regs(plan, decl_map, MapSet.new(), 0)
  end

  defp expand_native_int_regs(_plan, _decl_map, regs, n) when n >= 32, do: regs

  defp expand_native_int_regs(%FunctionPlan{} = plan, decl_map, prev, n) do
    next =
      plan
      |> all_def_regs()
      |> Enum.filter(&native_int_candidate?(plan, &1, decl_map, prev))
      |> MapSet.new()

    if MapSet.equal?(next, prev) do
      next
    else
      expand_native_int_regs(plan, decl_map, next, n + 1)
    end
  end

  defp native_int_mutable_regs(%FunctionPlan{} = plan, native_int_only_regs) do
    native_int_only_regs
    |> Enum.filter(fn reg ->
      defs = all_defining_instrs(plan, reg)

      length(defs) > 1 or
        Enum.any?(defs, fn
          %{op: :phi} ->
            true

          %{op: :call_runtime, args: %{builtin: :retain}} ->
            true

          %{op: :call_fn, args: %{module: mod, name: name}} ->
            NativeReturn.cached_kind({mod, name}) == :native_int

          _ ->
            false
        end)
    end)
    |> MapSet.new()
  end

  defp native_int_decl_lines(native_int_locals, native_int_mutable_regs) do
    native_int_mutable_regs
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.filter(&Map.has_key?(native_int_locals, &1))
    |> Enum.map(fn reg ->
      name = Map.fetch!(native_int_locals, reg)
      "elmc_int_t #{name};"
    end)
  end

  defp native_int_candidate?(plan, reg, decl_map, native_set) do
    case all_defining_instrs(plan, reg) do
      [] ->
        false

      [%{op: op} | _] when op in [:const_int, :const_c_expr, :record_get_int, :int_arith, :boxed_tag_peel] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_runtime, args: %{builtin: :int_list_head_int}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_fn, args: %{module: mod, name: name}} | _] ->
        NativeReturn.cached_kind({mod, name}) == :native_int and
          native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :phi, args: %{native_int_phi: true}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :phi, args: %{then: then_r, else: else_r}}] ->
        native_source?(plan, then_r, native_set) and native_source?(plan, else_r, native_set) and
          native_int_uses_only?(plan, reg, decl_map, native_set)

      retains when is_list(retains) ->
        retain_defs?(retains) and
          Enum.all?(retains, fn %{args: %{args: [src]}} ->
            native_source?(plan, src, native_set)
          end) and native_int_uses_only?(plan, reg, decl_map, native_set)

      _ ->
        false
    end
  end

  defp retain_defs?(instrs),
    do:
      instrs != [] and
        Enum.all?(instrs, &match?(%{op: :call_runtime, args: %{builtin: :retain, args: [_]}}, &1))

  defp native_source?(plan, reg, native_set) when is_integer(reg) do
    MapSet.member?(native_set, reg) or
      case defining_instr(plan, reg) do
        %{op: op} when op in [:const_int, :const_c_expr, :record_get_int, :int_arith, :boxed_tag_peel] ->
          true

        %{op: :call_runtime, args: %{builtin: :int_list_head_int}} ->
          true

        %{op: :phi, args: %{native_int_phi: true}} ->
          true

        %{op: :call_fn, args: %{module: mod, name: name}} ->
          NativeReturn.cached_kind({mod, name}) == :native_int

        _ ->
          false
      end
  end

  @doc false
  @spec all_defining_instrs(FunctionPlan.t(), non_neg_integer()) :: [map()]
  def all_defining_instrs(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(fn
      %{dest: ^reg} -> true
      _ -> false
    end)
  end

  defp all_def_regs(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{dest: reg} when is_integer(reg) -> [reg]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp native_int_uses_only?(plan, reg, decl_map, native_set) do
    use_kinds =
      plan_use_refs(plan, reg, decl_map, native_set)
      |> Enum.map(fn {kind, _} -> kind end)
      |> Enum.uniq()

    allowed = [:native_int_call, :native_operand]

    allowed =
      if Map.get(plan, :native_scalar_return) in [:native_int, :native_bool] do
        allowed ++ [:publish_fn_out]
      else
        allowed
      end

    use_kinds == [] or Enum.all?(use_kinds, &(&1 in allowed))
  end

  defp native_bool_mutable_regs(%FunctionPlan{} = plan, native_bool_only_regs) do
    native_bool_only_regs
    |> Enum.filter(fn reg ->
      defs = all_defining_instrs(plan, reg)

      length(defs) > 1 or
        Enum.any?(defs, fn
          %{op: :call_fn, args: %{module: mod, name: name}} ->
            NativeReturn.cached_kind({mod, name}) == :native_bool

          _ ->
            false
        end)
    end)
    |> MapSet.new()
  end

  defp native_bool_mutable_decl_lines(native_bool_locals, native_bool_mutable_regs) do
    native_bool_mutable_regs
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(fn reg ->
      name = Map.fetch!(native_bool_locals, reg)
      "bool #{name};"
    end)
  end

  defp build_native_bool_only_regs(%FunctionPlan{} = plan, decl_map) do
    expand_native_bool_regs(plan, decl_map, MapSet.new(), 0)
  end

  defp expand_native_bool_regs(_plan, _decl_map, regs, n) when n >= 32, do: regs

  defp expand_native_bool_regs(%FunctionPlan{} = plan, decl_map, prev, n) do
    next =
      plan
      |> all_def_regs()
      |> Enum.filter(&native_bool_candidate?(plan, &1, decl_map, prev))
      |> MapSet.new()

    if MapSet.equal?(next, prev) do
      next
    else
      expand_native_bool_regs(plan, decl_map, next, n + 1)
    end
  end

  defp native_bool_candidate?(plan, reg, decl_map, native_bool_set) do
    case all_defining_instrs(plan, reg) do
      [%{op: op} | _]
      when op in [:compare, :bool_and, :test_maybe_nothing, :test_list_empty, :test_ctor_tag, :test_bool] ->
        native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      [%{op: :phi, args: %{then: then_r, else: else_r}}] ->
        phi_truthy_native?(plan, then_r, else_r) and
          native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      _ ->
        false
    end
  end

  defp phi_truthy_native?(plan, then_r, else_r) do
    Elmc.Backend.Plan.TruthyNative.truthy_native_arm?(plan, then_r) and
      Elmc.Backend.Plan.TruthyNative.truthy_native_arm?(plan, else_r)
  end

  defp native_bool_uses_only?(plan, reg, decl_map, native_bool_set) do
    use_kinds =
      plan_bool_use_refs(plan, reg, decl_map, native_bool_set)
      |> Enum.map(fn {kind, _} -> kind end)
      |> Enum.uniq()

    use_kinds == [] or Enum.all?(use_kinds, &(&1 == :native_bool_operand))
  end

  defp plan_bool_use_refs(%FunctionPlan{blocks: blocks}, reg, decl_map, native_bool_set) do
    Enum.flat_map(blocks, fn %{instrs: instrs, terminator: term} ->
      instr_refs =
        instrs
        |> Enum.reject(fn instr -> instr.op in [:release, :catch_begin, :catch_end] end)
        |> Enum.reject(fn instr -> defining_reg?(instr, reg) end)
        |> Enum.flat_map(&instr_bool_use_refs(&1, reg, decl_map, native_bool_set))

      term_refs =
        case term do
          {:br_if, _, _, cond} when cond == reg -> [{:native_bool_operand, reg}]
          _ -> []
        end

      Enum.filter(instr_refs ++ term_refs, fn {_, ref} -> ref == reg end)
    end)
  end

  defp instr_bool_use_refs(%{op: :phi, args: %{cond: cond, then: then_r, else: else_r}}, reg, _, _) do
    []
    |> then(fn refs -> if cond == reg, do: [{:native_bool_operand, reg} | refs], else: refs end)
    |> then(fn refs -> if then_r == reg, do: [{:boxed, reg} | refs], else: refs end)
    |> then(fn refs -> if else_r == reg, do: [{:boxed, reg} | refs], else: refs end)
  end

  defp instr_bool_use_refs(%{op: :bool_and, args: %{left: left, right: right}}, reg, _, _) do
    Enum.flat_map([left, right], fn
      ^reg -> [{:native_bool_operand, reg}]
      _ -> []
    end)
  end

  defp instr_bool_use_refs(instr, reg, decl_map, _native_bool_set) do
    instr_reg_refs(instr, decl_map)
    |> Enum.filter(fn {_, ref} -> ref == reg end)
    |> Enum.map(fn
      {:native_operand, ref} -> {:native_bool_operand, ref}
      {_, ref} -> {:boxed, ref}
    end)
  end

  @doc false
  @spec plan_use_refs(FunctionPlan.t(), non_neg_integer(), map(), MapSet.t()) :: [
          {:native_int_call | :native_operand | :boxed | :publish_fn_out, non_neg_integer()}
        ]
  def plan_use_refs(%FunctionPlan{} = plan, reg, decl_map, native_set) do
    Enum.flat_map(plan.blocks, fn %{instrs: instrs, terminator: term} ->
      instr_refs =
        instrs
        |> Enum.reject(fn instr -> instr.op in [:release, :catch_begin, :catch_end] end)
        |> Enum.reject(fn instr -> defining_reg?(instr, reg) end)
        |> Enum.flat_map(&instr_use_refs(&1, decl_map, native_set, plan))

      term_refs =
        case term do
          {:br_if, _, _, cond} when cond == reg ->
            [{:native_operand, reg}]

          {:switch_tag, subject, _, _} when subject == reg ->
            [{:native_operand, reg}]

          _ ->
            []
        end

      Enum.filter(instr_refs ++ term_refs, fn {_, ref} -> ref == reg end)
    end)
  end

  defp instr_use_refs(%{op: :phi, dest: dest, args: args = %{then: then_r, else: else_r}}, decl_map, native_set, plan) do
    [
      phi_operand_use_kind(plan, dest, args, then_r, native_set, decl_map),
      phi_operand_use_kind(plan, dest, args, else_r, native_set, decl_map)
    ]
  end

  defp instr_use_refs(
         %{op: :call_runtime, dest: dest, args: %{builtin: :retain, args: [src]}},
         _decl_map,
         native_set,
         _plan
       )
       when is_integer(dest) and is_integer(src) do
    kind = if MapSet.member?(native_set, dest), do: :native_operand, else: :boxed
    [{kind, src}]
  end

  defp instr_use_refs(
         %{op: :call_runtime, args: %{builtin: :tuple2, args: args}},
         decl_map,
         native_set,
         plan
       )
       when is_list(args) do
    Enum.map(args, fn arg_reg ->
      kind =
        if is_integer(arg_reg) and native_int_value_reg?(plan, arg_reg, native_set, decl_map) do
          :native_operand
        else
          :boxed
        end

      {kind, arg_reg}
    end)
  end

  defp instr_use_refs(instr, decl_map, _native_set, _plan), do: instr_reg_refs(instr, decl_map)

  defp phi_operand_use_kind(plan, phi_dest, phi_args, reg, native_set, decl_map) when is_integer(reg) do
    if native_phi_operand_context?(plan, phi_dest, phi_args, native_set) and
         native_int_value_reg?(plan, reg, native_set, decl_map) do
      {:native_operand, reg}
    else
      {:boxed, reg}
    end
  end

  defp native_phi_operand_context?(plan, phi_dest, phi_args, native_set) when is_integer(phi_dest) do
    Map.get(phi_args, :native_int_phi) == true or
      MapSet.member?(native_set, phi_dest) or
      native_phi_dest_publishes_scalar?(plan, phi_dest)
  end

  defp native_phi_operand_context?(_, _, _, _), do: false

  defp native_phi_dest_publishes_scalar?(plan, reg) when is_integer(reg) do
    case Map.get(plan, :native_scalar_return) do
      :native_int -> reg_reaches_native_scalar_publish?(plan, reg, MapSet.new())
      _ -> false
    end
  end

  defp reg_reaches_native_scalar_publish?(plan, reg, visited) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      false
    else
      visited = MapSet.put(visited, reg)

      direct_native_publish?(plan, reg) or
        Enum.any?(phi_successors(plan, reg), &reg_reaches_native_scalar_publish?(plan, &1, visited))
    end
  end

  defp direct_native_publish?(plan, reg) when is_integer(reg) do
    Enum.any?(plan.blocks, fn %{instrs: instrs} ->
      Enum.any?(instrs, fn
        %{op: :publish, dest: :fn_out, args: %{source: ^reg}} -> true
        _ -> false
      end)
    end)
  end

  defp phi_successors(plan, reg) when is_integer(reg) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :phi, dest: dest, args: %{then: ^reg}} -> [dest]
      %{op: :phi, dest: dest, args: %{else: ^reg}} -> [dest]
      _ -> []
    end)
  end

  defp native_int_value_reg?(plan, reg, native_set, decl_map) when is_integer(reg) do
    native_int_value_reg?(plan, reg, native_set, decl_map, MapSet.new())
  end

  defp native_int_value_reg?(plan, reg, native_set, decl_map, visited) when is_integer(reg) do
    if MapSet.member?(visited, reg) do
      false
    else
      visited = MapSet.put(visited, reg)

      MapSet.member?(native_set, reg) or
        case defining_instr(plan, reg) do
          %{op: :call_fn, args: %{module: mod, name: name}} ->
            NativeReturn.cached_kind({mod, name}) == :native_int

          %{op: op} when op in [:const_int, :const_c_expr, :record_get_int, :int_arith] ->
            true

          %{op: :call_runtime, args: %{builtin: :int_list_head_int}} ->
            true

          %{op: :phi, args: %{native_int_phi: true}} ->
            true

          %{op: :phi, args: %{then: then_r, else: else_r}} ->
            native_int_value_reg?(plan, then_r, native_set, decl_map, visited) and
              native_int_value_reg?(plan, else_r, native_set, decl_map, visited)

          _ ->
            false
        end
    end
  end

  defp defining_instr(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp defining_reg?(%{dest: dest}, reg) when is_integer(dest) and is_integer(reg),
    do: dest == reg

  defp defining_reg?(_, _), do: false

  defp instr_reg_refs(%{op: :call_fn, args: %{module: mod, name: name, args: args}}, decl_map)
       when is_list(args) do
    kinds = callee_arg_kinds(mod, name, decl_map)

    Enum.with_index(args)
    |> Enum.map(fn {reg, idx} ->
      kind = Enum.at(kinds, idx, :boxed)
      ref_kind = if kind == :native_int, do: :native_int_call, else: :boxed
      {ref_kind, reg}
    end)
  end

  defp instr_reg_refs(%{op: :call_runtime, args: %{builtin: :record_new_values_ints, args: args}}, _decl_map)
       when is_list(args) do
    Enum.map(args, &{:native_operand, &1})
  end

  defp instr_reg_refs(
         %{op: :call_runtime, args: %{builtin: id, args: args} = args_map},
         _decl_map
       )
       when id in [:record_new, :record_new_take] and is_list(args) do
    field_names = Map.get(args_map, :field_names, [])

    args
    |> Enum.with_index()
    |> Enum.map(fn {reg, idx} ->
      kind =
        case Enum.at(field_names, idx) do
          name when is_binary(name) ->
            if record_field_int?(name), do: :native_operand, else: :boxed

          _ ->
            :boxed
        end

      {kind, reg}
    end)
  end

  defp instr_reg_refs(%{op: :call_runtime, args: %{builtin: id, args: args}}, _decl_map)
       when is_list(args) do
    Enum.with_index(args)
    |> Enum.map(fn {reg, idx} ->
      kind = if RuntimeBuiltins.native_int_arg?(id, idx), do: :native_int_call, else: :boxed
      {kind, reg}
    end)
  end

  defp instr_reg_refs(%{op: :int_arith, args: args}, _decl_map) do
    []
    |> maybe_add_reg_ref(args, :lhs, :native_operand)
    |> maybe_add_reg_ref(args, :rhs, :native_operand)
  end

  defp instr_reg_refs(%{op: :compare, args: %{left: left, right: right}}, _decl_map),
    do: [{:native_operand, left}, {:native_operand, right}]

  defp instr_reg_refs(%{op: :phi, args: %{then: then_r, else: else_r}}, _decl_map),
    do: [{:boxed, then_r}, {:boxed, else_r}]

  defp instr_reg_refs(%{op: :load_local, args: %{source: source}}, _decl_map),
    do: [{:boxed, source}]

  defp instr_reg_refs(%{op: :publish, dest: :fn_out, args: %{source: source}}, _decl_map),
    do: [{:publish_fn_out, source}]

  defp instr_reg_refs(%{op: :publish, args: %{source: source}}, _decl_map),
    do: [{:boxed, source}]

  defp instr_reg_refs(%{op: :boxed_binop, args: %{lhs: lhs, rhs: rhs}}, _decl_map),
    do: [{:boxed, lhs}, {:boxed, rhs}]

  defp instr_reg_refs(%{op: :bool_and, args: %{left: left, right: right}}, _decl_map),
    do: [{:native_operand, left}, {:native_operand, right}]

  defp instr_reg_refs(%{op: :test_maybe_nothing, args: %{reg: reg}}, _decl_map),
    do: [{:native_operand, reg}]

  defp instr_reg_refs(%{op: :test_list_empty, args: %{reg: reg}}, _decl_map),
    do: [{:native_operand, reg}]

  defp instr_reg_refs(%{op: :boxed_tag_peel, args: %{subject: subject}}, _decl_map),
    do: [{:boxed, subject}]

  defp instr_reg_refs(%{op: :test_ctor_tag, args: %{subject: subject}}, _decl_map),
    do: [{:native_operand, subject}]

  defp instr_reg_refs(%{op: :test_bool, args: %{subject: subject}}, _decl_map),
    do: [{:native_operand, subject}]

  defp instr_reg_refs(%{op: :switch_ctor_tag, args: %{subject: subject}}, _decl_map),
    do: [{:boxed, subject}]

  defp instr_reg_refs(%{op: op, args: %{params: params}}, _decl_map)
       when op in [:pebble_sub, :pebble_cmd, :render_cmd] and is_list(params) do
    Enum.map(params, &{:native_int_call, &1})
  end

  defp instr_reg_refs(%{op: :record_get_int, args: %{base: base}}, _decl_map),
    do: [{:boxed, base}]

  defp instr_reg_refs(%{op: :record_get, args: %{base: base}}, _decl_map), do: [{:boxed, base}]

  defp instr_reg_refs(%{op: :record_update, args: args}, _decl_map),
    do: [{:boxed, Map.get(args, :base)}, {:boxed, Map.get(args, :value)}]

  defp instr_reg_refs(%{op: :tuple_proj, args: %{base: base}}, _decl_map), do: [{:boxed, base}]

  defp instr_reg_refs(%{op: :make_closure, args: %{captures: caps}}, _decl_map) when is_list(caps),
    do: Enum.map(caps, &{:boxed, &1})

  defp instr_reg_refs(%{op: :call_closure, args: args}, _decl_map) do
    callee = Map.get(args, :callee)
    call_args = Map.get(args, :args, [])
    [{:boxed, callee} | Enum.map(call_args, &{:boxed, &1})]
  end

  defp instr_reg_refs(%{op: :forward_ref_set, args: %{value: value}}, _decl_map),
    do: [{:boxed, value}]

  defp instr_reg_refs(%{op: :release, args: %{reg: reg}}, _decl_map), do: [{:boxed, reg}]

  defp instr_reg_refs(_, _decl_map), do: []

  defp maybe_add_reg_ref(refs, args, key, kind) do
    case Map.get(args, key) do
      reg when is_integer(reg) -> [{kind, reg} | refs]
      _ -> refs
    end
  end

  defp callee_arg_kinds(module, name, decl_map) do
    case Map.get(decl_map, {module, name}) do
      decl when is_map(decl) ->
        if FunctionCallAbi.direct_plan_call_abi?(decl, module, decl_map) and
             FunctionEmit.mixed_direct_abi?(decl, module, decl_map) do
          NativeFunctionCall.arg_kinds(decl, module, decl_map)
        else
          List.duplicate(:boxed, length(Map.get(decl, :args, [])))
        end

      _ ->
        []
    end
  end

  defp compact_slots(slots) when map_size(slots) == 0, do: slots

  defp compact_slots(slots) do
    remap =
      slots
      |> Map.values()
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.with_index()
      |> Map.new()

    Map.new(slots, fn {reg, index} -> {reg, Map.fetch!(remap, index)} end)
  end

  defp boxed_use_regs(%FunctionPlan{} = plan, decl_map) do
    plan.blocks
    |> Enum.flat_map(fn %Block{instrs: instrs} ->
      Enum.flat_map(instrs, &boxed_operand_regs(&1, decl_map))
    end)
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  defp boxed_operand_regs(%{op: :make_closure, args: %{captures: captures}}, _decl_map)
       when is_list(captures),
       do: captures

  defp boxed_operand_regs(%{op: :phi, args: %{then: then_r, else: else_r}}, _decl_map),
    do: [then_r, else_r]

  defp boxed_operand_regs(%{op: :load_local, args: %{source: source}}, _decl_map), do: [source]

  defp boxed_operand_regs(%{op: :call_runtime, args: %{builtin: :tuple2, args: args}}, _decl_map)
       when is_list(args),
       do: args

  defp boxed_operand_regs(%{op: :call_runtime, args: %{builtin: :tuple2_take, args: args}}, _decl_map)
       when is_list(args),
       do: args

  defp boxed_operand_regs(
         %{op: :call_runtime, args: %{builtin: id, args: args} = args_map},
         _decl_map
       )
       when id in [:record_new, :record_new_take] and is_list(args) do
    field_names = Map.get(args_map, :field_names, [])

    args
    |> Enum.with_index()
    |> Enum.flat_map(fn {reg, idx} ->
      case Enum.at(field_names, idx) do
        name when is_binary(name) ->
          if record_field_int?(name), do: [], else: [reg]

        _ ->
          [reg]
      end
    end)
  end

  defp boxed_operand_regs(%{op: :call_runtime, args: %{builtin: id, args: args}}, _decl_map)
       when is_list(args) do
    args
    |> Enum.with_index()
    |> Enum.reject(fn {_, index} -> RuntimeBuiltins.native_int_arg?(id, index) end)
    |> Enum.map(fn {reg, _} -> reg end)
  end

  defp boxed_operand_regs(%{op: :call_fn, args: %{module: mod, name: name, args: args}}, decl_map)
       when is_list(args) do
    decl = Map.get(decl_map, {mod, name})

    if decl && FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map) &&
         FunctionEmit.mixed_direct_abi?(decl, mod, decl_map) do
      kinds = NativeFunctionCall.arg_kinds(decl, mod, decl_map)

      args
      |> Enum.zip(kinds)
      |> Enum.reject(fn {_, kind} -> kind in [:native_int, :native_bool] end)
      |> Enum.map(fn {reg, _} -> reg end)
    else
      Enum.filter(args, &is_integer/1)
    end
  end

  defp boxed_operand_regs(%{op: :call_closure, args: args}, _decl_map) do
    callee = Map.get(args, :callee)
    call_args = Map.get(args, :args, [])
    [callee | call_args]
  end

  defp boxed_operand_regs(%{op: :record_get, args: %{base: base}}, _decl_map), do: [base]

  defp boxed_operand_regs(%{op: :record_update, args: args}, _decl_map) do
    [Map.get(args, :base), Map.get(args, :value)]
  end

  defp boxed_operand_regs(%{op: :boxed_binop, args: %{lhs: lhs, rhs: rhs}}, _decl_map),
    do: [lhs, rhs]

  defp boxed_operand_regs(%{op: :test_maybe_nothing, args: %{reg: reg}}, _decl_map), do: [reg]

  defp boxed_operand_regs(%{op: :test_list_empty, args: %{reg: reg}}, _decl_map), do: [reg]

  defp boxed_operand_regs(%{op: :test_ctor_tag, args: %{subject: subject}}, _decl_map),
    do: [subject]

  defp boxed_operand_regs(%{op: :test_bool, args: %{subject: subject}}, _decl_map),
    do: [subject]

  defp boxed_operand_regs(%{op: :bool_and, args: %{left: left, right: right}}, _decl_map),
    do: [left, right]

  defp boxed_operand_regs(%{op: :switch_ctor_tag, args: %{subject: subject}}, _decl_map),
    do: [subject]

  defp boxed_operand_regs(%{op: :tuple_proj, args: %{base: base}}, _decl_map), do: [base]

  defp boxed_operand_regs(%{op: :forward_ref_set, args: %{value: value}}, _decl_map), do: [value]

  defp boxed_operand_regs(%{op: :publish, args: %{source: source}}, _decl_map), do: [source]

  defp boxed_operand_regs(%{op: :release, args: %{reg: reg}}, _decl_map), do: [reg]

  defp boxed_operand_regs(%{op: op}, _decl_map)
       when op in [:int_arith, :compare, :load_param, :const_int, :const_static_list, :const_immortal_string],
       do: []

  defp boxed_operand_regs(_, _decl_map), do: []

  defp native_int_result_ref(reg, _slots, instr_opts) do
    case Map.get(Keyword.get(instr_opts, :native_int_inline, %{}), reg) do
      expr when is_binary(expr) ->
        expr

      nil ->
        case const_int_literal_from_plan(Keyword.get(instr_opts, :parent_plan), reg) do
          value when is_integer(value) -> Integer.to_string(value)
          _ -> "plan_native_int_#{reg}"
        end
    end
  end

  defp const_int_literal_from_plan(%FunctionPlan{} = plan, reg) do
    plan
    |> all_defining_instrs(reg)
    |> List.first()
    |> case do
      %{op: :const_int, args: %{value: value}} when is_integer(value) -> value
      _ -> nil
    end
  end

  defp const_int_literal_from_plan(_, _), do: nil

  defp native_bool_result_ref(reg, _instr_opts) do
    "plan_native_bool_#{reg}"
  end

  defp ret_source_reg(%FunctionPlan{blocks: blocks}) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        blocks
        |> Enum.flat_map(& &1.instrs)
        |> Enum.find_value(fn
          %{op: :publish, dest: :fn_out, args: %{source: reg}} when is_integer(reg) -> reg
          _ -> nil
        end)

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        reg

      _ ->
        nil
    end
  end

  defp maybe_add_native_ret_reg(regs, plan, reg, kind)
       when is_integer(reg) and kind in [:native_int, :native_bool] do
    if NativeReturn.ret_reg_allows_native?(plan, reg, kind) do
      MapSet.put(regs, reg)
    else
      regs
    end
  end

  defp maybe_add_native_ret_reg(regs, _plan, _reg, _kind), do: regs

  defp maybe_add_native_scalar_ret_bool_reg(regs, reg, :native_bool) when is_integer(reg),
    do: MapSet.put(regs, reg)

  defp maybe_add_native_scalar_ret_bool_reg(regs, _reg, _kind), do: regs

  @spec letrec_decl_lines([String.t()]) :: [String.t()]
  def letrec_decl_lines(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> "ElmcForwardRef *#{ref} = elmc_forward_ref_new();" end)
  end

  @spec letrec_free_lines([String.t()]) :: [String.t()]
  def letrec_free_lines(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> "elmc_forward_ref_free(#{ref});" end)
  end

  defp record_field_int?(field_name) when is_binary(field_name) do
    Process.get(:elmc_record_field_types, %{})
    |> Map.values()
    |> Enum.any?(fn fields when is_map(fields) ->
      Map.get(fields, field_name) == "Int" or Map.get(fields, to_string(field_name)) == "Int"
    end)
  end
end
