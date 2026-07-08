defmodule Elmc.Backend.C.Lower.Function do
  @moduledoc """
  Lower verified `%FunctionPlan{}` to C function body text (RC ABI).
  """

  alias Elmc.Backend.C.Lower.{Frame, Instr, Lambda}
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec emit(FunctionPlan.t(), keyword()) :: String.t()
  def emit(%FunctionPlan{} = plan, opts \\ []) do
    if Keyword.get(opts, :shell, true) do
      wrap_shell(plan, emit_core(plan, opts))
    else
      emit_core(plan, opts)
    end
  end

  @spec emit_core(FunctionPlan.t(), keyword()) :: String.t()
  def emit_core(%FunctionPlan{} = plan, opts \\ []) do
    unless Keyword.get(opts, :closure_mode) do
      Lambda.ensure_emitted!(plan)
    end

    {slots, _slot_count} = Plan.allocate_slots(plan)
    rc? = plan.rc_required
    decl = lookup_decl(plan.module, plan.name)
    decl_map = Process.get(:elmc_program_decls, %{})

    param_kinds =
      if decl && FunctionEmit.mixed_direct_abi?(decl, plan.module, decl_map) do
        NativeFunctionCall.arg_kinds(decl, plan.module, decl_map)
      else
        List.duplicate(:boxed, length(plan.params))
      end

    instr_opts = [
      rc_required: rc?,
      params: param_names(plan.params),
      param_kinds: param_kinds,
      ownership: Map.get(decl || %{}, :ownership, []),
      lambdas: plan.lambdas || [],
      parent_plan: plan,
      module: plan.module,
      closure_mode: Keyword.get(opts, :closure_mode)
    ]

    jump_targets = jump_target_ids(plan.blocks)

    body_lines =
      plan.blocks
      |> Enum.flat_map(fn %Block{id: id, instrs: instrs, terminator: term} ->
        (if labeled_block?(id, jump_targets), do: [block_label(id)], else: []) ++
          Enum.flat_map(instrs, &emit_instr_lines(&1, slots, instr_opts)) ++
          [emit_terminator(term, slots, rc?)]
      end)
      |> Enum.reject(&(&1 == ""))

    ret_line = emit_return(plan, slots)

    (body_lines ++ List.wrap(ret_line))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp block_label(0), do: "/* plan block 0 */"
  defp block_label(id), do: "elmc_plan_block_#{id}:"

  defp labeled_block?(0, _jump_targets), do: true
  defp labeled_block?(id, jump_targets), do: MapSet.member?(jump_targets, id)

  defp jump_target_ids(blocks) do
    Enum.reduce(blocks, MapSet.new(), fn %Block{terminator: term}, acc ->
      add_jump_targets(acc, term)
    end)
  end

  defp add_jump_targets(acc, {:br, id}), do: MapSet.put(acc, id)

  defp add_jump_targets(acc, {:br_if, then_id, else_id, _}) do
    acc |> MapSet.put(then_id) |> MapSet.put(else_id)
  end

  defp add_jump_targets(acc, {:switch_tag, _, arms, default_id}) do
    arm_targets = Enum.map(arms, fn {_, id} -> id end)
    Enum.reduce(arm_targets ++ [default_id], acc, &MapSet.put(&2, &1))
  end

  defp add_jump_targets(acc, _), do: acc

  defp emit_instr_lines(instr, slots, instr_opts) do
    code = Instr.emit(instr, slots, instr_opts)
    nulls = emit_null_consumed_slots(instr, slots)

    [code, nulls]
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
  end

  defp emit_null_consumed_slots(%{effects: %{consumes: consumes}}, slots) when is_list(consumes) do
    consumes
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.map(fn reg ->
      case Map.get(slots, reg) do
        i when is_integer(i) -> "owned[#{i}] = NULL;"
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp emit_null_consumed_slots(_, _), do: []

  defp emit_terminator({:br_if, then_id, else_id, cond_reg}, slots, _rc?) do
    cond = slot_ref(cond_reg, slots)

    """
    if (elmc_as_int(#{cond}) != 0) {
      goto elmc_plan_block_#{then_id};
    } else {
      goto elmc_plan_block_#{else_id};
    }
    """
    |> String.trim()
  end

  defp emit_terminator({:br, target_id}, _slots, _rc?) do
    "goto elmc_plan_block_#{target_id};"
  end

  defp emit_terminator({:switch_tag, subject, arms, default_id}, slots, _rc?) do
    subject_s = slot_ref(subject, slots)

    arm_lines =
      Enum.map(arms, fn {tag, block_id} ->
        "if (elmc_union_tag_matches(#{subject_s}, #{tag})) goto elmc_plan_block_#{block_id};"
      end)

    default_line = "goto elmc_plan_block_#{default_id};"

  chain =
      case arm_lines do
        [] ->
          default_line

        lines ->
          Enum.join(lines, " else ") <> " else " <> default_line
      end

    chain
  end

  defp emit_terminator({:ret, _}, _slots, _rc?), do: ""
  defp emit_terminator(:none, _slots, _rc?), do: ""
  defp emit_terminator(_, _slots, _rc?), do: ""

  defp wrap_shell(%FunctionPlan{rc_required: rc?, fallible: fallible?} = plan, core) do
    {slots, slot_count} = Plan.allocate_slots(plan)
    owned = Frame.owned_declaration(plan, slots)
    slot_indices = if slot_count > 0, do: Enum.to_list(0..(slot_count - 1)), else: []
    epilogue = Frame.epilogue_release(slot_indices, slot_count)
    borrow_nulls = emit_borrow_param_nulls(plan, slots)
    core_with_nulls = append_borrow_param_nulls(core, borrow_nulls)

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

    (letrec_decls ++ prefix ++ [Frame.wrap_catch(needs_catch?, core_with_nulls)] ++ suffix)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp emit_borrow_param_nulls(plan, slots) do
    ownership = Map.get(lookup_decl(plan.module, plan.name) || %{}, :ownership, [])

    if :retain_arg in List.wrap(ownership) do
      []
    else
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))
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

  defp append_borrow_param_nulls(core, []), do: core

  defp append_borrow_param_nulls(core, nulls) do
    core <> "\n" <> Enum.join(nulls, "\n")
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

  defp emit_return(%FunctionPlan{rc_required: false, blocks: blocks}, slots) do
    slot_count = owned_slot_count(slots)

    case List.last(blocks) do
      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        ref = slot_ref(reg, slots)
        idx = Map.get(slots, reg, 0)

        if slot_count > 0 do
          """
          {
            ElmcValue *__ret = #{ref};
            owned[#{idx}] = NULL;
            elmc_release_array_lifo(owned, #{slot_count});
            return __ret;
          }
          """
          |> String.trim()
        else
          "return #{ref};"
        end

      _ ->
        if slot_count > 0 do
          """
          elmc_release_array_lifo(owned, #{slot_count});
          return elmc_int_zero();
          """
          |> String.trim()
        else
          "return elmc_int_zero();"
        end
    end
  end

  defp emit_return(%FunctionPlan{blocks: blocks}, slots) do
    case List.last(blocks) do
      %Block{terminator: {:ret, :fn_out}} ->
        ""

      %Block{terminator: {:ret, reg}} when is_integer(reg) ->
        "*out = #{slot_ref(reg, slots)};\nowned[#{Map.get(slots, reg, 0)}] = NULL;"

      _ ->
        "*out = elmc_int_zero();"
    end
  end

  defp slot_ref(reg, slots) do
    i = Map.get(slots, reg, reg)
    "owned[#{i}]"
  end

  defp owned_slot_count(slots) do
    case Map.values(slots) do
      [] -> 0
      values -> Enum.max(values) + 1
    end
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

  @spec letrec_decl_lines([String.t()]) :: [String.t()]
  def letrec_decl_lines(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> "ElmcForwardRef *#{ref} = elmc_forward_ref_new();" end)
  end

  @spec letrec_free_lines([String.t()]) :: [String.t()]
  def letrec_free_lines(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> "elmc_forward_ref_free(#{ref});" end)
  end
end
