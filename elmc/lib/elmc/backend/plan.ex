defmodule Elmc.Backend.Plan do
  @moduledoc """
  Target-neutral SSA plan IR — shared contract for C, bytecode, and future WASM backends.

  See `plan/README.md` for the cross-target runtime builtin registry.
  """

  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec primary_lowered?(map(), String.t(), map(), keyword()) :: boolean()
  def primary_lowered?(decl, module_name, decl_map, opts \\ []) do
    opts = if opts == [], do: Process.get(:elmc_codegen_opts, []), else: opts
    name = Map.get(decl, :name, "")
    key = {module_name, name}

    cond do
      plan_ir_mode(opts) != :primary ->
        false

      true ->
        case primary_lowered_cache_get(key) do
          {:ok, result} ->
            result

          :pending ->
            # plan_use_refs -> callee_arg_kinds re-enters while lowering the same function.
            true

          :miss ->
            primary_lowered_cache_put(key, :pending)

            rc_required? = RcRequired.rc_required?(module_name, name)

            result =
              match?(
                {:ok, _},
                lower_function(decl, module_name, decl_map, rc_required: rc_required?)
              )

            primary_lowered_cache_put(key, {:ok, result})
            result
        end
    end
  end

  defp primary_lowered_cache_get(key) do
    case Map.get(Process.get(:elmc_plan_primary_lowered_cache, %{}), key) do
      {:ok, _} = hit -> hit
      :pending -> :pending
      _ -> :miss
    end
  end

  defp primary_lowered_cache_put(key, value) do
    cache = Process.get(:elmc_plan_primary_lowered_cache, %{})
    Process.put(:elmc_plan_primary_lowered_cache, Map.put(cache, key, value))
  end

  defdelegate lower_function(decl, module, decl_map, opts \\ []),
    to: Elmc.Backend.Plan.Lower.Function,
    as: :lower

  defdelegate verify(plan), to: Elmc.Backend.Plan.Verify, as: :run
  defdelegate dump(plan), to: Elmc.Backend.Plan.Debug, as: :dump
  defdelegate plan_ir_mode(opts), to: Elmc.Backend.Plan.Shadow, as: :plan_ir_mode
  defdelegate strict_primary?(opts), to: Elmc.Backend.Plan.StrictPolicy, as: :strict?
  defdelegate default_plan_ir_mode(), to: Elmc.Backend.Plan.Defaults, as: :plan_ir_mode
  defdelegate shadow_verify(decl, module, decl_map, opts), to: Elmc.Backend.Plan.Shadow, as: :maybe_verify_function
  defdelegate shadow_stats(), to: Elmc.Backend.Plan.Shadow, as: :shadow_stats
  defdelegate reset_shadow_stats(), to: Elmc.Backend.Plan.Shadow, as: :reset_stats

  @spec allocate_slots(FunctionPlan.t()) :: {map(), non_neg_integer()}
  def allocate_slots(plan), do: Elmc.Backend.Plan.Allocate.run(plan)
end
