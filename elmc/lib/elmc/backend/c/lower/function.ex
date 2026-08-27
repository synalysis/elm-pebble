defmodule Elmc.Backend.C.Lower.Function do
  @moduledoc """
  Lower verified `%FunctionPlan{}` to C function body text (RC ABI).
  """
  alias Elmc.Types, as: Types


  alias Elmc.Backend.C.Ast
  alias Elmc.Backend.C.Ast.{Emit, Lint}

  alias Elmc.Backend.C.Lower.{
    DenseConstRecord,
    DenseIntTable,
    EphemeralBox,
    Frame,
    Instr,
    Lambda,
    NativeIntFold,
    NativeReturn,
    StringConcat,
    TagRefs
  }
  alias Elmc.Backend.CCodegen.{FunctionCallAbi, FunctionEmit, Fusion, RecordCompile, RcRequired, RetainOperandAlias}
  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.Optimize
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.SizeProfile

  @min_switch_arms 3

  @spec cleanup_cfg_text(String.t()) :: String.t()
  def cleanup_cfg_text(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> cleanup_cfg_lines()
    |> Enum.join("\n")
    |> String.trim()
  end

  @spec emit(FunctionPlan.t(), keyword()) :: String.t()
  def emit(%FunctionPlan{} = plan, opts \\ []) do
    fusion_c = Map.get(plan, :fusion_c)

    cond do
      is_binary(fusion_c) and fusion_c != "" and plan.blocks == [] ->
        cleanup_cfg_text(fusion_c)

      Keyword.get(opts, :shell, true) ->
        {core, slots} = emit_core_with_slots(plan, opts)
        wrap_shell(plan, core, slots)

      true ->
        emit_core(plan, opts)
    end
  end

  @spec emit_core(FunctionPlan.t(), keyword()) :: String.t()
  def emit_core(plan, opts \\ [])

  def emit_core(%FunctionPlan{fusion_c: c, blocks: []} = _plan, _opts)
      when is_binary(c) and c != "" do
    cleanup_cfg_text(c)
  end

  def emit_core(%FunctionPlan{} = plan, opts) do
    {core, _slots} = emit_core_with_slots(plan, opts)
    core
  end

  @spec emit_core_with_slots(FunctionPlan.t(), keyword()) :: {String.t(), map()}
  def emit_core_with_slots(plan, opts \\ [])

  def emit_core_with_slots(%FunctionPlan{fusion_c: c, blocks: []}, _opts)
      when is_binary(c) and c != "" do
    {cleanup_cfg_text(c), %{}}
  end

  def emit_core_with_slots(%FunctionPlan{} = plan, opts) do
    case DenseIntTable.emit_body(plan) do
      {:ok, body} ->
        {body, %{}}

      :error ->
        case DenseConstRecord.emit_body(plan) do
          {:ok, body} -> {body, %{}}
          :error -> emit_core_with_slots_cfg(plan, opts)
        end
    end
  end

  defp emit_core_with_slots_cfg(%FunctionPlan{} = plan, opts) do
    Process.put(:elmc_plan_rec_values_suffix, 0)
    Process.put(:elmc_rc_call_tmp_counter, 0)
    # Borrow marks are process-local and must not accumulate across functions —
    # stale owned[i] marks from earlier fns would null live slots in this epilogue
    # and leak (2048 collapseRows / step RC imbalance).
    RecordCompile.reset_borrowed_field_refs()

    unless Keyword.get(opts, :closure_mode) do
      Lambda.ensure_emitted!(plan)
    end

    rc? = plan.rc_required
    param_kinds = param_kinds_for_plan(plan)
    decl_map = Process.get(:elmc_program_decls, %{})
    {slots, _slot_count} = Plan.allocate_slots(plan)

    closure_mode = Keyword.get(opts, :closure_mode)

    {borrow_param_regs, slots} =
      allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, closure_mode)

    closure_borrow_regs = build_closure_borrow_regs(plan, closure_mode)

    const_int_regs = build_const_int_regs(plan)
    fusion_native_literal_regs = build_fusion_native_literal_regs(plan)
    const_c_expr_regs = build_const_c_expr_regs(plan)
    native_scalar_out = Map.get(plan, :native_scalar_return)
    ret_reg = ret_source_reg(plan)
    native_int_only_regs = build_native_int_only_regs(plan, decl_map)
    native_pair_regs = build_native_pair_component_regs(plan)
    native_list_int_pair_int_regs = build_native_list_int_pair_int_regs(plan)

    native_int_only_regs =
      native_int_only_regs
      |> MapSet.union(MapSet.new(Map.keys(native_pair_regs)))
      |> MapSet.union(MapSet.new(Map.keys(native_list_int_pair_int_regs)))

    # Allocate native-int param → C-arg aliases after native_int_only is known.
    # `retain` of a native-int param is counted in boxed_uses, but when the param
    # (and retain dest) stay native_int_only the C parameter is already native —
    # forcing an owned box leaves `plan_native_int_N` undeclared/uninitialized.
    {native_int_regs, slots} =
      allocate_native_int_param_slots(
        plan,
        slots,
        param_kinds,
        decl_map,
        closure_mode,
        native_int_only_regs
      )

    native_int_only_regs =
      maybe_add_native_ret_reg(native_int_only_regs, plan, ret_reg, native_scalar_out)

    # Native-int regs used as boxed operands (phi arms, tuples, …) must stay boxed ElmcValue*
    # (owned slots + `elmc_new_int`), not native `elmc_int_t` temps with skipped const_int emit.
    # Limit demotion to `const_int` defs: params / native call results keep `plan_native_int_*`
    # and ephemeral `elmc_new_int_take` at the use site. Pure `const_c_expr` tags prefer ephemeral
    # boxing too (exclude from owned).
    boxed_uses = boxed_use_regs(plan, decl_map)

    const_int_defs =
      boxed_uses
      |> Enum.filter(fn reg ->
        match?(%{op: :const_int}, plan_defining_instr(plan, reg))
      end)
      |> MapSet.new()

    native_int_owned_regs =
      native_int_only_regs
      |> MapSet.intersection(const_int_defs)
      |> MapSet.difference(MapSet.new(Map.keys(const_c_expr_regs)))

    native_int_only_regs = MapSet.difference(native_int_only_regs, native_int_owned_regs)

    unused_native_int_skip_regs = build_unused_native_int_skip_regs(plan, native_int_only_regs)

    # forward_ref_set needs a real ElmcValue* — never leave those regs as skipped
    # native temps (`tmp_N` undeclared) or pure native_int_only without a slot.
    forward_ref_value_regs = forward_ref_value_regs(plan)
    native_int_only_regs = MapSet.difference(native_int_only_regs, forward_ref_value_regs)

    tail_inline_skip_regs =
      plan
      |> build_tail_inline_skip_regs()
      |> MapSet.union(build_record_param_inline_skip_regs(plan, param_kinds))
      |> MapSet.union(build_unused_boxed_param_skip_regs(plan, param_kinds))
      |> MapSet.union(build_overwritten_inline_skip_regs(plan))
      |> MapSet.union(unused_native_int_skip_regs)
      |> MapSet.difference(forward_ref_value_regs)

    slots = Map.drop(slots, MapSet.to_list(tail_inline_skip_regs))

    # Hoist natives that need a mutable lvalue: RC out-param (`&plan_native_int_N`),
    # multiple defs, plan-state switch, or a use outside the def block (goto can
    # skip a `const` initializer while a join phi shape still names the temp).
    # Keep `const_int` / `const_c_expr` regs as use-site literals — forcing them into
    # mutable locals yields `plan_native_int_N = 8` with no reads (-Wunused-but-set).
    const_like_native_int_regs =
      MapSet.new(Map.keys(const_int_regs) ++ Map.keys(const_c_expr_regs))

    native_int_mutable_regs =
      native_int_only_regs
      |> MapSet.difference(unused_native_int_skip_regs)
      |> MapSet.difference(const_like_native_int_regs)
      |> Enum.filter(&native_int_needs_mutable_local?(plan, &1, decl_map))
      |> MapSet.new()

    # Mutable regs must keep real `plan_native_int_N` locals — never treat them as
    # single-def const inline text (`"2"`, `ELMC_COLOR_…`).
    const_int_regs = Map.drop(const_int_regs, MapSet.to_list(native_int_mutable_regs))
    const_c_expr_regs = Map.drop(const_c_expr_regs, MapSet.to_list(native_int_mutable_regs))

    native_bool_only_regs =
      build_native_bool_only_regs(plan, decl_map)
      |> MapSet.difference(native_int_only_regs)
      |> maybe_add_native_scalar_ret_bool_reg(ret_reg, native_scalar_out)

    # Same rule for native bools: mutable only when address-taken or multi-def.
    native_bool_mutable_regs =
      native_bool_only_regs
      |> Enum.filter(&native_bool_needs_mutable_local?(plan, &1, decl_map))
      |> MapSet.new()

    native_int_locals =
      native_int_only_regs
      |> MapSet.difference(MapSet.new(Map.keys(const_int_regs)))
      |> MapSet.difference(MapSet.new(Map.keys(const_c_expr_regs)))
      |> MapSet.difference(MapSet.new(Map.keys(native_int_regs)))
      |> MapSet.difference(MapSet.new(Map.keys(native_pair_regs)))
      |> MapSet.difference(MapSet.new(Map.keys(native_list_int_pair_int_regs)))
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
      |> Map.merge(native_pair_regs)
      |> Map.merge(native_list_int_pair_int_regs)
      |> Map.merge(native_int_locals)

    slots =
      finalize_owned_slots_map(
        plan,
        slots,
        MapSet.difference(native_int_only_regs, native_int_owned_regs),
        native_bool_only_regs,
        fusion_native_literal_regs
      )

    skip_fill =
      MapSet.difference(native_int_only_regs, native_int_owned_regs)
      |> MapSet.union(native_bool_only_regs)
      |> MapSet.union(fusion_native_literal_regs)
      |> MapSet.union(tail_inline_skip_regs)
      |> MapSet.union(MapSet.new(Map.keys(native_int_regs)))
      |> MapSet.union(MapSet.new(Map.keys(borrow_param_regs)))
      |> MapSet.union(closure_borrow_regs)
      |> MapSet.difference(forward_ref_value_regs)

    slots = fill_missing_owned_slots(plan, slots, skip_fill)

    native_int_inline =
      NativeIntFold.inline_exprs(plan,
        slots: slots,
        native_int_only_regs: native_int_only_regs,
        native_bool_only_regs: native_bool_only_regs,
        native_int_regs: native_int_operand_regs,
        const_int_regs: const_int_regs,
        native_ret_reg: ret_reg,
        borrow_param_regs: borrow_param_regs,
        closure_mode: closure_mode,
        param_kinds: param_kinds,
        params: param_names(plan.params),
        parent_plan: plan,
        boxed_direct_scene_argv?: boxed_direct_scene_argv?(plan, decl_map)
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
      native_list_int_pair_pair_regs:
        Map.get(plan, :native_list_int_pair_pair_regs) || MapSet.new(),
      fused_string_roots: string_fusion.roots,
      fused_string_skip_regs: string_fusion.skip_regs,
      tail_inline_skip_regs: tail_inline_skip_regs,
      direct_scene_writer: Process.get(:elmc_direct_scene_writer, false),
      boxed_direct_scene_argv?: boxed_direct_scene_argv?(plan, decl_map),
      scene_writer_var: "writer",
      ownership: Map.get(lookup_decl(plan.module, plan.name) || %{}, :ownership, []),
      lambdas: plan.lambdas,
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

    # Only emit when a mid-CFG `{:ret, _}` will `goto` here — unused labels
    # fail pebble builds under -Werror=unused-label.
    epilogue =
      if not state_switch_emit?(plan) and needs_plan_epilogue_label?(plan) do
        ["elmc_plan_epilogue:"]
      else
        []
      end

    core =
      (body_lines ++ epilogue ++ List.wrap(ret_line) ++ List.wrap(deferred_cleanup))
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(&String.split(&1, "\n"))
      |> cleanup_cfg_lines(explicit_targets)
      |> then(fn lines ->
        missing_native_int_decl_lines(lines, native_int_locals) ++ lines
      end)
      |> Enum.join("\n")
      |> cleanup_cfg_text()

    {core, slots}
  end

  @spec missing_native_int_decl_lines([String.t()], map()) :: [String.t()]

  defp missing_native_int_decl_lines(lines, _native_int_locals) do
    body = Enum.join(lines, "\n")

    ~r/\bplan_native_int_(\d+)\b/
    |> Regex.scan(body)
    |> Enum.map(fn [_, reg] -> String.to_integer(reg) end)
    |> Enum.uniq()
    |> Enum.reject(fn reg ->
      name = "plan_native_int_#{reg}"

      Enum.any?(lines, fn line ->
        String.contains?(line, "elmc_int_t #{name}") or
          String.contains?(line, "const elmc_int_t #{name}")
      end)
    end)
    |> Enum.sort()
    |> Enum.map(fn reg -> "elmc_int_t plan_native_int_#{reg} = 0;" end)
  end

  @spec emit_goto_body(FunctionPlan.t(), Types.slot_map(), keyword(), [String.t()], MapSet.t(non_neg_integer())) :: [String.t()]

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

      block_instrs = truncate_after_non_rc_tail_fn_out(instrs, rc?)

      block_lines =
        (fn ->
           # Per-block owned-live: goto CFG arms are mutually exclusive at runtime;
           # carrying emit-time live state across blocks marks phi merge slots live
           # when only a different arm wrote them.
           Process.put(:elmc_plan_owned_live, MapSet.new())

           block_instrs
           |> fuse_open_list_map_loops()
           |> Enum.flat_map(&emit_instr_lines(&1, slots, instr_opts))
         end).()

      (if labeled_block?(id, explicit_targets), do: [block_label(id)], else: []) ++
        block_lines ++
        [emit_terminator(term, slots, rc?, Keyword.put(instr_opts, :next_id, next_id))]
    end)
    |> Enum.reject(&(&1 == ""))
    |> then(&(mutable_decls ++ &1))
  end

  @spec state_switch_emit?(map()) :: boolean()

  defp state_switch_emit?(%FunctionPlan{} = plan) do
    codegen_opts = Process.get(:elmc_codegen_opts, %{})
    thresholds = SizeProfile.plan_state_switch_thresholds(codegen_opts)

    SizeProfile.plan_emit_mode(codegen_opts) == :state_switch and
      not is_binary(Map.get(plan, :fusion_c)) and
      Map.get(plan, :native_scalar_return) not in [:native_int, :native_bool] and
      length(plan.blocks) >= thresholds.min_blocks and
      plan_emit_owned_slot_count(plan) <= thresholds.max_owned_slots
  end

  @spec emit_state_switch_body(FunctionPlan.t(), Types.slot_map(), keyword(), [String.t()]) :: [String.t()]

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
          (fn ->
             Process.put(:elmc_plan_owned_live, MapSet.new())

             instrs
             |> fuse_open_list_map_loops()
             |> Enum.flat_map(&emit_instr_lines(&1, slots, instr_opts))
             |> Enum.reject(&(&1 == ""))
             |> Enum.map(&("    " <> &1))
             |> Enum.join("\n")
           end).()

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

  @spec plan_state_c_ref(keyword(), integer()) :: String.t()

  defp plan_state_c_ref(opts, block_id) when is_integer(block_id) do
    plan = Keyword.fetch!(opts, :parent_plan)
    labels = Keyword.get(opts, :plan_state_labels, %{})
    TagRefs.plan_state_ref(plan, block_id, labels)
  end

  @spec plan_module_from(keyword()) :: String.t() | nil

  defp plan_module_from(opts) do
    Keyword.get(opts, :module) ||
      case Keyword.get(opts, :parent_plan) do
        %{module: mod} when is_binary(mod) -> mod
        _ -> nil
      end
  end

  @spec union_switch_tag_ref(integer(), String.t() | nil, String.t() | nil) :: String.t()

  defp union_switch_tag_ref(tag, ctor_name, module) when is_integer(tag) do
    TagRefs.union_tag_ref(tag, ctor_name, module)
  end

  @spec const_int_c_ref_for_inline(integer() | {integer(), term()} | {integer(), term(), term()}, String.t() | nil) :: String.t()

  defp const_int_c_ref_for_inline(value, module)

  defp const_int_c_ref_for_inline(value, _module) when is_integer(value), do: Integer.to_string(value)

  defp const_int_c_ref_for_inline({value, ctor}, module) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, module)

  defp const_int_c_ref_for_inline({value, ctor, _bool_lit?}, module) when is_integer(value),
    do: TagRefs.const_int_ref(value, ctor, module)

  @spec emit_state_switch_terminator(Block.terminator() | term(), Types.slot_map(), boolean(), keyword()) :: String.t()

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

  defp emit_state_switch_terminator({:ret, reg}, slots, rc?, opts) when is_integer(reg) do
    if rc? do
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
              slot_count = owned_slot_count(slots)

              """
              *out = #{ref};
              elmc_owned_null_aliases(owned, #{slot_count}, *out);
              """
            else
              "*out = #{ref};"
            end
        end

      "#{assign}\n    __plan_state = -1; break;"
    else
      "__plan_state = -1; break;"
    end
  end

  defp emit_state_switch_terminator(:none, _slots, _rc?, _opts), do: "__plan_state = -1; break;"
  defp emit_state_switch_terminator(_, _slots, _rc?, _opts), do: "__plan_state = -1; break;"

  @spec emit_state_int_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_state_int_switch(subject_s, arms, default_id, opts) do
    if length(arms) >= @min_switch_arms do
      emit_state_int_c_switch(subject_s, arms, default_id, opts)
    else
      emit_state_int_switch_chain(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_state_union_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_state_union_switch(subject_s, arms, default_id, opts) do
    cond do
      union_tag_int_switch?(arms) ->
        emit_state_int_switch(union_tag_int_expr(subject_s), arms, default_id, opts)

      length(arms) >= @min_switch_arms ->
        emit_state_union_c_switch(subject_s, arms, default_id, opts)

      true ->
        emit_state_union_switch_chain(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_state_int_switch_chain(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

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

  @spec emit_state_union_switch_chain(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

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

  @spec emit_state_int_c_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_state_int_c_switch(subject_s, arms, default_id, opts) do
    if duplicate_switch_arm_refs?(arms, plan_module_from(opts)) do
      emit_state_int_switch_chain(subject_s, arms, default_id, opts)
    else
      emit_state_int_c_switch_table(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_state_int_c_switch_table(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_state_int_c_switch_table(subject_s, arms, default_id, opts) do
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

  @spec emit_state_union_c_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_state_union_c_switch(subject_s, arms, default_id, opts) do
    if duplicate_switch_arm_refs?(arms, plan_module_from(opts)) do
      emit_state_union_switch_chain(subject_s, arms, default_id, opts)
    else
      emit_state_union_c_switch_table(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_state_union_c_switch_table(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_state_union_c_switch_table(subject_s, arms, default_id, opts) do
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

  @spec state_switch_default_line(non_neg_integer() | nil, keyword()) :: String.t() | nil

  defp state_switch_default_line(nil, _opts), do: nil

  defp state_switch_default_line(target_id, opts),
    do: "__plan_state = #{plan_state_c_ref(opts, target_id)}; break;"

  @spec state_switch_c_default_line(non_neg_integer() | nil, keyword()) :: String.t() | nil

  defp state_switch_c_default_line(nil, _opts), do: nil

  defp state_switch_c_default_line(target_id, opts),
    do: "default: __plan_state = #{plan_state_c_ref(opts, target_id)}; break;"

  @spec cleanup_cfg_lines([String.t()], MapSet.t(non_neg_integer())) :: [String.t()]

  defp cleanup_cfg_lines(lines, protected_block_ids \\ MapSet.new()) do
    lines
    |> Enum.flat_map(&String.split(&1, "\n"))
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(&1 == ""))
    |> coalesce_consecutive_block_labels(protected_block_ids)
    |> remove_redundant_cfg_jumps()
    |> remove_unused_block_labels()
  end

  @spec remove_unused_block_labels([String.t()]) :: [String.t()]

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

  @spec coalesce_consecutive_block_labels([String.t()], MapSet.t(non_neg_integer())) :: [String.t()]

  defp coalesce_consecutive_block_labels(lines, protected_block_ids) do
    {out, aliases, pending} =
      Enum.reduce(lines, {[], %{}, []}, fn line, {out, aliases, pending} ->
        case block_label_id(line) do
          id when is_integer(id) ->
            {out, Map.put(aliases, id, id), pending ++ [id]}

          _ ->
            {out, aliases} = flush_pending_labels(out, aliases, pending, protected_block_ids)
            {out ++ [line], aliases, []}
        end
      end)

    {out, aliases} = flush_pending_labels(out, aliases, pending, protected_block_ids)
    rewrite_block_label_refs(out, aliases)
  end

  @spec flush_pending_labels([String.t()], %{non_neg_integer() => non_neg_integer()}, [non_neg_integer()], MapSet.t(non_neg_integer())) :: {[String.t()], %{non_neg_integer() => non_neg_integer()}}

  defp flush_pending_labels(out, aliases, [], _protected_block_ids), do: {out, aliases}

  defp flush_pending_labels(out, aliases, pending, protected_block_ids) do
    pending = Enum.reverse(pending)

    if coalesce_pending_block_labels?(pending, protected_block_ids) do
      keeper = List.last(pending)

      aliases =
        Enum.reduce(pending, aliases, fn id, map ->
          if id == keeper, do: map, else: Map.put(map, id, keeper)
        end)

      {out ++ [block_label(keeper)], aliases}
    else
      {out ++ Enum.map(pending, &block_label/1), aliases}
    end
  end

  @spec coalesce_pending_block_labels?([non_neg_integer()], MapSet.t(non_neg_integer())) :: boolean()

  defp coalesce_pending_block_labels?([_single], _protected_block_ids), do: false

  defp coalesce_pending_block_labels?(pending, protected_block_ids) when is_list(pending) do
    length(pending) > 1 and
      not Enum.any?(pending, &MapSet.member?(protected_block_ids, &1))
  end

  @spec block_label_id(String.t()) :: non_neg_integer() | nil

  defp block_label_id("/* plan block 0 */"), do: 0

  defp block_label_id(line) when is_binary(line) do
    case Regex.run(~r/^elmc_plan_block_(\d+):$/, String.trim(line)) do
      [_, id_s] -> String.to_integer(id_s)
      _ -> nil
    end
  end

  @spec rewrite_block_label_refs([String.t()], %{non_neg_integer() => non_neg_integer()}) :: [String.t()]

  defp rewrite_block_label_refs(lines, aliases) when map_size(aliases) == 0, do: lines

  defp rewrite_block_label_refs(lines, aliases) do
    Enum.map(lines, fn line ->
      Regex.replace(~r/\belmc_plan_block_(\d+)\b/, line, fn _, id_s ->
        id = String.to_integer(id_s)
        "elmc_plan_block_#{Map.get(aliases, id, id)}"
      end)
    end)
  end

  @spec remove_redundant_cfg_jumps([String.t()]) :: [String.t()]

  defp remove_redundant_cfg_jumps(lines) do
    do_remove_redundant_cfg_jumps(lines)
  end

  @spec do_remove_redundant_cfg_jumps([String.t()]) :: [String.t()]

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

  @spec unified_branch_to_same_target?(String.t(), String.t()) :: boolean()

  defp unified_branch_to_same_target?(if_line, goto_line) do
    with {:ok, t1} <- if_goto_target(if_line),
         {:ok, t2} <- goto_target(goto_line),
         true <- t1 == t2 do
      true
    else
      _ -> false
    end
  end

  @spec redundant_goto_before_label?(String.t(), String.t()) :: boolean()

  defp redundant_goto_before_label?(goto_line, label_line) do
    with {:ok, target} <- goto_target(goto_line),
         {:ok, ^target} <- block_label_target(label_line) do
      true
    else
      _ -> false
    end
  end

  @spec if_goto_targets_label?(String.t(), String.t()) :: boolean()

  defp if_goto_targets_label?(if_line, label_line) do
    with {:ok, target} <- if_goto_target(if_line),
         {:ok, ^target} <- block_label_target(label_line) do
      true
    else
      _ -> false
    end
  end

  @spec if_goto_target(String.t()) :: {:ok, String.t()} | :error

  defp if_goto_target(line) do
    case Regex.run(~r/^if \(.+\) goto (elmc_plan_block_\d+);$/, String.trim(line)) do
      [_, target] -> {:ok, target}
      _ -> :error
    end
  end

  @spec goto_target(String.t()) :: {:ok, String.t()} | :error

  defp goto_target(line) do
    case Regex.run(~r/^goto (elmc_plan_block_\d+);$/, String.trim(line)) do
      [_, target] -> {:ok, target}
      _ -> :error
    end
  end

  @spec block_label_target(String.t()) :: {:ok, String.t()} | :error

  defp block_label_target(line) do
    case block_label_id(line) do
      id when is_integer(id) -> {:ok, "elmc_plan_block_#{id}"}
      _ -> :error
    end
  end

  @spec block_label(non_neg_integer()) :: String.t()

  defp block_label(0), do: "/* plan block 0 */"
  defp block_label(id), do: "elmc_plan_block_#{id}:"

  @spec labeled_block?(non_neg_integer(), MapSet.t(non_neg_integer())) :: boolean()

  defp labeled_block?(0, _), do: true
  defp labeled_block?(id, explicit_targets), do: MapSet.member?(explicit_targets, id)

  @spec explicit_jump_target_ids([Block.t()]) :: MapSet.t(non_neg_integer())

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

  @spec explicit_targets_from_terminator(Block.terminator() | term(), non_neg_integer() | nil) :: [non_neg_integer()]

  defp explicit_targets_from_terminator({:br, target_id}, _next_id), do: [target_id]

  defp explicit_targets_from_terminator({:br_if, then_id, else_id, _}, _next_id) do
    Enum.uniq([then_id, else_id])
  end

  defp explicit_targets_from_terminator({:switch_tag, _, arms, default_id}, _next_id) do
    Enum.map(arms, &TagRefs.switch_arm_target/1) ++ List.wrap(default_id)
  end

  defp explicit_targets_from_terminator(_, _), do: []

  @spec emit_instr_lines(Types.t() | map(), Types.slot_map(), keyword()) :: [String.t()]

  defp emit_instr_lines(instr, slots, instr_opts) do
    live = Process.get(:elmc_plan_owned_live, MapSet.new())
    {reassignment, live} = owned_reassign_prefix(instr, slots, instr_opts, live)
    Process.put(:elmc_plan_owned_live, live)
    code = Instr.emit(instr, slots, instr_opts)

    alias_xfer =
      case emit_result_alias_transfer(instr, slots, instr_opts) do
        "" -> []
        line -> [line]
      end

    nulls =
      cond do
        # Dest skipped for later reconstruction: do not release its boxed operands here.
        skipped_dest_instr?(instr, instr_opts) ->
          []

        tail_fn_out_owned_cleanup_instr?(instr) and not transferring_consume_instr?(instr, instr_opts) ->
          # Tail writes into *out / branch out; skip cleanup that would release the published
          # value. Transferring consumes (e.g. record_new_values_take into out) still must null
          # the moved owned[] slots so LIFO / later :release ops do not double-free fields.
          []

        true ->
          emit_null_consumed_slots(instr, slots, instr_opts)
      end
    live = update_owned_live_slots(instr, slots, instr_opts, live)
    live = clear_record_update_cow_drop_base_live(instr, slots, live)
    Process.put(:elmc_plan_owned_live, live)

    [reassignment, code, alias_xfer, nulls]
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
  end

  # C-only: `make_closure` + `list_map` → open loop calling the static closure fn
  # with stack captures (no heap closure cell, no `elmc_list_map` runtime).
  # Intervening instrs that do not touch the closure dest are kept (e.g. record_get
  # for the list operand between make_closure and list_map).
  @spec fuse_open_list_map_loops([map()]) :: [map()]
  defp fuse_open_list_map_loops(instrs) when is_list(instrs) do
    case find_fusible_closure_list_map(instrs) do
      {:ok, before, mid, walk, rest_instrs} ->
        fuse_open_list_map_loops(before ++ mid ++ [walk] ++ rest_instrs)

      :none ->
        instrs
    end
  end

  defp find_fusible_closure_list_map(instrs) do
    instrs
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {_instr, i} ->
      case unwrap_make_closure(instrs, i) do
        {:ok, clos_dest, idx, caps, mc_span} ->
          case find_list_map_after(instrs, mc_span.last + 1, clos_dest) do
            {:ok, map_span, map_dest, list_reg, map, acc} ->
              mid = Enum.slice(instrs, (mc_span.last + 1)..(map_span.first - 1)//1)

              if closure_dest_untouched?(mid, clos_dest) do
                before = Enum.take(instrs, mc_span.first)
                rest_instrs = Enum.drop(instrs, map_span.last + 1)
                walk = list_walk_map_instr(map_dest, list_reg, idx, caps, map, clos_dest, acc)
                {:ok, before, mid, walk, rest_instrs}
              else
                nil
              end

            :none ->
              nil
          end

        :none ->
          nil
      end
    end)
  end

  defp unwrap_make_closure(instrs, i) do
    case Enum.at(instrs, i) do
      %{op: :catch_begin} ->
        case Enum.slice(instrs, i, 3) do
          [
            %{op: :catch_begin},
            %{op: :make_closure, dest: dest, args: %{index: idx, captures: caps}},
            %{op: :catch_end}
          ]
          when is_integer(dest) ->
            {:ok, dest, idx, caps, %{first: i, last: i + 2}}

          _ ->
            :none
        end

      %{op: :make_closure, dest: dest, args: %{index: idx, captures: caps}} when is_integer(dest) ->
        {:ok, dest, idx, caps, %{first: i, last: i}}

      _ ->
        :none
    end
  end

  defp find_list_map_after(instrs, start, clos_dest) do
    instrs
    |> Enum.with_index()
    |> Enum.drop(start)
    |> Enum.find_value(:none, fn {instr, i} ->
      case instr do
        %{op: :catch_begin} ->
          case Enum.slice(instrs, i, 3) do
            [
              %{op: :catch_begin},
              %{op: :call_runtime, dest: map_dest, args: %{builtin: builtin, args: hof_args}} = map,
              %{op: :catch_end}
            ] ->
              list_hof_match(i, i + 2, clos_dest, map_dest, builtin, hof_args, map)

            _ ->
              nil
          end

        %{op: :call_runtime, dest: map_dest, args: %{builtin: builtin, args: hof_args}} = map ->
          list_hof_match(i, i, clos_dest, map_dest, builtin, hof_args, map)

        _ ->
          nil
      end
    end)
  end

  defp closure_dest_untouched?(mid, clos_dest) do
    Enum.all?(mid, fn instr ->
      dest = Map.get(instr, :dest)
      effects = Map.get(instr, :effects) || %{}
      consumes = Map.get(effects, :consumes) || []
      dest != clos_dest and clos_dest not in consumes
    end)
  end

  defp list_hof_match(first, last, clos_dest, map_dest, builtin, [c, list], map)
       when c == clos_dest and is_integer(list) and
              builtin in [:list_map, :list_filter, :list_indexed_map] do
    {:ok, %{first: first, last: last}, map_dest, list, map, nil}
  end

  defp list_hof_match(first, last, clos_dest, map_dest, :list_foldl, [c, acc, list], map)
       when c == clos_dest and is_integer(list) and is_integer(acc) do
    {:ok, %{first: first, last: last}, map_dest, list, map, acc}
  end

  defp list_hof_match(_, _, _, _, _, _, _), do: nil

  defp list_walk_map_instr(map_dest, list_reg, idx, caps, map, _clos_dest, acc) do
    caps = List.wrap(caps)
    kind = list_walk_kind(map)
    acc_regs = if is_integer(acc), do: [acc], else: []

    effects = %{
      produces: if(is_integer(map_dest), do: {:owned, map_dest}, else: nil),
      consumes: [],
      borrows: Enum.uniq([list_reg | caps] ++ acc_regs),
      fallible: true
    }

    args = %{
      list: list_reg,
      lambda_idx: idx,
      captures: caps,
      kind: kind
    }

    args = if is_integer(acc), do: Map.put(args, :acc, acc), else: args

    %Types{
      op: :list_walk_map,
      dest: map_dest,
      args: args,
      effects: effects,
      id: Map.get(map, :id),
      block_id: Map.get(map, :block_id),
      span: Map.get(map, :span)
    }
  end

  defp list_walk_kind(%{args: %{builtin: :list_filter}}), do: :filter
  defp list_walk_kind(%{args: %{builtin: :list_indexed_map}}), do: :indexed_map
  defp list_walk_kind(%{args: %{builtin: :list_foldl}}), do: :foldl
  defp list_walk_kind(_), do: :map

  @spec skipped_dest_instr?(map() | term(), keyword()) :: boolean()

  defp skipped_dest_instr?(%{dest: dest}, instr_opts) when is_integer(dest) do
    MapSet.member?(Keyword.get(instr_opts, :fused_string_skip_regs, MapSet.new()), dest) or
      MapSet.member?(Keyword.get(instr_opts, :tail_inline_skip_regs, MapSet.new()), dest)
  end

  defp skipped_dest_instr?(_, _), do: false

  @spec clear_record_update_cow_drop_base_live(Types.t() | map(), Types.slot_map(), MapSet.t(non_neg_integer())) :: MapSet.t(non_neg_integer())

  defp clear_record_update_cow_drop_base_live(
         %{op: :record_update, args: %{base: base_reg}, dest: dest_reg},
         slots,
         live
       )
       when is_integer(base_reg) and is_integer(dest_reg) do
    case {Map.get(slots, base_reg), Map.get(slots, dest_reg)} do
      {base_idx, dest_idx} when is_integer(base_idx) and is_integer(dest_idx) and base_idx != dest_idx ->
        MapSet.delete(live, base_idx)

      _ ->
        live
    end
  end

  defp clear_record_update_cow_drop_base_live(_instr, _slots, live), do: live

  @spec owned_reassign_prefix(Types.t() | map(), Types.slot_map(), keyword(), MapSet.t(non_neg_integer())) :: {String.t(), MapSet.t(non_neg_integer())}

  defp owned_reassign_prefix(_instr, _slots, _instr_opts, live) do
    # Identity owned[reg] allocation + frame `elmc_release_array_lifo`: never emit
    # mid-body `elmc_release(owned[i])` before a write. SSA dests are unique and
    # slots are not packed across regs, so overwrite-reuse does not apply.
    {"", live}
  end

  @spec update_owned_live_slots(Types.t() | map(), Types.slot_map(), keyword(), MapSet.t(non_neg_integer())) :: MapSet.t(non_neg_integer())

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

  @spec clear_consumed_owned_slots(Types.t() | map(), Types.slot_map(), keyword(), MapSet.t(non_neg_integer())) :: MapSet.t(non_neg_integer())

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

  @spec boxed_owned_index(Types.reg(), Types.slot_map(), keyword()) :: non_neg_integer() | nil

  defp boxed_owned_index(reg, slots, instr_opts) when is_integer(reg) do
    if MapSet.member?(Keyword.get(instr_opts, :native_int_only_regs, MapSet.new()), reg) or
         MapSet.member?(Keyword.get(instr_opts, :native_bool_only_regs, MapSet.new()), reg) or
         MapSet.member?(Keyword.get(instr_opts, :tail_inline_skip_regs, MapSet.new()), reg) do
      nil
    else
      Map.get(slots, reg)
    end
  end

  @spec tail_fn_out_owned_cleanup_instr?(map() | term()) :: boolean()

  defp tail_fn_out_owned_cleanup_instr?(%{op: op, dest: dest})
       when op in [:call_runtime, :call_fn, :call_closure, :record_update, :pebble_cmd, :pipe_apply_repeat] and
              dest in [:fn_out, :branch_out],
       do: true

  defp tail_fn_out_owned_cleanup_instr?(_), do: false

  @spec truncate_after_non_rc_tail_fn_out([Types.t()], boolean()) :: [Types.t()]

  defp truncate_after_non_rc_tail_fn_out(instrs, false) do
    case Enum.find_index(instrs, &non_rc_tail_fn_out_instr?/1) do
      nil -> instrs
      idx -> Enum.take(instrs, idx + 1)
    end
  end

  defp truncate_after_non_rc_tail_fn_out(instrs, _), do: instrs

  @spec non_rc_tail_fn_out_instr?(map() | term()) :: boolean()

  defp non_rc_tail_fn_out_instr?(%{dest: dest, op: op})
       when dest in [:fn_out, :branch_out] and
              op in [
                :call_runtime,
                :call_fn,
                :call_closure,
                :record_update,
                :pebble_cmd,
                :publish,
                :pipe_apply_repeat
              ],
       do: true

  defp non_rc_tail_fn_out_instr?(_), do: false

  @spec emit_null_consumed_slots(Types.t() | map() | term(), Types.slot_map(), keyword()) :: [String.t()]

  defp emit_null_consumed_slots(%{op: :publish}, _slots, _instr_opts), do: []

  defp emit_null_consumed_slots(%{op: :release}, _slots, _instr_opts), do: []

  defp emit_null_consumed_slots(%{op: :phi, dest: dest} = instr, slots, instr_opts)
       when is_integer(dest) do
    if phi_dead_owned_slot_transfer?(dest, slots, instr_opts) do
      []
    else
      emit_null_consumed_slots_from_effects(instr, slots, instr_opts)
    end
  end

  defp emit_null_consumed_slots(%{effects: %{consumes: consumes}} = instr, slots, instr_opts)
       when is_list(consumes) do
    emit_null_consumed_slots_from_effects(instr, slots, instr_opts)
  end

  defp emit_null_consumed_slots(_, _slots, _instr_opts), do: []

  @spec emit_result_alias_transfer(Types.t() | map(), Types.slot_map(), keyword()) :: String.t()

  defp emit_result_alias_transfer(
         %{op: :call_runtime, dest: dest, effects: %{result_aliases: aliases}},
         slots,
         instr_opts
       )
       when is_list(aliases) and aliases != [] do
    # Non-RC `ElmcValue *` tails fold alias-drop into wrap_non_rc_* (`__rc_ret` /
    # `__ret`). Emitting `*out` here is dead code after `return` and fails to compile.
    if dest in [:fn_out, :branch_out] and not Keyword.get(instr_opts, :rc_required, true) do
      ""
    else
      RetainOperandAlias.emit_for_plan_dest(dest, aliases, slots, instr_opts)
    end
  end

  defp emit_result_alias_transfer(_, _, _), do: ""

  @spec emit_null_consumed_slots_from_effects(Types.t() | map(), Types.slot_map(), keyword()) :: [String.t()]

  defp emit_null_consumed_slots_from_effects(%{effects: %{consumes: consumes}} = instr, slots, instr_opts)
       when is_list(consumes) do
    deferred = Keyword.get(instr_opts, :native_ret_deferred_regs, MapSet.new())
    transfer? = transferring_consume_instr?(instr, instr_opts)
    # borrow_result callees may return an owned arg by pointer alias without an
    # extra retain (e.g. fold base case `[] -> acc`). Releasing that arg after
    # the call would free the result — null instead.
    # retain_result callees (restore/orient Left) retain even when returning the
    # same pointer; the consume still owns a credit and must be released.
    result_owned_idx = call_result_owned_index(instr, slots, instr_opts)
    alias_return? = callee_borrow_returns_arg?(instr)

    consumes
    |> Enum.filter(&is_integer/1)
    |> Enum.reject(&retain_owned_transfer_null?(instr, &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :native_int_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :native_bool_only_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(Keyword.get(instr_opts, :tail_inline_skip_regs, MapSet.new()), &1))
    |> Enum.reject(&MapSet.member?(deferred, &1))
    |> Enum.uniq()
    |> Enum.map(fn reg ->
      case Map.get(slots, reg) do
        i when is_integer(i) ->
          cond do
            transfer? ->
              "owned[#{i}] = NULL;"

            # Dest and operand share a slot: LIFO must not free the result twice.
            is_integer(result_owned_idx) and result_owned_idx == i ->
              "owned[#{i}] = NULL;"

            # borrow_result may return an arg by pointer alias — null only that case.
            is_integer(result_owned_idx) and alias_return? ->
              """
              if (owned[#{result_owned_idx}] == owned[#{i}]) {
                owned[#{i}] = NULL;
              }
              """
              |> String.trim()

            true ->
              # Retain-style consume: leave owned[i] for epilogue LIFO (no mid-body release).
              ""
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  # Owned slot holding a call/closure result, when the callee may borrow-return an arg.
  @spec call_result_owned_index(map(), map(), keyword()) :: integer() | nil

  defp call_result_owned_index(%{op: op, dest: dest}, slots, instr_opts)
       when op in [:call_fn, :call_closure] and is_integer(dest) do
    boxed_owned_index(dest, slots, instr_opts)
  end

  defp call_result_owned_index(_, _, _), do: nil

  @spec callee_borrow_returns_arg?(map() | term()) :: boolean()

  defp callee_borrow_returns_arg?(%{op: :call_fn, args: %{module: mod, name: name}}) do
    ownership = List.wrap(Map.get(lookup_decl(mod, name) || %{}, :ownership, []))
    :borrow_result in ownership and :retain_result not in ownership
  end

  defp callee_borrow_returns_arg?(_), do: false

  @spec phi_dead_owned_slot_transfer?(Types.reg(), Types.slot_map(), keyword()) :: boolean()

  defp phi_dead_owned_slot_transfer?(dest, slots, instr_opts) do
    case boxed_owned_index(dest, slots, instr_opts) do
      idx when is_integer(idx) ->
        live = Process.get(:elmc_plan_owned_live, MapSet.new())
        not MapSet.member?(live, idx)

      _ ->
        false
    end
  end

  @spec retain_owned_transfer_null?(Types.t() | map() | term(), Types.reg() | term()) :: boolean()

  defp retain_owned_transfer_null?(
         %{op: :call_runtime, args: %{builtin: :retain, args: [src]}, effects: %{consumes: consumes}},
         reg
       )
       when is_integer(src) and is_list(consumes),
       do: reg == src and src in consumes

  defp retain_owned_transfer_null?(_, _), do: false

  @spec transferring_consume_instr?(map() | term(), keyword()) :: boolean()

  defp transferring_consume_instr?(
         %{
           op: :call_runtime,
           args: %{builtin: :retain, args: [src]},
           effects: %{consumes: consumes}
         },
         _instr_opts
       )
       when is_integer(src) and is_list(consumes) do
    src in consumes
  end

  defp transferring_consume_instr?(%{op: :call_runtime, args: %{builtin: :tuple2}}, instr_opts) do
    # Non-RC lowers `:tuple2` to `elmc_tuple2_take_value` (moves args). RC lowers to
    # `elmc_tuple2` which retains — releasing consumed slots after the call is correct.
    not Keyword.get(instr_opts, :rc_required, true)
  end

  defp transferring_consume_instr?(%{op: :call_runtime, args: %{builtin: id}}, _instr_opts) do
    # record_new_values_ints copies scalar ints; it does not take ownership of boxed args.
    id in [:record_new, :record_new_take, :tuple2_take] or
      RuntimeBuiltins.ownership_transfer?(id)
  end

  defp transferring_consume_instr?(%{op: :pipe_apply_repeat}, _instr_opts), do: true

  defp transferring_consume_instr?(_, _), do: false

  @spec build_native_ret_deferred_release_regs(FunctionPlan.t(), Types.slot_map(), map(), MapSet.t(Types.reg())) :: MapSet.t(Types.reg())

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

  @spec int_arith_owned_operand_regs(Types.t() | map() | term()) :: [Types.reg()]

  defp int_arith_owned_operand_regs(%{op: :int_arith, args: %{kind: kind} = args})
       when kind in [:add_vars, :mul_vars, :sub_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars] do
    [Map.get(args, :lhs), Map.get(args, :rhs)]
    |> Enum.filter(&is_integer/1)
  end

  defp int_arith_owned_operand_regs(%{op: :int_arith, args: %{kind: kind, lhs: lhs}})
       when kind in [:add_const, :sub_const] and is_integer(lhs),
       do: [lhs]

  defp int_arith_owned_operand_regs(_), do: []

  @spec emit_deferred_consume_releases(keyword(), Types.slot_map()) :: String.t()

  defp emit_deferred_consume_releases(instr_opts, slots) do
    # Deferred consumes stay in owned[] until frame LIFO; do not emit mid-body releases.
    _ = {instr_opts, slots}
    ""
  end

  @spec emit_terminator(Block.terminator() | term(), Types.slot_map(), boolean(), keyword()) :: String.t()

  defp emit_terminator({:br_if, then_id, else_id, cond_reg}, slots, _rc?, opts) do
    next_id = Keyword.get(opts, :next_id)
    cond = Instr.branch_cond_expr(cond_reg, slots, opts)

    # Cond is already a C boolean (native bool or elmc_as_bool(...)).
    # Never compare elmc_as_bool() to integer 0/1.
    neg_cond = "!#{cond}"
    pos_cond = cond

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
        subject_s = int_switch_subject_ref(subject, slots, opts)
        emit_int_switch(subject_s, arms, default_id, opts)

      ctor_int_tag_switch_subject?(subject, opts) ->
        emit_int_switch("elmc_as_int(#{Instr.switch_subject_ref(subject, slots, opts)})", arms, default_id, opts)

      true ->
        emit_union_switch(subject_s, arms, default_id, opts)
    end
  end

  defp emit_terminator({:ret, _}, _slots, _rc?, opts) do
    # Goto CFG relies on fallthrough into CATCH_END when the ret block is last.
    # If a later block exists (e.g. a shared arm body inserted after merge), jump
    # past it to the function epilogue label.
    case Keyword.get(opts, :next_id) do
      next when is_integer(next) -> "goto elmc_plan_epilogue;"
      _ -> ""
    end
  end

  defp emit_terminator(:none, _slots, _rc?, _opts), do: ""
  defp emit_terminator(_, _slots, _rc?, _opts), do: ""

  @spec needs_plan_epilogue_label?(FunctionPlan.t()) :: boolean()

  defp needs_plan_epilogue_label?(%FunctionPlan{blocks: blocks}) do
    last_id =
      case List.last(blocks) do
        %Block{id: id} -> id
        _ -> nil
      end

    Enum.any?(blocks, fn
      %Block{id: id, terminator: {:ret, _}} -> id != last_id
      _ -> false
    end)
  end

  @spec ctor_int_tag_switch_subject?(integer(), keyword()) :: boolean()

  defp ctor_int_tag_switch_subject?(reg, opts) when is_integer(reg) do
    case plan_defining_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :call_fn, args: %{module: mod, name: name}} ->
        ctor_int_tag_return_type?(lookup_decl(mod, name))

      _ ->
        false
    end
  end

  @spec ctor_int_tag_return_type?(map() | term()) :: boolean()

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

  @spec type_short_name(String.t()) :: String.t()

  defp type_short_name(qualified) when is_binary(qualified) do
    qualified |> String.split(".") |> List.last()
  end

  @spec native_int_switch_subject?(Types.reg() | Types.result_slot(), keyword()) :: boolean()

  defp native_int_switch_subject?(:fn_out, opts) do
    case plan_defining_instr(Keyword.get(opts, :parent_plan), :fn_out) do
      %{op: :call_runtime, args: %{builtin: :char_to_code}} -> true
      _ -> false
    end
  end

  defp native_int_switch_subject?(reg, opts) when is_integer(reg) do
    MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) or
      Map.has_key?(Keyword.get(opts, :native_int_regs, %{}), reg) or
      native_param_kind(reg, opts) == :native_int
  end

  @spec int_switch_subject_ref(Types.reg() | Types.result_slot(), Types.slot_map(), keyword()) :: String.t()

  defp int_switch_subject_ref(:fn_out, slots, opts) do
    case plan_defining_instr(Keyword.get(opts, :parent_plan), :fn_out) do
      %{op: :call_runtime, args: %{builtin: :char_to_code}} ->
        "elmc_as_int(#{Instr.switch_subject_ref(:fn_out, slots, opts)})"

      _ ->
        Instr.switch_subject_ref(:fn_out, slots, opts)
    end
  end

  defp int_switch_subject_ref(subject, slots, opts),
    do: Instr.switch_subject_ref(subject, slots, opts)

  @spec native_param_kind(Types.reg(), keyword()) :: atom() | nil

  defp native_param_kind(reg, opts) do
    case plan_defining_instr(Keyword.get(opts, :parent_plan), reg) do
      %{op: :load_param, args: %{index: index}} ->
        Enum.at(Keyword.get(opts, :param_kinds, []), index)

      _ ->
        nil
    end
  end

  @spec emit_int_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_int_switch(subject_s, arms, default_id, opts) do
    _next_id = Keyword.get(opts, :next_id)

    if length(arms) >= @min_switch_arms do
      emit_int_c_switch(subject_s, arms, default_id, opts)
    else
      emit_int_switch_chain(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_union_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_union_switch(subject_s, arms, default_id, opts) do
    cond do
      union_tag_int_switch?(arms) ->
        emit_int_switch(union_tag_int_expr(subject_s), arms, default_id, opts)

      length(arms) >= @min_switch_arms ->
        emit_union_c_switch(subject_s, arms, default_id, opts)

      true ->
        emit_switch_tag_chain(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_int_c_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_int_c_switch(subject_s, arms, default_id, opts) do
    if duplicate_switch_arm_refs?(arms, plan_module_from(opts)) do
      emit_int_switch_chain(subject_s, arms, default_id, opts)
    else
      emit_int_c_switch_table(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_int_c_switch_table(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_int_c_switch_table(subject_s, arms, default_id, opts) do
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

  @spec emit_union_c_switch(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_union_c_switch(subject_s, arms, default_id, opts) do
    if duplicate_switch_arm_refs?(arms, plan_module_from(opts)) do
      emit_switch_tag_chain(subject_s, arms, default_id, opts)
    else
      emit_union_c_switch_table(subject_s, arms, default_id, opts)
    end
  end

  @spec emit_union_c_switch_table(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

  defp emit_union_c_switch_table(subject_s, arms, default_id, opts) do
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

  @spec plan_union_tag_expr(String.t()) :: String.t()

  defp plan_union_tag_expr(subject_s), do: union_tag_int_expr(subject_s)

  @spec union_tag_int_expr(String.t()) :: String.t()

  defp union_tag_int_expr(subject_s), do: "elmc_union_tag_as_int(#{subject_s})"

  @spec union_tag_int_switch?(list()) :: boolean()

  defp union_tag_int_switch?(arms) when is_list(arms) do
    opts = Process.get(:elmc_codegen_opts, %{})
    min_arms = SizeProfile.plan_union_tag_switch_min_arms(opts)

    length(arms) >= min_arms and SizeProfile.enum_tag_peel?(opts)
  end

  @spec emit_int_switch_chain(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

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

  @spec emit_switch_tag_chain(String.t(), [TagRefs.switch_arm()], non_neg_integer() | nil, keyword()) :: String.t()

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

  @spec join_switch_tag_arms([String.t()]) :: String.t()

  defp join_switch_tag_arms(lines) do
    lines
    |> Enum.intersperse("\nelse ")
    |> Enum.join("")
  end

  @spec wrap_shell(FunctionPlan.t(), String.t(), Types.slot_map()) :: String.t()

  defp wrap_shell(%FunctionPlan{} = plan, core, slots) do
    if Map.get(plan, :native_scalar_value_return) == true and owned_slot_count(slots) == 0 do
      String.trim(core)
    else
      wrap_rc_shell(plan, core, slots)
    end
  end

  @spec plan_rc_shell?(FunctionPlan.t()) :: boolean()
  defp plan_rc_shell?(%FunctionPlan{rc_required: true}), do: true

  defp plan_rc_shell?(%FunctionPlan{native_scalar_return: kind}),
    do: NativeReturn.dual_out?(kind)

  @spec wrap_rc_shell(FunctionPlan.t(), String.t(), Types.slot_map()) :: String.t()

  defp wrap_rc_shell(%FunctionPlan{fallible: fallible?} = plan, core, slots) do
    rc? = plan_rc_shell?(plan)
    slot_count = owned_slot_count(slots)
    owned = Frame.owned_declaration(plan, slots)
    slot_indices = if slot_count > 0, do: Enum.to_list(0..(slot_count - 1)), else: []

    epilogue =
      [RecordCompile.borrowed_owned_refs_null_stmt(), Frame.epilogue_release(slot_indices, slot_count)]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    letrec_decls = letrec_decl_lines(plan.letrec_refs || [])
    letrec_free = letrec_free_lines(plan.letrec_refs || [])

    # Dense boxed LUTs emit `CHECK_RC` without going through CFG fallible analysis.
    needs_catch? = rc? and (fallible? or String.contains?(core, "CHECK_RC("))

    ast =
      Ast.rc_fn(
        rc?: rc?,
        owned_decl: owned,
        owned_count: slot_count,
        needs_catch: needs_catch?,
        body: core,
        letrec_decls: letrec_decls,
        letrec_free: letrec_free,
        epilogue: epilogue
      )

    :ok = Lint.run!(ast)
    Emit.to_c(ast)
  end

  @spec borrow_null_cleanup_lines([String.t()]) :: String.t()

  defp borrow_null_cleanup_lines([]), do: ""

  defp borrow_null_cleanup_lines(nulls) do
    nulls
    |> Enum.map(&"    #{&1}")
    |> Enum.join("\n")
  end

  @spec emit_borrow_param_nulls(FunctionPlan.t(), Types.slot_map()) :: [String.t()]

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
  @spec prepared_owned_slots(FunctionPlan.t(), keyword()) :: {Types.slot_map(), non_neg_integer()}
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

  @spec prepare_owned_slots_map(FunctionPlan.t(), keyword()) :: Types.slot_map()

  defp prepare_owned_slots_map(%FunctionPlan{} = plan, opts \\ []) do
    param_kinds = param_kinds_for_plan(plan)
    decl_map = Process.get(:elmc_program_decls, %{})
    {slots, _} = Plan.allocate_slots(plan)

    closure_mode = Keyword.get(opts, :closure_mode)

    {borrow_param_regs, slots} =
      allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, closure_mode)

    closure_borrow_regs = build_closure_borrow_regs(plan, closure_mode)

    const_c_expr_regs = build_const_c_expr_regs(plan)
    fusion_native_literal_regs = build_fusion_native_literal_regs(plan)
    native_scalar_out = Map.get(plan, :native_scalar_return)
    ret_reg = ret_source_reg(plan)

    native_int_only_regs = build_native_int_only_regs(plan, decl_map)
    native_int_only_regs =
      maybe_add_native_ret_reg(native_int_only_regs, plan, ret_reg, native_scalar_out)

    {native_int_regs, slots} =
      allocate_native_int_param_slots(
        plan,
        slots,
        param_kinds,
        decl_map,
        closure_mode,
        native_int_only_regs
      )

    boxed_uses = boxed_use_regs(plan, decl_map)

    const_int_defs =
      boxed_uses
      |> Enum.filter(fn reg ->
        match?(%{op: :const_int}, plan_defining_instr(plan, reg))
      end)
      |> MapSet.new()

    native_int_owned_regs =
      native_int_only_regs
      |> MapSet.intersection(const_int_defs)
      |> MapSet.difference(MapSet.new(Map.keys(const_c_expr_regs)))

    native_int_only_regs = MapSet.difference(native_int_only_regs, native_int_owned_regs)

    unused_native_int_skip_regs = build_unused_native_int_skip_regs(plan, native_int_only_regs)

    forward_ref_value_regs = forward_ref_value_regs(plan)
    native_int_only_regs = MapSet.difference(native_int_only_regs, forward_ref_value_regs)

    tail_inline_skip_regs =
      plan
      |> build_tail_inline_skip_regs()
      |> MapSet.union(build_record_param_inline_skip_regs(plan, param_kinds))
      |> MapSet.union(build_unused_boxed_param_skip_regs(plan, param_kinds))
      |> MapSet.union(build_overwritten_inline_skip_regs(plan))
      |> MapSet.union(unused_native_int_skip_regs)
      |> MapSet.difference(forward_ref_value_regs)

    slots = Map.drop(slots, MapSet.to_list(tail_inline_skip_regs))

    native_bool_only_regs =
      build_native_bool_only_regs(plan, decl_map)
      |> MapSet.difference(native_int_only_regs)
      |> maybe_add_native_scalar_ret_bool_reg(ret_reg, native_scalar_out)

    slots =
      finalize_owned_slots_map(
        plan,
        slots,
        MapSet.difference(native_int_only_regs, native_int_owned_regs),
        native_bool_only_regs,
        fusion_native_literal_regs
      )

    skip_fill =
      MapSet.difference(native_int_only_regs, native_int_owned_regs)
      |> MapSet.union(native_bool_only_regs)
      |> MapSet.union(fusion_native_literal_regs)
      |> MapSet.union(tail_inline_skip_regs)
      |> MapSet.union(MapSet.new(Map.keys(native_int_regs)))
      |> MapSet.union(MapSet.new(Map.keys(borrow_param_regs)))
      |> MapSet.union(closure_borrow_regs)
      |> MapSet.difference(forward_ref_value_regs)

    fill_missing_owned_slots(plan, slots, skip_fill)
  end

  @spec emit_return(FunctionPlan.t(), Types.slot_map(), atom() | term(), [String.t()], keyword()) :: String.t()

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

    EphemeralBox.non_rc_scalar_return("elmc_new_int", src, slot_count)
  end

  defp emit_return(%FunctionPlan{rc_required: false, blocks: blocks} = plan, slots, :native_bool, _borrow_nulls, instr_opts) do
    reg = native_ret_reg(plan, blocks)
    slot_count = owned_slot_count(slots)

    src =
      case reg do
        r when is_integer(r) -> native_bool_result_ref(r, instr_opts)
        _ -> "false"
      end

    EphemeralBox.non_rc_scalar_return("elmc_new_bool", src, slot_count)
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

  defp emit_return(%FunctionPlan{} = _plan, _slots, :native_int_pair, _borrow_nulls, _instr_opts) do
    # Each contributing `tuple2` / `tuple2_ints` writes `*out0`/`*out1` in the
    # body (including switch/case arms). A join-only write would reuse the first
    # arm's constants for every branch.
    ""
  end

  defp emit_return(%FunctionPlan{} = _plan, _slots, :native_list_int_pair, _borrow_nulls, _instr_opts) do
    # Each contributing `tuple2` writes `*out_list`/`*out_int` in the body
    # (including direct `:fn_out` and phi arms).
    ""
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

        native_bool? =
          MapSet.member?(Keyword.get(instr_opts, :native_bool_only_regs, MapSet.new()), reg)

        cond do
          native_int? ->
            src = native_int_result_ref(reg, slots, instr_opts)
            EphemeralBox.non_rc_scalar_return("elmc_new_int", src, slot_count)

          native_bool? ->
            src = native_bool_result_ref(reg, instr_opts)
            EphemeralBox.non_rc_scalar_return("elmc_new_bool", src, slot_count)

          true ->
            ref = slot_ref(reg, slots, instr_opts)

            case Map.get(slots, reg) do
              idx when is_integer(idx) and slot_count > 0 ->
                borrow_cleanup =
                  borrow_nulls
                  |> Enum.reject(&(&1 == "owned[#{idx}] = NULL;"))
                  |> borrow_null_cleanup_lines()

                """
                {
                  ElmcValue *__ret = #{ref};
                  elmc_owned_null_aliases(owned, #{slot_count}, __ret);
                  #{borrow_cleanup}
                  elmc_release_array_lifo(owned, #{slot_count});
                  return __ret;
                }
                """
                |> String.trim()

              _ when slot_count > 0 ->
                # Borrowed param/capture return: caller owns the result.
                """
                {
                  ElmcValue *__ret = elmc_retain(#{ref});
                  #{borrow_cleanup}
                  elmc_release_array_lifo(owned, #{slot_count});
                  return __ret;
                }
                """
                |> String.trim()

              _ ->
                # Identity / passthrough closures (e.g. Array.initialize identity).
                "return elmc_retain(#{ref});"
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

  defp emit_return(%FunctionPlan{stream_mode: true, blocks: blocks}, _slots, _, _borrow_nulls, _instr_opts) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :stream_void}} -> ""
      _ -> ""
    end
  end

  defp emit_return(%FunctionPlan{blocks: blocks}, slots, _, _borrow_nulls, instr_opts) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        ""

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        case Map.get(slots, reg) do
          i when is_integer(i) ->
            slot_count = owned_slot_count(slots)

            """
            *out = #{slot_ref(reg, slots, instr_opts)};
            elmc_owned_null_aliases(owned, #{slot_count}, *out);
            """

          nil ->
            "*out = #{slot_ref(reg, slots, instr_opts)};"
        end

      _ ->
        "*out = elmc_int_zero();"
    end
  end

  @spec native_ret_reg(FunctionPlan.t() | term(), [Block.t()]) :: Types.reg() | nil

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

  @spec slot_ref(Types.reg(), Types.slot_map(), keyword()) :: String.t()

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

  @spec owned_slot_count(map()) :: non_neg_integer()
  def owned_slot_count(slots) when is_map(slots) do
    case Map.values(slots) do
      [] -> 0
      values -> Enum.max(values) + 1
    end
  end

  @spec finalize_owned_slots_map(FunctionPlan.t(), Types.slot_map(), MapSet.t(Types.reg()), MapSet.t(Types.reg()), MapSet.t(Types.reg())) :: Types.slot_map()

  defp finalize_owned_slots_map(%FunctionPlan{} = plan, slots, native_int_only_regs, native_bool_only_regs, fusion_native_literal_regs) do
    slots
    |> then(&drop_undef_slot_regs(plan, &1))
    |> Map.drop(MapSet.to_list(native_int_only_regs))
    |> Map.drop(MapSet.to_list(native_bool_only_regs))
    |> Map.drop(MapSet.to_list(fusion_native_literal_regs))
    |> compact_slots()
  end

  @spec fill_missing_owned_slots(FunctionPlan.t(), Types.slot_map(), MapSet.t(Types.reg())) :: Types.slot_map()

  defp fill_missing_owned_slots(%FunctionPlan{} = plan, slots, skip_regs) do
    defined = all_def_regs(plan)
    next = owned_slot_count(slots)

    {slots, _} =
      defined
      |> Enum.sort()
      |> Enum.reduce({slots, next}, fn reg, {acc, idx} ->
        cond do
          Map.has_key?(acc, reg) ->
            {acc, idx}

          MapSet.member?(skip_regs, reg) ->
            {acc, idx}

          true ->
            {Map.put(acc, reg, idx), idx + 1}
        end
      end)

    slots
  end

  @spec build_fusion_native_literal_regs(FunctionPlan.t()) :: MapSet.t(Types.reg())

  defp build_fusion_native_literal_regs(%FunctionPlan{} = plan) do
    plan
    |> build_const_int_regs()
    |> Map.keys()
    |> Enum.filter(&fusion_native_literal_reg?(plan, &1))
    |> MapSet.new()
  end

  @spec fusion_native_literal_reg?(FunctionPlan.t(), Types.reg()) :: boolean()

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

  @spec fusion_native_literal_consumer?(Types.t() | map() | term(), Types.reg() | term()) :: boolean()

  defp fusion_native_literal_consumer?(%{op: :call_fn, args: %{module: mod, name: name, args: args}}, reg) do
    case Fusion.rc_native_fusion_arg_kinds({mod, name}) do
      kinds when is_list(kinds) ->
        Enum.zip(args, kinds) |> Enum.any?(fn {r, k} -> r == reg and k in [:native_int, :boxed_int_tag] end)

      _ ->
        false
    end
  end

  defp fusion_native_literal_consumer?(_, _), do: false

  @spec drop_undef_slot_regs(FunctionPlan.t(), Types.slot_map()) :: Types.slot_map()

  defp drop_undef_slot_regs(%FunctionPlan{} = plan, slots) do
    defined = MapSet.new(all_def_regs(plan))

    Map.filter(slots, fn {reg, _} ->
      MapSet.member?(defined, reg)
    end)
  end

  @spec lookup_decl(String.t(), String.t()) :: Types.decl() | nil

  defp lookup_decl(module, name) do
    Process.get(:elmc_program_decls, %{})
    |> Map.get({module, name})
  end

  @spec param_names(list()) :: [String.t()]

  defp param_names(params) when is_list(params) do
    Enum.map(params, fn
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> "_"
    end)
  end

  @spec boxed_direct_scene_argv?(FunctionPlan.t(), Types.decl_map()) :: boolean()

  defp boxed_direct_scene_argv?(_plan, _decl_map) do
    Process.get(:elmc_direct_scene_writer) == true and
      Process.get(:elmc_direct_scene_boxed_argv) == true
  end

  @spec param_kinds_for_plan(FunctionPlan.t()) :: [atom()]

  defp param_kinds_for_plan(%FunctionPlan{} = plan) do
    decl = lookup_decl(plan.module, plan.name)
    decl_map = Process.get(:elmc_program_decls, %{})

    effective_decl =
      if decl do
        Map.put(decl, :args, FunctionEmit.effective_decl_args(decl, plan.module, decl_map))
      end

    cond do
      # Scene-stream `*_commands_append` bodies use CommandDef arg kinds (Int params
      # as native_int) even when the argv wrapper is still boxed `ElmcValue *`.
      effective_decl && Process.get(:elmc_direct_scene_writer) == true ->
        CommandDef.arg_kinds(effective_decl)

      effective_decl && FunctionEmit.mixed_direct_abi?(effective_decl, plan.module, decl_map) ->
        NativeFunctionCall.arg_kinds(effective_decl, plan.module, decl_map)

      true ->
        List.duplicate(:boxed, length(plan.params))
    end
  end

  @spec allocate_native_int_param_slots(
          FunctionPlan.t(),
          Types.slot_map(),
          [atom()],
          Types.decl_map(),
          map() | nil,
          MapSet.t(Types.reg())
        ) :: {%{Types.reg() => String.t()}, Types.slot_map()}

  defp allocate_native_int_param_slots(
         plan,
         slots,
         param_kinds,
         decl_map,
         closure_mode,
         _native_int_only_regs
       ) do
    all_native_int_regs =
      build_native_int_param_regs(plan, param_kinds, decl_map, closure_mode)

    # Native-int params are always the C `elmc_int_t` argument — never materialize
    # `elmc_new_int(&owned[i], param)` at `load_param`. Borrowed heap uses peel via
    # Ephemeral int boxing (or a `*_int` runtime ABI); consuming uses materialize
    # an ephemeral box at the call site. Boxing here was dead whenever
    # `boxed_value_ref` peeled via `native_param_c_ref` (e.g. `list_nth_maybe` index).
    pure_native_param_regs = Map.keys(all_native_int_regs)

    slots = Map.drop(slots, pure_native_param_regs)
    {Map.take(all_native_int_regs, pure_native_param_regs), slots}
  end

  @spec build_tail_inline_skip_regs(FunctionPlan.t()) :: MapSet.t(Types.reg())

  defp build_tail_inline_skip_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(&tail_inline_skip_operand_regs(plan, &1))
    |> MapSet.new()
  end

  @spec build_overwritten_inline_skip_regs(FunctionPlan.t()) :: MapSet.t(Types.reg())

  defp build_overwritten_inline_skip_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(fn block ->
      Optimize.unread_overwritten_dest_regs(block.instrs, block.terminator)
      |> MapSet.to_list()
    end)
    |> MapSet.new()
  end

  @spec build_record_param_inline_skip_regs(FunctionPlan.t(), [atom()]) :: MapSet.t(Types.reg())

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

  @spec build_unused_native_int_skip_regs(FunctionPlan.t(), MapSet.t(Types.reg())) :: MapSet.t(Types.reg())

  defp build_unused_native_int_skip_regs(%FunctionPlan{} = plan, native_int_only_regs) do
    native_int_only_regs
    |> MapSet.to_list()
    |> Enum.filter(&unused_native_int_copy_reg?(plan, &1))
    |> MapSet.new()
  end

  @spec unused_native_int_copy_reg?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp unused_native_int_copy_reg?(plan, reg) do
    not direct_native_publish?(plan, reg) and
      not native_int_phi_operand?(plan, reg) and
      dead_native_int_copy_def?(plan, reg) and
      native_int_boxed_copy_only?(plan, reg)
  end

  @spec dead_native_int_copy_def?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp dead_native_int_copy_def?(plan, reg) do
    case plan_defining_instr(plan, reg) do
      %{op: :call_runtime, args: %{builtin: :retain}} ->
        true

      %{op: :load_local} ->
        true

      %{op: :int_arith, args: args} ->
        # Only identity copies (`x+0`/`x-0`). Skipping real arith whose sole use is
        # tuple2/record still runs emit_null_consumed on boxed operands, then the
        # use site reconstructs via as_int(owned[i]) on a freed slot (EscapeDict
        # map values became `0+1`).
        native_int_identity_source(args) != nil

      _ ->
        false
    end
  end

  @spec native_int_identity_source(map() | term()) :: Types.reg() | nil

  defp native_int_identity_source(%{kind: :add_const, lhs: lhs, value: 0}), do: lhs
  defp native_int_identity_source(%{kind: :sub_const, lhs: lhs, value: 0}), do: lhs
  defp native_int_identity_source(_), do: nil

  @spec native_int_boxed_copy_only?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp native_int_boxed_copy_only?(plan, reg) do
    sites = native_int_reg_use_sites(plan, reg)
    sites != [] and Enum.all?(sites, &boxed_aggregate_copy_instr?/1)
  end

  defp boxed_aggregate_copy_instr?(%{op: :const_static_list}), do: true

  defp boxed_aggregate_copy_instr?(instr), do: boxed_record_tuple_builtin_instr?(instr)

  @spec native_int_reg_use_sites(FunctionPlan.t(), Types.reg()) :: [Types.t() | map()]

  defp native_int_reg_use_sites(plan, reg) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(fn instr ->
      instr
      |> plan_value_operand_regs()
      |> Enum.member?(reg)
    end)
  end

  @spec boxed_record_tuple_builtin_instr?(map() | term()) :: boolean()

  defp boxed_record_tuple_builtin_instr?(%{op: :call_runtime, args: %{builtin: builtin}})
       when builtin in [:record_new, :record_new_take, :tuple2, :tuple2_take],
       do: true

  defp boxed_record_tuple_builtin_instr?(_), do: false

  @spec plan_value_operand_regs(Types.t() | map() | term()) :: [Types.reg()]

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

  defp plan_value_operand_regs(%{op: :const_static_list, args: %{regs: regs}}) when is_list(regs),
       do: regs

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

  @spec native_int_phi_operand?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp native_int_phi_operand?(plan, reg) do
    Enum.any?(plan.blocks, fn %{instrs: instrs} ->
      Enum.any?(instrs, fn
        %{op: :phi, args: %{then: ^reg}} -> true
        %{op: :phi, args: %{else: ^reg}} -> true
        _ -> false
      end)
    end)
  end

  @spec build_unused_boxed_param_skip_regs(FunctionPlan.t(), [atom()]) :: MapSet.t(Types.reg())

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

  @spec record_consume_regs(FunctionPlan.t()) :: MapSet.t(Types.reg())

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

  @spec boxed_param_new_int_root(FunctionPlan.t() | term(), Types.reg() | term(), [atom()] | term(), [String.t()] | term()) :: {:param, non_neg_integer()} | Types.reg() | boolean() | nil

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

  @spec native_param_c_expr?(String.t(), [atom()], [String.t()]) :: boolean()

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

  @spec native_param_reg?(FunctionPlan.t(), Types.reg(), [atom()]) :: boolean()

  defp native_param_reg?(plan, reg, param_kinds) do
    case plan_defining_instr(plan, reg) do
      %{op: :load_param, args: %{index: index}} ->
        Enum.at(param_kinds, index) == :native_int

      _ ->
        false
    end
  end

  @spec reg_operand_uses_subset?(FunctionPlan.t(), Types.reg(), MapSet.t(Types.reg())) :: boolean()

  defp reg_operand_uses_subset?(plan, reg, allowed) do
    uses = plan_operand_use_regs(plan, reg)

    uses != [] and Enum.all?(uses, &MapSet.member?(allowed, &1))
  end

  @spec plan_operand_use_regs(FunctionPlan.t(), Types.reg()) :: [Types.reg()]

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

  @spec plan_instr_operand_regs(Types.t() | map() | term()) :: [Types.reg()]

  defp plan_instr_operand_regs(%{op: :phi, args: args}) when is_map(args) do
    [Map.get(args, :then), Map.get(args, :else), Map.get(args, :cond)]
    |> Enum.filter(&is_integer/1)
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

  @spec tail_inline_skip_operand_regs(FunctionPlan.t(), Types.t() | map()) :: [Types.reg()]

  defp tail_inline_skip_operand_regs(plan, %{
         op: :call_runtime,
         dest: dest,
         args: %{builtin: builtin, args: args}
       })
       when builtin in [:tuple2, :tuple2_take] and dest in [:fn_out, :branch_out] do
    Enum.filter(args, &tail_inline_operand?(plan, &1))
  end

  defp tail_inline_skip_operand_regs(_plan, _instr), do: []

  @spec tail_inline_operand?(FunctionPlan.t(), Types.reg()) :: boolean()

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

  @spec plan_defining_instr(FunctionPlan.t() | map() | term(), Types.reg() | Types.result_slot() | term()) :: Types.t() | nil

  defp plan_defining_instr(%FunctionPlan{blocks: blocks}, reg)
       when is_integer(reg) or reg in [:fn_out, :branch_out] do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  defp plan_defining_instr(_, _), do: nil

  @spec allocate_borrow_param_direct_slots(FunctionPlan.t(), Types.slot_map(), [atom()], Types.decl_map(), map() | nil) :: {%{Types.reg() => String.t()}, Types.slot_map()}

  defp allocate_borrow_param_direct_slots(plan, slots, param_kinds, _decl_map, %{capture_count: cap_n})
       when is_integer(cap_n) do
    borrow_regs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))
      |> Enum.map(fn %{dest: reg, args: %{index: index}} -> {reg, index} end)
      |> Enum.uniq_by(fn {reg, _} -> reg end)
      |> Enum.filter(fn {_reg, index} ->
        Enum.at(param_kinds, index, :boxed) == :boxed
      end)
      |> Map.new(fn {reg, index} ->
        {reg, closure_param_c_ref(index, cap_n)}
      end)

    slots = Map.drop(slots, Map.keys(borrow_regs))
    {borrow_regs, slots}
  end

  defp allocate_borrow_param_direct_slots(plan, slots, param_kinds, decl_map, _closure_mode) do
    allocate_borrow_param_direct_slots_impl(plan, slots, param_kinds, decl_map)
  end

  @spec build_closure_borrow_regs(FunctionPlan.t(), map() | nil) :: MapSet.t(Types.reg())

  defp build_closure_borrow_regs(plan, %{capture_count: cap_n}) when is_integer(cap_n) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&(&1.op == :load_param))
    |> Enum.map(fn %{dest: reg} -> reg end)
    |> MapSet.new()
  end

  defp build_closure_borrow_regs(_plan, _closure_mode), do: MapSet.new()

  @spec allocate_borrow_param_direct_slots_impl(FunctionPlan.t(), Types.slot_map(), [atom()], Types.decl_map()) :: {%{Types.reg() => String.t()}, Types.slot_map()}

  defp allocate_borrow_param_direct_slots_impl(plan, slots, param_kinds, decl_map) do
    decl = lookup_decl(plan.module, plan.name)

    if borrow_param_direct_enabled?(decl || %{}) or retain_arg_borrow_direct_enabled?(decl || %{}) do
      borrow_regs = build_borrow_param_regs(plan, param_kinds, decl_map)
      needs_owned = param_regs_needing_owned_retain(plan, Map.keys(borrow_regs))
      direct_regs = Map.drop(borrow_regs, MapSet.to_list(needs_owned))
      slots = Map.drop(slots, Map.keys(direct_regs))
      {direct_regs, slots}
    else
      {%{}, slots}
    end
  end

  @spec retain_arg_borrow_direct_enabled?(Types.decl()) :: boolean()

  defp retain_arg_borrow_direct_enabled?(decl) do
    :retain_arg in List.wrap(Map.get(decl, :ownership, []))
  end

  @spec borrow_param_direct_enabled?(Types.decl()) :: boolean()

  defp borrow_param_direct_enabled?(decl) do
    ownership = List.wrap(Map.get(decl, :ownership, []))
    :retain_arg not in ownership and (:borrow_arg in ownership or ownership == [])
  end

  # Borrowed boxed params can use the C argument directly when the plan never
  # reassigns that param register (for example thin delegates, or read-only borrows).
  # When the register is reused after `case`/`::` destructuring, load_param keeps
  # an owned scratch slot so the same reg can hold derived values later.
  @spec param_regs_needing_owned_copy(FunctionPlan.t(), [Types.reg()]) :: MapSet.t(Types.reg())

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

  @spec param_regs_needing_owned_retain(FunctionPlan.t(), [Types.reg()]) :: MapSet.t(Types.reg())

  defp param_regs_needing_owned_retain(plan, param_regs) when is_list(param_regs) do
    param_set = MapSet.new(param_regs)

    consumed =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.flat_map(fn
        %{effects: %{consumes: consumes}} when is_list(consumes) ->
          Enum.filter(consumes, &MapSet.member?(param_set, &1))

        _ ->
          []
      end)
      |> MapSet.new()

    MapSet.union(consumed, param_regs_needing_owned_copy(plan, param_regs))
  end

  @spec build_borrow_param_regs(FunctionPlan.t(), [atom()], Types.decl_map()) :: %{Types.reg() => String.t()}

  defp build_borrow_param_regs(plan, param_kinds, decl_map) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&(&1.op == :load_param))
    |> Enum.map(fn %{dest: reg, args: %{index: index}} -> {reg, index} end)
    |> Enum.uniq_by(fn {reg, _} -> reg end)
    |> Enum.filter(fn {_reg, index} -> Enum.at(param_kinds, index) == :boxed end)
    |> Map.new(fn {reg, index} ->
      {reg, plan_decl_param_c_arg(plan, index, decl_map)}
    end)
  end

  @spec build_native_int_param_regs(FunctionPlan.t(), [atom()], Types.decl_map(), map() | nil) :: %{Types.reg() => String.t()}

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

  @spec plan_native_int_param_c_ref(FunctionPlan.t(), non_neg_integer(), Types.decl_map(), map() | nil) :: String.t()

  defp plan_native_int_param_c_ref(plan, index, decl_map, closure_mode) do
    case closure_mode do
      %{capture_count: cap} when is_integer(cap) ->
        closure_native_int_param_ref(index, cap)

      _ ->
        plan_decl_param_c_arg(plan, index, decl_map)
    end
  end

  @spec plan_decl_param_c_arg(FunctionPlan.t(), non_neg_integer(), Types.decl_map()) :: String.t()

  defp plan_decl_param_c_arg(plan, index, _decl_map) do
    names = param_names(plan.params)

    names =
      if names != [] do
        names
      else
        case lookup_decl(plan.module, plan.name) do
          %{args: args} when is_list(args) -> decl_arg_names(args)
          _ -> []
        end
      end

    FunctionCallAbi.param_c_arg(index, names)
  end

  @spec closure_param_c_ref(non_neg_integer(), non_neg_integer()) :: String.t()

  defp closure_param_c_ref(index, capture_count) when index < capture_count do
    "captures[#{index}]"
  end

  defp closure_param_c_ref(index, capture_count) do
    arg_i = index - capture_count
    "(argc > #{arg_i} ? args[#{arg_i}] : NULL)"
  end

  @doc false
  @spec closure_native_int_param_ref(non_neg_integer(), non_neg_integer()) :: String.t()

  def closure_native_int_param_ref(index, capture_count) when index < capture_count do
    "elmc_as_int(captures[#{index}])"
  end

  def closure_native_int_param_ref(index, capture_count) do
    arg_i = index - capture_count
    "elmc_as_int((argc > #{arg_i} ? args[#{arg_i}] : NULL))"
  end

  @spec decl_arg_names(list()) :: [String.t()]

  defp decl_arg_names(args) do
    Enum.map(args, fn
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> "_"
    end)
  end

  @spec build_const_int_regs(FunctionPlan.t()) :: %{Types.reg() => term()}

  defp build_const_int_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :const_int, dest: reg, args: %{value: value} = args} when is_integer(reg) ->
        [{reg, {value, Map.get(args, :union_ctor), Map.get(args, :bool_lit) == true}}]

      %{op: :call_runtime, dest: reg, args: %{builtin: :new_int, literal: value}}
      when is_integer(reg) and is_integer(value) ->
        [{reg, {value, nil}}]

      _ ->
        []
    end)
    |> single_def_const_int_entries(plan)
    |> Map.new()
  end

  @spec single_def_const_int_entries(list(), FunctionPlan.t()) :: list()
  defp single_def_const_int_entries(entries, plan) do
    entries
    |> Enum.group_by(fn {reg, _} -> reg end)
    |> Enum.flat_map(fn
      # One const_int is not enough: branch joins reuse the same dest for
      # `int_arith` / other defs (`Ready -> cursor+cmd; _ -> -1`). Treating that
      # reg as a literal `"-1"` makes native stores into a non-lvalue and drops
      # the success arm (fallthrough always yields -1).
      {reg, [single]} when is_integer(reg) ->
        if length(all_defining_instrs(plan, reg)) == 1, do: [single], else: []

      {_reg, _multiple} ->
        []
    end)
  end

  @spec build_const_c_expr_regs(FunctionPlan.t()) :: %{Types.reg() => String.t()}

  defp build_const_c_expr_regs(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(&(&1.op == :const_c_expr))
    |> Enum.group_by(& &1.dest)
    |> Enum.flat_map(fn
      {reg, [%{args: %{value: value}}]} -> [{reg, value}]
      {_reg, _multiple} -> []
    end)
    |> Map.new()
  end

  @spec build_native_int_only_regs(FunctionPlan.t(), Types.decl_map()) :: MapSet.t(Types.reg())

  defp build_native_int_only_regs(%FunctionPlan{} = plan, decl_map) do
    _ = native_publish_reach_set(plan)
    expand_native_int_regs(plan, decl_map, MapSet.new(), 0)
  end

  @spec build_native_pair_component_regs(FunctionPlan.t()) :: %{Types.reg() => String.t()}

  defp build_native_pair_component_regs(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :call_fn, dest: dest, args: %{native_pair_out: {first, second}}}
      when is_integer(dest) and is_integer(first) and is_integer(second) ->
        [
          {first, "plan_native_pair_#{dest}_0"},
          {second, "plan_native_pair_#{dest}_1"}
        ]

      _ ->
        []
    end)
    |> Map.new()
  end

  @spec build_native_list_int_pair_int_regs(FunctionPlan.t()) :: %{Types.reg() => String.t()}

  defp build_native_list_int_pair_int_regs(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: :call_fn, dest: dest, args: %{native_list_int_pair_out: int_reg}}
      when is_integer(dest) and is_integer(int_reg) ->
        [{int_reg, "plan_list_int_pair_#{dest}_int"}]

      _ ->
        []
    end)
    |> Map.new()
  end

  @spec expand_native_int_regs(FunctionPlan.t(), Types.decl_map(), MapSet.t(Types.reg()), non_neg_integer()) :: MapSet.t(Types.reg())

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

  @spec native_int_decl_lines(%{Types.reg() => String.t()}, MapSet.t(Types.reg())) :: [String.t()]

  defp native_int_decl_lines(native_int_locals, native_int_mutable_regs) do
    native_int_mutable_regs
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.filter(&Map.has_key?(native_int_locals, &1))
    |> Enum.map(fn reg ->
      name = Map.fetch!(native_int_locals, reg)
      # unused attr: plan-state cross-block analysis can hoist a local that emit
      # later folds away; Pebble builds use -Werror=unused-but-set-variable.
      "elmc_int_t #{name} __attribute__((unused)) = 0;"
    end)
  end

  # Mutable lvalue required for RC `elmc_int_t *out` callees (`&plan_native_int_N`),
  # multiple defining instrs (reassign / non-SSA merge), plan-state `switch` emit,
  # or a use (including native_int_phi shape operands) in a block other than the
  # def. Goto CFG labels share one C scope: `if (c) goto join; const x = …; join:
  # use(x)` is `-Wmaybe-uninitialized` even when the use is under a ternary that
  # is dynamically dead on the skip path (game-jump-n-run `plan_native_int_131`).
  @spec native_int_needs_mutable_local?(FunctionPlan.t(), Types.reg(), Types.decl_map()) :: boolean()

  defp native_int_needs_mutable_local?(plan, reg, decl_map) do
    defs = all_defining_instrs(plan, reg)

    length(defs) > 1 or Enum.any?(defs, &native_int_rc_out_param_def?(&1, decl_map, plan)) or
      state_switch_emit?(plan) or native_int_cross_block_use?(plan, reg)
  end

  @spec native_bool_needs_mutable_local?(FunctionPlan.t(), Types.reg(), Types.decl_map()) :: boolean()

  defp native_bool_needs_mutable_local?(plan, reg, decl_map) do
    defs = all_defining_instrs(plan, reg)

    length(defs) > 1 or Enum.any?(defs, &native_bool_rc_out_param_def?(&1, decl_map, plan)) or
      state_switch_emit?(plan) or native_bool_cross_block_use?(plan, reg)
  end

  @spec native_int_cross_block_use?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp native_int_cross_block_use?(%FunctionPlan{} = plan, reg) do
    case defining_block_id(plan, reg) do
      nil ->
        false

      def_id ->
        Enum.any?(native_scalar_use_block_ids(plan, reg), &(&1 != def_id))
    end
  end

  @spec native_bool_cross_block_use?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp native_bool_cross_block_use?(%FunctionPlan{} = plan, reg) do
    case defining_block_id(plan, reg) do
      nil ->
        false

      def_id ->
        Enum.any?(native_scalar_use_block_ids(plan, reg), &(&1 != def_id))
    end
  end

  @spec defining_block_id(FunctionPlan.t(), Types.reg()) :: non_neg_integer() | nil

  defp defining_block_id(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{id: id, instrs: instrs} ->
      if Enum.any?(instrs, &defining_reg?(&1, reg)), do: id
    end)
  end

  @spec native_scalar_use_block_ids(FunctionPlan.t(), Types.reg()) :: [non_neg_integer()]

  defp native_scalar_use_block_ids(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    Enum.flat_map(blocks, fn %{id: id, instrs: instrs} ->
      if Enum.any?(instrs, &native_scalar_instr_uses_reg?(&1, reg)), do: [id], else: []
    end)
  end

  @spec native_scalar_instr_uses_reg?(Types.t() | map(), Types.reg()) :: boolean()

  defp native_scalar_instr_uses_reg?(instr, reg) do
    reg in plan_value_operand_regs(instr) or phi_shape_uses_reg?(instr, reg)
  end

  @spec phi_shape_uses_reg?(Types.t() | map(), Types.reg()) :: boolean()

  defp phi_shape_uses_reg?(%{op: :phi, args: args}, reg) when is_map(args) do
    (Map.get(args, :native_int_phi) == true or Map.get(args, :truthy_native) == true) and
      (reg in phi_shape_regs(Map.get(args, :then_shape)) or
         reg in phi_shape_regs(Map.get(args, :else_shape)))
  end

  defp phi_shape_uses_reg?(_, _), do: false

  @spec phi_shape_regs(term()) :: [Types.reg()]

  defp phi_shape_regs({:int_arith, args}) when is_map(args) do
    [:lhs, :rhs, :base, :value]
    |> Enum.map(&Map.get(args, &1))
    |> Enum.filter(&is_integer/1)
  end

  defp phi_shape_regs({:compare, _kind, left, right}) do
    Enum.filter([left, right], &is_integer/1)
  end

  defp phi_shape_regs({:reg, reg}) when is_integer(reg), do: [reg]
  defp phi_shape_regs(_), do: []

  defp native_int_rc_out_param_def?(%{op: :call_fn, args: %{module: mod, name: name}}, decl_map, plan)
       when is_binary(mod) and is_binary(name) do
    NativeReturn.cached_kind({mod, name}) == :native_int and
      not NativeReturn.value_return?({mod, name}) and
      not native_boxed_rc_out_callee?(mod, name, decl_map) and
      (RcRequired.rc_required?(mod, name) or native_scalar_self_rc_out?(plan, mod, name))
  end

  defp native_int_rc_out_param_def?(_, _, _), do: false

  defp native_bool_rc_out_param_def?(%{op: :call_fn, args: %{module: mod, name: name}}, decl_map, plan)
       when is_binary(mod) and is_binary(name) do
    NativeReturn.cached_kind({mod, name}) == :native_bool and
      not NativeReturn.value_return?({mod, name}) and
      not native_boxed_rc_out_callee?(mod, name, decl_map) and
      (RcRequired.rc_required?(mod, name) or native_scalar_self_rc_out?(plan, mod, name))
  end

  defp native_bool_rc_out_param_def?(_, _, _), do: false

  defp native_scalar_self_rc_out?(%FunctionPlan{module: mod, name: name, rc_required: true}, mod, name),
    do: true

  defp native_scalar_self_rc_out?(_, _, _), do: false

  @spec native_int_candidate?(FunctionPlan.t(), Types.reg(), Types.decl_map(), MapSet.t(Types.reg())) :: boolean()

  defp native_int_candidate?(plan, reg, decl_map, native_set) do
    case all_defining_instrs(plan, reg) do
      [] ->
        false

      [%{op: :const_int, args: %{bool_lit: true}} | _] ->
        false

      [%{op: op} | _] when op in [:const_int, :const_c_expr, :record_get_int, :int_arith, :boxed_tag_peel] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      # Only projections of `tuple2_ints` pairs are known Int elements. Nested
      # Dict/List tuple spines stay boxed (tag tests need ElmcValue*).
      [%{op: :tuple_proj, args: %{base: base}} | _] ->
        tuple2_ints_reg?(plan, base) and native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_runtime, args: %{builtin: :new_int, literal: value}} | _]
      when is_integer(value) ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_runtime, args: %{builtin: :int_list_head_int}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_runtime, args: %{builtin: :list_nth_int_at}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_runtime, args: %{builtin: :maybe_with_default_int}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_runtime, args: %{builtin: :string_length_boxed}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :call_fn, args: %{module: mod, name: name}} | _] ->
        NativeReturn.cached_kind({mod, name}) == :native_int and
          not native_boxed_rc_out_callee?(mod, name, decl_map) and
          native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :phi, args: %{native_int_phi: true}} | _] ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :phi, args: %{then: then_r, else: else_r}}] ->
        native_source?(plan, then_r, native_set) and native_source?(plan, else_r, native_set) and
          native_int_uses_only?(plan, reg, decl_map, native_set)

      [%{op: :load_param, args: %{index: index}} | _] ->
        load_param_native_int_candidate?(plan, reg, index, decl_map, native_set)

      retains ->
        retain_defs?(retains) and
          Enum.all?(retains, fn %{args: %{args: [src]}} ->
            native_source?(plan, src, native_set)
          end) and native_int_uses_only?(plan, reg, decl_map, native_set)
    end
  end

  # Boxed Int params (`ElmcValue *`) may still be native-int dests when every
  # use is a peel (`publish` to `elmc_int_t` return, arith, …). Treating them
  # as boxed owned writes `tmp_N = elmc_retain(x)` and never assigns
  # `plan_native_int_N` (identity `Int -> Int`).
  @spec load_param_native_int_candidate?(
          FunctionPlan.t(),
          Types.reg(),
          non_neg_integer(),
          Types.decl_map(),
          MapSet.t(Types.reg())
        ) :: boolean()

  defp load_param_native_int_candidate?(plan, reg, index, decl_map, native_set) do
    case Enum.at(param_kinds_for_plan(plan), index) do
      :native_int ->
        native_int_uses_only?(plan, reg, decl_map, native_set)

      _ ->
        Map.get(plan, :native_scalar_return) == :native_int and
          native_int_has_use?(plan, reg, decl_map, native_set) and
          native_int_uses_only?(plan, reg, decl_map, native_set)
    end
  end

  @spec native_int_has_use?(FunctionPlan.t(), Types.reg(), Types.decl_map(), MapSet.t(Types.reg())) ::
          boolean()

  defp native_int_has_use?(plan, reg, decl_map, native_set) do
    plan_use_refs(plan, reg, decl_map, native_set) != []
  end

  @spec retain_defs?([Types.t() | map()]) :: boolean()

  defp retain_defs?(instrs),
    do:
      instrs != [] and
        Enum.all?(instrs, &match?(%{op: :call_runtime, args: %{builtin: :retain, args: [_]}}, &1))

  @spec native_source?(FunctionPlan.t(), Types.reg(), MapSet.t(Types.reg())) :: boolean()

  defp native_source?(plan, reg, native_set) when is_integer(reg) do
    MapSet.member?(native_set, reg) or
      case defining_instr(plan, reg) do
        %{op: :load_param, args: %{index: index}} ->
          Enum.at(param_kinds_for_plan(plan), index) == :native_int

        %{op: :const_int, args: %{bool_lit: true}} ->
          false

        %{op: op} when op in [:const_int, :const_c_expr, :record_get_int, :int_arith, :boxed_tag_peel] ->
          true

        %{op: :tuple_proj, args: %{base: base}} ->
          tuple2_ints_reg?(plan, base)

        %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
          true

        %{op: :call_runtime, args: %{builtin: :int_list_head_int}} ->
          true

        %{op: :call_runtime, args: %{builtin: :list_nth_int_at}} ->
          true

        %{op: :call_runtime, args: %{builtin: :maybe_with_default_int}} ->
          true

        %{op: :call_runtime, args: %{builtin: :string_length_boxed}} ->
          true

        %{op: :phi, args: %{native_int_phi: true}} ->
          true

        %{op: :call_fn, args: %{module: mod, name: name}} ->
          NativeReturn.cached_kind({mod, name}) == :native_int and
            not native_boxed_rc_out_callee?(mod, name, Process.get(:elmc_program_decls, %{}))

        _ ->
          false
      end
  end

  defp native_boxed_rc_out_callee?(mod, name, decl_map) when is_binary(mod) and is_binary(name) do
    case Map.get(decl_map, {mod, name}) do
      %{__struct__: _} = decl ->
        NativeFunctionCall.native_boxed_rc_abi?(decl, mod, decl_map)

      decl when is_map(decl) ->
        NativeFunctionCall.native_boxed_rc_abi?(decl, mod, decl_map)

      _ ->
        false
    end
  end

  defp native_boxed_rc_out_callee?(_, _, _), do: false

  defp tuple2_ints_reg?(%FunctionPlan{} = plan, reg) when is_integer(reg) do
    match?(
      %{op: :call_runtime, args: %{builtin: :tuple2_ints}},
      defining_instr(plan, reg)
    )
  end

  defp tuple2_ints_reg?(_, _), do: false

  @doc false
  @spec all_defining_instrs(FunctionPlan.t(), non_neg_integer()) :: Types.instr_list()
  def all_defining_instrs(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.filter(fn
      %{dest: ^reg} -> true
      _ -> false
    end)
  end

  @spec all_def_regs(FunctionPlan.t()) :: [Types.reg()]

  defp all_def_regs(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{dest: reg} when is_integer(reg) -> [reg]
      _ -> []
    end)
    |> Enum.uniq()
  end

  @spec native_int_uses_only?(FunctionPlan.t(), Types.reg(), Types.decl_map(), MapSet.t(Types.reg())) :: boolean()

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

  @spec native_bool_mutable_decl_lines(%{Types.reg() => String.t()}, MapSet.t(Types.reg())) :: [String.t()]

  defp native_bool_mutable_decl_lines(native_bool_locals, native_bool_mutable_regs) do
    native_bool_mutable_regs
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(fn reg ->
      name = Map.fetch!(native_bool_locals, reg)
      "bool #{name} = false;"
    end)
  end

  @spec build_native_bool_only_regs(FunctionPlan.t(), Types.decl_map()) :: MapSet.t(Types.reg())

  defp build_native_bool_only_regs(%FunctionPlan{} = plan, decl_map) do
    expand_native_bool_regs(plan, decl_map, MapSet.new(), 0)
  end

  @spec expand_native_bool_regs(FunctionPlan.t(), Types.decl_map(), MapSet.t(Types.reg()), non_neg_integer()) :: MapSet.t(Types.reg())

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

  @spec native_bool_candidate?(FunctionPlan.t(), Types.reg(), Types.decl_map(), MapSet.t(Types.reg())) :: boolean()

  defp native_bool_candidate?(plan, reg, decl_map, native_bool_set) do
    case all_defining_instrs(plan, reg) do
      [%{op: op} | _]
      when op in [
             :compare,
             :bool_and,
             :test_maybe_nothing,
             :test_list_empty,
             :test_list_length_gte,
             :test_ctor_tag,
             :test_bool,
             :platform_static_bool
           ] ->
        native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      [%{op: :phi, args: %{truthy_native: true}} | _] ->
        native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      [%{op: :const_int, args: %{bool_lit: true}} | _] ->
        native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      [%{op: :call_fn, args: %{module: mod, name: name}} | _] ->
        NativeReturn.cached_kind({mod, name}) == :native_bool and
          not native_boxed_rc_out_callee?(mod, name, decl_map) and
          native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      [%{op: :phi, args: %{then: then_r, else: else_r}}] ->
        phi_truthy_native?(plan, then_r, else_r) and
          native_bool_uses_only?(plan, reg, decl_map, native_bool_set)

      _ ->
        false
    end
  end

  @spec phi_truthy_native?(FunctionPlan.t(), Types.reg(), Types.reg()) :: boolean()

  defp phi_truthy_native?(plan, then_r, else_r) do
    Elmc.Backend.Plan.TruthyNative.truthy_native_arm?(plan, then_r) and
      Elmc.Backend.Plan.TruthyNative.truthy_native_arm?(plan, else_r)
  end

  @spec native_bool_uses_only?(FunctionPlan.t(), Types.reg(), Types.decl_map(), MapSet.t(Types.reg())) :: boolean()

  defp native_bool_uses_only?(plan, reg, decl_map, native_bool_set) do
    use_kinds =
      plan_bool_use_refs(plan, reg, decl_map, native_bool_set)
      |> Enum.map(fn {kind, _} -> kind end)
      |> Enum.uniq()

    use_kinds == [] or Enum.all?(use_kinds, &(&1 == :native_bool_operand))
  end

  @spec plan_bool_use_refs(FunctionPlan.t(), Types.reg(), Types.decl_map(), MapSet.t(Types.reg())) :: [{atom(), Types.reg()}]

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

  @spec instr_bool_use_refs(Types.t() | map(), Types.reg(), Types.decl_map() | term(), MapSet.t(Types.reg()) | term()) :: [{atom(), Types.reg()}]

  defp instr_bool_use_refs(%{op: :phi, args: %{cond: cond, then: then_r, else: else_r} = args}, reg, _, _) do
    arm_kind = if Map.get(args, :truthy_native) == true, do: :native_bool_operand, else: :boxed

    []
    |> then(fn refs -> if cond == reg, do: [{:native_bool_operand, reg} | refs], else: refs end)
    |> then(fn refs -> if then_r == reg, do: [{arm_kind, reg} | refs], else: refs end)
    |> then(fn refs -> if else_r == reg, do: [{arm_kind, reg} | refs], else: refs end)
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
  @spec plan_use_refs(FunctionPlan.t(), non_neg_integer(), Types.function_decl_map(), MapSet.t()) :: [
          {:native_int_call | :native_operand | :boxed | :publish_fn_out, non_neg_integer()}
        ]
  def plan_use_refs(%FunctionPlan{} = plan, reg, decl_map, native_set) do
    # Seed once per plan: phi→publish reachability used by phi_operand_use_kind.
    # Without this, huge bool/if trees re-walk the CFG for every phi on every reg.
    _ = native_publish_reach_set(plan)

    Enum.flat_map(plan.blocks, fn %{instrs: instrs, terminator: term} ->
      instr_refs =
        instrs
        |> Enum.reject(fn instr -> instr.op in [:release, :catch_begin, :catch_end] end)
        |> Enum.reject(fn instr -> defining_reg?(instr, reg) end)
        |> Enum.flat_map(&instr_use_refs_for_reg(&1, reg, decl_map, native_set, plan))

      term_refs =
        case term do
          {:br_if, _, _, cond} when cond == reg ->
            [{:native_operand, reg}]

          {:switch_tag, subject, _, _} when subject == reg ->
            [{:native_operand, reg}]

          _ ->
            []
        end

      instr_refs ++ term_refs
    end)
  end

  # Only classify uses of `reg`. Phi arms are expensive (native_int_value_reg? +
  # publish reachability); evaluating both arms for every phi on every query was
  # O(phis × regs × CFG) and hung on RegisterExhaustion-scale || chains.
  @spec instr_use_refs_for_reg(map(), non_neg_integer(), Types.decl_map(), MapSet.t(), FunctionPlan.t()) ::
          [{atom(), non_neg_integer()}]
  defp instr_use_refs_for_reg(
         %{op: :phi, dest: dest, args: args = %{then: then_r, else: else_r}},
         reg,
         decl_map,
         native_set,
         plan
       ) do
    []
    |> then(fn refs ->
      if then_r == reg,
        do: [phi_operand_use_kind(plan, dest, args, then_r, native_set, decl_map) | refs],
        else: refs
    end)
    |> then(fn refs ->
      if else_r == reg,
        do: [phi_operand_use_kind(plan, dest, args, else_r, native_set, decl_map) | refs],
        else: refs
    end)
  end

  defp instr_use_refs_for_reg(instr, reg, decl_map, native_set, plan) do
    instr
    |> instr_use_refs(decl_map, native_set, plan)
    |> Enum.filter(fn {_, ref} -> ref == reg end)
  end

  @spec instr_use_refs(Types.t() | map(), Types.decl_map(), MapSet.t(Types.reg()), FunctionPlan.t() | term()) :: [{atom(), Types.reg()}]

  defp instr_use_refs(
         %{op: :call_runtime, dest: dest, args: %{builtin: :retain, args: [src]}},
         decl_map,
         native_set,
         plan
       )
       when is_integer(dest) and is_integer(src) do
    # Retain of a known Int producer is a native copy (dual-out `*out_int`,
    # native callees). Do not require `dest` to already be in `native_set` —
    # that chicken-egg forced `advanceSeed` results to box via `elmc_new_int`.
    kind =
      cond do
        MapSet.member?(native_set, dest) ->
          :native_operand

        native_int_value_reg?(plan, src, native_set, decl_map) ->
          :native_operand

        true ->
          :boxed
      end

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

  @spec phi_operand_use_kind(FunctionPlan.t(), Types.reg(), map(), Types.reg(), MapSet.t(Types.reg()), Types.decl_map()) :: {atom(), Types.reg()}

  defp phi_operand_use_kind(plan, phi_dest, phi_args, reg, native_set, decl_map) when is_integer(reg) do
    if native_phi_operand_context?(plan, phi_dest, phi_args, native_set) and
         native_int_value_reg?(plan, reg, native_set, decl_map) do
      {:native_operand, reg}
    else
      {:boxed, reg}
    end
  end

  @spec native_phi_operand_context?(FunctionPlan.t() | term(), Types.reg() | term(), map() | term(), MapSet.t(Types.reg()) | term()) :: boolean()

  defp native_phi_operand_context?(plan, phi_dest, phi_args, native_set) when is_integer(phi_dest) do
    Map.get(phi_args, :native_int_phi) == true or
      MapSet.member?(native_set, phi_dest) or
      native_phi_dest_publishes_scalar?(plan, phi_dest)
  end

  defp native_phi_operand_context?(_, _, _, _), do: false

  @spec native_phi_dest_publishes_scalar?(FunctionPlan.t(), Types.reg()) :: boolean()

  defp native_phi_dest_publishes_scalar?(plan, reg) when is_integer(reg) do
    case Map.get(plan, :native_scalar_return) do
      :native_int -> MapSet.member?(native_publish_reach_set(plan), reg)
      _ -> false
    end
  end

  # Regs that flow forward through phi arms to a `:publish`/`:fn_out` source.
  # Computed once per plan (Process cache) — the old per-query DFS rescanned all
  # instructions at every phi hop and hung on deep || desugarings.
  @spec native_publish_reach_set(FunctionPlan.t()) :: MapSet.t(non_neg_integer())
  defp native_publish_reach_set(%FunctionPlan{} = plan) do
    key =
      {plan.module, plan.name, length(plan.blocks),
       Enum.reduce(plan.blocks, 0, fn b, n -> n + length(b.instrs) end)}

    case Process.get(:elmc_native_publish_reach) do
      {^key, set} ->
        set

      _ ->
        set = compute_native_publish_reach(plan)
        Process.put(:elmc_native_publish_reach, {key, set})
        set
    end
  end

  @spec compute_native_publish_reach(FunctionPlan.t()) :: MapSet.t(non_neg_integer())
  defp compute_native_publish_reach(%FunctionPlan{blocks: blocks}) do
    instrs = Enum.flat_map(blocks, & &1.instrs)

    published =
      Enum.flat_map(instrs, fn
        %{op: :publish, dest: :fn_out, args: %{source: reg}} when is_integer(reg) -> [reg]
        _ -> []
      end)

    # Reverse CFG edge: phi dest → arms that flow into it.
    reverse =
      Enum.reduce(instrs, %{}, fn
        %{op: :phi, dest: dest, args: %{then: then_r, else: else_r}}, acc when is_integer(dest) ->
          arms = for r <- [then_r, else_r], is_integer(r), do: r
          Map.update(acc, dest, arms, &(arms ++ &1))

        _, acc ->
          acc
      end)

    expand_publish_reach(published, MapSet.new(published), reverse)
  end

  defp expand_publish_reach([], reach, _reverse), do: reach

  defp expand_publish_reach([reg | rest], reach, reverse) do
    {reach, rest} =
      Enum.reduce(Map.get(reverse, reg, []), {reach, rest}, fn arm, {reach, rest} ->
        if MapSet.member?(reach, arm) do
          {reach, rest}
        else
          {MapSet.put(reach, arm), [arm | rest]}
        end
      end)

    expand_publish_reach(rest, reach, reverse)
  end

  @spec direct_native_publish?(FunctionPlan.t(), non_neg_integer()) :: boolean()
  defp direct_native_publish?(plan, reg) when is_integer(reg) do
    Enum.any?(plan.blocks, fn %{instrs: instrs} ->
      Enum.any?(instrs, fn
        %{op: :publish, dest: :fn_out, args: %{source: ^reg}} -> true
        _ -> false
      end)
    end)
  end

  @spec native_int_value_reg?(FunctionPlan.t(), Types.reg(), MapSet.t(Types.reg()), Types.decl_map()) :: boolean()
  @spec native_int_value_reg?(FunctionPlan.t(), Types.reg(), MapSet.t(Types.reg()), Types.decl_map(), MapSet.t(Types.reg())) :: boolean()

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

          %{op: :call_runtime, args: %{builtin: :list_nth_int_at}} ->
            true

          %{op: :call_runtime, args: %{builtin: :maybe_with_default_int}} ->
            true

          %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
            native_int_value_reg?(plan, src, native_set, decl_map, visited)

          %{op: :phi, args: %{native_int_phi: true}} ->
            true

          %{op: :load_param, args: %{index: index}} when is_integer(index) ->
            Enum.at(param_kinds_for_plan(plan), index) == :native_int

          %{op: :phi, args: %{then: then_r, else: else_r}} ->
            native_int_value_reg?(plan, then_r, native_set, decl_map, visited) and
              native_int_value_reg?(plan, else_r, native_set, decl_map, visited)

          _ ->
            false
        end
    end
  end

  @spec defining_instr(FunctionPlan.t(), Types.reg()) :: Types.t() | nil

  defp defining_instr(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end

  @spec defining_reg?(map() | term(), integer() | term()) :: boolean()

  defp defining_reg?(%{dest: dest}, reg) when is_integer(dest) and is_integer(reg),
    do: dest == reg

  defp defining_reg?(_, _), do: false

  @spec instr_reg_refs(Types.t() | map() | term(), Types.decl_map()) :: [{atom(), Types.reg()}]

  defp instr_reg_refs(%{op: :call_fn, args: %{module: mod, name: name, args: args}}, decl_map)
       when is_list(args) do
    kinds =
      case Fusion.rc_native_fusion_arg_kinds({mod, name}) do
        fusion_kinds when is_list(fusion_kinds) -> fusion_kinds
        _ -> callee_arg_kinds(mod, name, decl_map)
      end

    Enum.with_index(args)
    |> Enum.map(fn {reg, idx} ->
      kind = Enum.at(kinds, idx, :boxed)
      # :boxed_int_tag is an elmc_int_t peel/arg, not a heap handle.
      ref_kind = if kind in [:native_int, :boxed_int_tag], do: :native_int_call, else: :boxed
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

  defp instr_reg_refs(%{op: :phi, args: %{native_int_phi: true, then: then_r, else: else_r}}, _decl_map),
    do: [{:native_operand, then_r}, {:native_operand, else_r}]

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

  defp instr_reg_refs(%{op: :test_list_length_gte, args: %{reg: reg}}, _decl_map),
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

  defp instr_reg_refs(%{op: :record_update, args: args}, _decl_map) do
    # Int fields lower via `elmc_record_update_index_int_cow_drop`, so the value
    # is a native-int sink (same contract as `record_new` Int fields).
    field = Map.get(args, :field)

    value_kind =
      if is_binary(field) and record_field_int?(field), do: :native_operand, else: :boxed

    [{:boxed, Map.get(args, :base)}, {value_kind, Map.get(args, :value)}]
  end

  defp instr_reg_refs(%{op: :tuple_proj, args: %{base: base}}, _decl_map), do: [{:boxed, base}]

  defp instr_reg_refs(%{op: :make_closure, args: %{captures: caps}}, _decl_map) when is_list(caps),
       do: Enum.map(caps, &{:boxed, &1})

  defp instr_reg_refs(%{op: :list_walk_map, args: args}, _decl_map) do
    list = Map.get(args, :list)
    acc = Map.get(args, :acc)
    caps = Map.get(args, :captures, [])
    list_refs = if is_integer(list), do: [{:boxed, list}], else: []
    acc_refs = if is_integer(acc), do: [{:boxed, acc}], else: []
    list_refs ++ acc_refs ++ Enum.map(caps, &{:boxed, &1})
  end

  defp instr_reg_refs(%{op: :const_static_list, args: %{regs: regs}}, _decl_map) when is_list(regs),
       do: Enum.map(regs, &{:boxed, &1})

  defp instr_reg_refs(%{op: :call_closure, args: args}, _decl_map) do
    callee = Map.get(args, :callee)
    call_args = Map.get(args, :args, [])
    [{:boxed, callee} | Enum.map(call_args, &{:boxed, &1})]
  end

  defp instr_reg_refs(%{op: :forward_ref_set, args: %{value: value}}, _decl_map),
    do: [{:boxed, value}]

  defp instr_reg_refs(%{op: :release, args: %{reg: reg}}, _decl_map), do: [{:boxed, reg}]

  defp instr_reg_refs(_, _decl_map), do: []

  @spec maybe_add_reg_ref([{atom(), Types.reg()}], map(), atom(), atom()) :: [{atom(), Types.reg()}]

  defp maybe_add_reg_ref(refs, args, key, kind) do
    case Map.get(args, key) do
      reg when is_integer(reg) -> [{kind, reg} | refs]
      _ -> refs
    end
  end

  @spec callee_arg_kinds(String.t(), String.t(), Types.decl_map()) :: [atom()]

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

  @spec compact_slots(Types.slot_map()) :: Types.slot_map()

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

  @spec boxed_use_regs(FunctionPlan.t(), Types.decl_map()) :: MapSet.t(Types.reg())

  defp boxed_use_regs(%FunctionPlan{} = plan, decl_map) do
    skip_publish_fn_out? =
      Map.get(plan, :native_scalar_return) in [
        :native_int,
        :native_bool,
        :native_int_pair,
        :native_list_int_pair
      ]

    plan.blocks
    |> Enum.flat_map(fn %Block{instrs: instrs} ->
      Enum.flat_map(instrs, fn instr ->
        if skip_publish_fn_out? and match?(%{op: :publish, dest: :fn_out}, instr) do
          []
        else
          boxed_operand_regs(instr, decl_map)
        end
      end)
    end)
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  @spec forward_ref_value_regs(map()) :: MapSet.t()

  defp forward_ref_value_regs(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs} ->
      Enum.flat_map(instrs, fn
        %{op: :forward_ref_set, args: %{value: value}} when is_integer(value) -> [value]
        _ -> []
      end)
    end)
    |> MapSet.new()
  end

  @spec boxed_operand_regs(Types.t() | map() | term(), Types.decl_map()) :: [Types.reg()]

  defp boxed_operand_regs(%{op: :const_static_list, args: %{regs: regs}}, _decl_map)
       when is_list(regs),
       do: regs

  defp boxed_operand_regs(%{op: :make_closure, args: %{captures: captures}}, _decl_map)
       when is_list(captures),
       do: captures

  defp boxed_operand_regs(%{op: :list_walk_map, args: args}, _decl_map) do
    list = Map.get(args, :list)
    acc = Map.get(args, :acc)
    caps = Map.get(args, :captures, [])
    list_regs = if is_integer(list), do: [list], else: []
    acc_regs = if is_integer(acc), do: [acc], else: []
    list_regs ++ acc_regs ++ caps
  end

  defp boxed_operand_regs(%{op: :phi, args: %{native_int_phi: true}}, _decl_map), do: []

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

    kinds =
      case Fusion.rc_native_fusion_arg_kinds({mod, name}) do
        fusion_kinds when is_list(fusion_kinds) ->
          fusion_kinds

        _ ->
          if decl && FunctionCallAbi.direct_plan_call_abi?(decl, mod, decl_map) &&
               FunctionEmit.mixed_direct_abi?(decl, mod, decl_map) do
            NativeFunctionCall.arg_kinds(decl, mod, decl_map)
          else
            nil
          end
      end

    cond do
      is_list(kinds) ->
        args
        |> Enum.zip(kinds)
        |> Enum.reject(fn {_, kind} -> kind in [:native_int, :native_bool, :boxed_int_tag] end)
        |> Enum.map(fn {reg, _} -> reg end)

      true ->
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
    base = Map.get(args, :base)
    field = Map.get(args, :field)

    if is_binary(field) and record_field_int?(field) do
      [base]
    else
      [base, Map.get(args, :value)]
    end
  end

  defp boxed_operand_regs(%{op: :boxed_binop, args: %{lhs: lhs, rhs: rhs}}, _decl_map),
    do: [lhs, rhs]

  defp boxed_operand_regs(%{op: :test_maybe_nothing, args: %{reg: reg}}, _decl_map), do: [reg]

  defp boxed_operand_regs(%{op: :test_list_empty, args: %{reg: reg}}, _decl_map), do: [reg]

  defp boxed_operand_regs(%{op: :test_list_length_gte, args: %{reg: reg}}, _decl_map), do: [reg]

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

  defp boxed_operand_regs(%{op: :release}, _decl_map), do: []

  defp boxed_operand_regs(%{op: op}, _decl_map)
       when op in [:int_arith, :compare, :load_param, :const_int, :const_static_list, :const_immortal_string],
       do: []

  defp boxed_operand_regs(_, _decl_map), do: []

  @spec native_int_result_ref(Types.reg(), Types.slot_map(), keyword()) :: String.t()

  defp native_int_result_ref(reg, _slots, instr_opts) do
    case Map.get(Keyword.get(instr_opts, :native_int_inline, %{}), reg) do
      expr when is_binary(expr) ->
        expr

      nil ->
        plan = Keyword.get(instr_opts, :parent_plan)
        mutable? = MapSet.member?(Keyword.get(instr_opts, :native_int_mutable_regs, MapSet.new()), reg)

        multi_def? =
          case plan do
            %FunctionPlan{} = p -> length(all_defining_instrs(p, reg)) > 1
            _ -> false
          end

        cond do
          mutable? or multi_def? ->
            "plan_native_int_#{reg}"

          true ->
            case const_int_literal_from_plan(plan, reg) do
              value when is_integer(value) -> Integer.to_string(value)
              _ -> "plan_native_int_#{reg}"
            end
        end
    end
  end

  @spec const_int_literal_from_plan(FunctionPlan.t() | map() | term(), Types.reg() | term()) :: integer() | nil

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

  @spec native_bool_result_ref(Types.reg(), keyword()) :: String.t()

  defp native_bool_result_ref(reg, _instr_opts) do
    "plan_native_bool_#{reg}"
  end

  @spec ret_source_reg(FunctionPlan.t()) :: Types.reg() | nil

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

  @spec maybe_add_native_ret_reg(MapSet.t(Types.reg()), FunctionPlan.t(), Types.reg() | nil, atom() | term()) :: MapSet.t(Types.reg())

  defp maybe_add_native_ret_reg(regs, plan, reg, :native_int) do
    if NativeReturn.ret_reg_allows_native?(plan, reg, :native_int) do
      MapSet.put(regs, reg)
    else
      regs
    end
  end

  defp maybe_add_native_ret_reg(regs, plan, _reg, :native_int_pair) do
    case NativeReturn.pair_ret_operands(plan) do
      {a, b} ->
        Enum.reduce([a, b], regs, fn r, acc ->
          if pair_ret_operand_needs_native_temp?(plan, r) do
            MapSet.put(acc, r)
          else
            acc
          end
        end)

      _ ->
        regs
    end
  end

  defp maybe_add_native_ret_reg(regs, _plan, _reg, _kind), do: regs

  defp pair_ret_operand_needs_native_temp?(plan, reg) when is_integer(reg) do
    case defining_instr(plan, reg) do
      %{op: :load_param, args: %{index: index}} ->
        # Native Int params already alias via `native_int_regs` (C arg name).
        Enum.at(param_kinds_for_plan(plan), index) != :native_int

      %{op: :const_int} ->
        false

      _ ->
        true
    end
  end

  defp pair_ret_operand_needs_native_temp?(_, _), do: false

  @spec maybe_add_native_scalar_ret_bool_reg(MapSet.t(Types.reg()), Types.reg() | nil, atom() | term()) :: MapSet.t(Types.reg())

  defp maybe_add_native_scalar_ret_bool_reg(regs, reg, :native_bool) when is_integer(reg),
    do: MapSet.put(regs, reg)

  defp maybe_add_native_scalar_ret_bool_reg(regs, _reg, _kind), do: regs

  @spec forward_ref_names_in_plan(FunctionPlan.t()) :: [String.t()]
  def forward_ref_names_in_plan(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.flat_map(fn
      %{op: op, args: %{ref: ref}}
      when op in [:forward_ref_set, :forward_ref_load, :forward_ref_capture] and is_binary(ref) ->
        [ref]

      %{op: :forward_ref_load_captured, args: %{ref: ref}} when is_binary(ref) ->
        [ref]

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  @spec letrec_decl_lines([String.t()]) :: [String.t()]
  def letrec_decl_lines(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> "ElmcForwardRef *#{ref} = elmc_forward_ref_new();" end)
  end

  @spec letrec_free_lines([String.t()]) :: [String.t()]
  def letrec_free_lines(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> "elmc_forward_ref_free(#{ref});" end)
  end

  @spec record_field_int?(String.t()) :: boolean()

  defp record_field_int?(field_name) when is_binary(field_name) do
    Process.get(:elmc_record_field_types, %{})
    |> Map.values()
    |> Enum.any?(fn fields when is_map(fields) ->
      Map.get(fields, field_name) == "Int" or Map.get(fields, to_string(field_name)) == "Int"
    end)
  end

  @spec duplicate_switch_arm_refs?(list(), String.t()) :: boolean()

  defp duplicate_switch_arm_refs?(arms, module) when is_list(arms) do
    arms
    |> Enum.map(fn arm ->
      TagRefs.union_tag_ref(
        TagRefs.switch_arm_tag(arm),
        TagRefs.switch_arm_ctor(arm),
        module
      )
    end)
    |> Enum.frequencies()
    |> Enum.any?(fn {_ref, count} -> count > 1 end)
  end
end
