defmodule Elmc.Backend.Wasm.Slots do
  @moduledoc false

  alias Elmc.Backend.Plan
  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @pointer_mem_base 1024
  @int_array_scratch_offset 4096

  @type t :: %{
          params: non_neg_integer(),
          rc_local: String.t(),
          fn_out_local: String.t(),
          plan_state_local: String.t() | nil,
          owned_base: non_neg_integer(),
          owned_count: non_neg_integer(),
          slot_map: %{non_neg_integer() => non_neg_integer()},
          reg_locals: %{non_neg_integer() => String.t()},
          local_count: non_neg_integer(),
          fn_out_mem: non_neg_integer(),
          reg_mem: %{non_neg_integer() => non_neg_integer()},
          owned_mem: %{non_neg_integer() => non_neg_integer()}
        }

  @spec build(FunctionPlan.t()) :: t()
  def build(%FunctionPlan{} = plan) do
    params = length(plan.params || [])
    {slot_map, _count} = Plan.allocate_slots(plan)

    owned_count =
      case Map.values(slot_map) do
        [] -> 0
        values -> Enum.max(values) + 1
      end

    reg_count =
      plan
      |> max_plan_reg()
      |> max(params)

    reg_locals =
      if reg_count > 0 do
        Map.new(0..(reg_count - 1), &{&1, WasmTypes.reg_local(&1)})
      else
        %{}
      end

    plan_state? = length(plan.blocks || []) > 1

    owned_base = params + 2

    owned_mem =
      Map.new(0..(owned_count - 1)//1, fn index ->
        {index, @pointer_mem_base + 4 + index * 4}
      end)

    reg_mem =
      Map.new(0..(reg_count - 1)//1, fn reg ->
        {reg, @pointer_mem_base + 4 + owned_count * 4 + reg * 4}
      end)

    %{
      params: params,
      rc_local: WasmTypes.ident("rc"),
      fn_out_local: WasmTypes.ident("fn_out"),
      plan_state_local: if(plan_state?, do: WasmTypes.ident("plan_state"), else: nil),
      owned_base: owned_base,
      owned_count: owned_count,
      slot_map: slot_map,
      reg_locals: reg_locals,
      local_count: owned_base + owned_count,
      fn_out_mem: @pointer_mem_base,
      reg_mem: reg_mem,
      owned_mem: owned_mem
    }
  end

  @spec int_array_scratch_offset() :: non_neg_integer()
  def int_array_scratch_offset, do: @int_array_scratch_offset

  @spec reg_name(t(), non_neg_integer() | :fn_out | :branch_out | nil) :: String.t()
  def reg_name(_slots, nil), do: WasmTypes.ident("zero")

  def reg_name(%{fn_out_local: fn_out}, :fn_out), do: fn_out
  def reg_name(%{fn_out_local: fn_out}, :branch_out), do: fn_out

  def reg_name(%{reg_locals: regs}, reg) when is_integer(reg) do
    Map.get(regs, reg, WasmTypes.reg_local(reg))
  end

  @spec pointer_mem_offset(t(), non_neg_integer() | :fn_out | :branch_out | nil) :: non_neg_integer() | nil
  def pointer_mem_offset(_slots, nil), do: nil
  def pointer_mem_offset(%{fn_out_mem: offset}, dest) when dest in [:fn_out, :branch_out], do: offset

  def pointer_mem_offset(%{reg_mem: reg_mem, owned_mem: owned_mem}, dest) when is_integer(dest) do
    Map.get(reg_mem, dest) || Map.get(owned_mem, dest)
  end

  @spec sync_owned_slot(t(), non_neg_integer() | :fn_out | :branch_out, String.t()) :: [binary()]
  def sync_owned_slot(%{slot_map: slot_map} = slots, dest_reg, src_local) when is_integer(dest_reg) do
    case Map.get(slot_map, dest_reg) do
      idx when is_integer(idx) ->
        owned = owned_local(slots, idx)

        [
          WasmTypes.line(
            WasmTypes.sexpr("local.set", [
              owned,
              " ",
              WasmTypes.sexpr("local.get", [src_local])
            ])
          )
        ]

      _ ->
        []
    end
  end

  def sync_owned_slot(_slots, _dest_reg, _src_local), do: []

  @spec owned_local(t(), non_neg_integer()) :: String.t()
  def owned_local(%{owned_base: base}, index), do: WasmTypes.ident("owned#{base + index}")

  @spec local_decls(t()) :: iodata()
  def local_decls(slots) do
    lines =
      [
        sexpr_local(slots.rc_local, "i32"),
        sexpr_local(slots.fn_out_local, "i32")
      ] ++
        List.wrap(
          if slots.plan_state_local do
            sexpr_local(slots.plan_state_local, "i32")
          end
        ) ++
        Enum.map(0..(slots.owned_count - 1)//1, &sexpr_local(owned_local(slots, &1), "i32")) ++
        Enum.map(slots.reg_locals, fn {_reg, name} -> sexpr_local(name, "i32") end)

    Enum.map(lines, &WasmTypes.line/1)
  end

  defp sexpr_local(name, type), do: WasmTypes.sexpr("local", [name, " ", type])

  defp max_plan_reg(%FunctionPlan{} = plan) do
    plan.blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.reduce(plan.reg_count || 0, fn instr, acc ->
      regs =
        [Map.get(instr, :dest)]
        |> Kernel.++(phi_regs(Map.get(instr, :args)))
        |> Enum.filter(&is_integer/1)

      case regs do
        [] -> acc
        _ -> max(acc, Enum.max(regs))
      end
    end)
  end

  defp phi_regs(args) when is_map(args) do
    for key <- [:then, :else, :cond],
        reg = Map.get(args, key),
        is_integer(reg),
        do: reg
  end

  defp phi_regs(_), do: []
end
