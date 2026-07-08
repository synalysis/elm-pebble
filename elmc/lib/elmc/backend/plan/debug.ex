defmodule Elmc.Backend.Plan.Debug do
  @moduledoc """
  Human-readable plan dumps for tests and diagnostics.
  """

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec dump(FunctionPlan.t()) :: String.t()
  def dump(%FunctionPlan{} = plan) do
    header = """
    function #{plan.module}.#{plan.name}/#{length(plan.params)}
      fallible=#{plan.fallible} rc=#{plan.rc_required} regs=#{plan.reg_count}
    """

    blocks =
      Enum.map_join(plan.blocks, "\n", fn %Block{id: id, instrs: instrs, terminator: term} ->
        body =
          Enum.map_join(instrs, "\n", fn %Types{} = i ->
            "    #{format_instr(i)}"
          end)

        term_line = "    terminator #{format_terminator(term)}"
        "  block #{id}:\n#{body}\n#{term_line}"
      end)

    header <> blocks
  end

  @spec dump_compact(FunctionPlan.t()) :: String.t()
  def dump_compact(plan), do: dump(plan)

  defp format_instr(%Types{id: id, op: op, dest: dest, args: args, effects: fx}) do
    dest_s = format_dest(dest)
    args_s = inspect(args, limit: :infinity, printable_limit: 80)
    fx_s = format_effects(fx)
    "%#{id} #{op} #{dest_s} #{args_s} #{fx_s}"
  end

  defp format_dest(nil), do: "→ _"
  defp format_dest(:fn_out), do: "→ fn_out"
  defp format_dest(:branch_out), do: "→ branch_out"
  defp format_dest(r) when is_integer(r), do: "→ %#{r}"

  defp format_effects(%{fallible: true} = fx),
    do: "[fallible borrows=#{inspect(fx.borrows)} consumes=#{inspect(fx.consumes)}]"

  defp format_effects(fx),
    do: "[borrows=#{inspect(fx.borrows)} consumes=#{inspect(fx.consumes)}]"

  defp format_terminator({:ret, r}), do: "ret #{inspect(r)}"
  defp format_terminator({:br, id}), do: "br #{id}"
  defp format_terminator({:br_if, t, f, r}), do: "br_if #{t}/#{f} on %#{r}"
  defp format_terminator({:switch_tag, r, arms, d}), do: "switch_tag %#{r} #{length(arms)} arms default #{d}"
  defp format_terminator(:none), do: "none"
  defp format_terminator(other), do: inspect(other)
end
