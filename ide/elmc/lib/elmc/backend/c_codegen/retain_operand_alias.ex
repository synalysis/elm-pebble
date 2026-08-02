defmodule Elmc.Backend.CCodegen.RetainOperandAlias do
  @moduledoc """
  Emit alias-null + conditional retain-drop after runtimes that return
  `elmc_retain(chosen_operand)` (`elmc_maybe_with_default`, `elmc_basics_min`, …).

  The extra retain must be dropped **inside** `if (dest == operand)` when transferring
  an owned operand. Unconditional `elmc_release(dest)` frees borrowed Just payloads
  while the model still owns them (YES `Maybe.withDefault default model.sun`).
  """

  alias Elmc.Backend.CCodegen.ValueSlots

  @doc """
  Emit C for plan-primary lowering. `dest` is an SSA reg or `:fn_out` / `:branch_out`.
  """
  @spec emit_for_plan_dest(
          non_neg_integer() | :fn_out | :branch_out,
          [non_neg_integer()],
          map(),
          keyword()
        ) :: String.t()
  def emit_for_plan_dest(dest, alias_regs, slots, instr_opts) when is_list(alias_regs) do
    case dest do
      reg when is_integer(reg) ->
        emit_for_plan(reg, alias_regs, slots, instr_opts)

      dest when dest in [:fn_out, :branch_out] ->
        alias_refs =
          alias_regs
          |> Enum.map(&plan_owned_slot_ref(&1, slots, instr_opts))
          |> Enum.filter(&is_binary/1)

        emit("*out", alias_refs, drop_result_retain?: true)

      _ ->
        ""
    end
  end

  @spec emit_for_plan(non_neg_integer(), [non_neg_integer()], map(), keyword()) :: String.t()
  def emit_for_plan(dest_reg, alias_regs, slots, instr_opts)
      when is_integer(dest_reg) and is_list(alias_regs) do
    dest_ref = plan_owned_slot_ref(dest_reg, slots, instr_opts)

    if is_binary(dest_ref) do
      alias_refs =
        alias_regs
        |> Enum.map(&plan_owned_slot_ref(&1, slots, instr_opts))
        |> Enum.filter(&is_binary/1)

      emit(dest_ref, alias_refs, drop_result_retain?: true)
    else
      ""
    end
  end

  @doc """
  Emit C when dest and alias operands are already resolved C refs (`owned[N]`, params, …).
  """
  @spec emit(String.t(), [String.t()], keyword()) :: String.t()
  def emit(dest_ref, alias_operand_refs, opts \\ [])
      when is_binary(dest_ref) and is_list(alias_operand_refs) do
    drop? = Keyword.get(opts, :drop_result_retain?, true)

    alias_operand_refs
    |> Enum.filter(&(is_binary(&1) and &1 != dest_ref))
    |> Enum.map(fn arg_ref ->
      body =
        if drop? do
          "elmc_release(#{dest_ref});\n  #{null_ref(arg_ref)}"
        else
          null_ref(arg_ref)
        end

      """
      if (#{dest_ref} == #{arg_ref}) {
        #{body}
      }
      """
    end)
    |> Enum.join("\n")
    |> case do
      "" -> ""
      code -> code <> "\n"
    end
  end

  @doc """
  Legacy direct-render / RuntimeCall path: `out` is the assignment lhs (`owned[N]`).
  """
  @spec emit_for_runtime_call(String.t(), [String.t()], map()) :: String.t()
  def emit_for_runtime_call(out, arg_vars, env) when is_binary(out) and is_list(arg_vars) do
    ValueSlots.null_call_operands_aliasing_out(out, arg_vars, env, drop_result_retain?: true)
  end

  @spec plan_owned_slot_ref(non_neg_integer(), map(), keyword()) :: String.t() | nil
  defp plan_owned_slot_ref(reg, slots, _instr_opts) when is_integer(reg) do
    case Map.get(slots, reg) do
      i when is_integer(i) -> "owned[#{i}]"
      _ -> nil
    end
  end

  @spec null_ref(String.t()) :: String.t()
  defp null_ref("owned[" <> _ = ref), do: "#{ref} = NULL;"
  defp null_ref(ref), do: "#{ref} = NULL;"
end
