defmodule Elmc.Backend.Bytecode.Program do
  @moduledoc """
  Link lowered `%FunctionPlan{}` values into a callable bytecode program.

  Collects transitive `call_fn` callees from a root function, lowers each from
  `decl_map`, and runs the entry plan with nested dispatch via `Runtime.plans`.
  """

  alias Elmc.Backend.Bytecode.{FnTable, Runtime}
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.Types, as: PlanTypes
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @type entry :: {String.t(), String.t()}

  @type t :: %{
          plans: %{entry() => FunctionPlan.t()},
          entry: entry()
        }

  @spec link(CCodegenTypes.function_decl_map(), entry(), keyword()) ::
          {:ok, t()} | PlanTypes.lower_result()
  def link(decl_map, {module, name} = root, opts \\ []) when is_map(decl_map) do
    with {:ok, root_plan} <- lower_decl(decl_map, module, name, opts) do
      plans = link_callees(decl_map, %{root => root_plan}, opts)
      {:ok, %{plans: plans, entry: root}}
    end
  end

  @spec run(t(), keyword()) :: {:ok, Runtime.value()}
  def run(%{plans: plans, entry: entry}, opts \\ []) do
    plan = Map.fetch!(plans, entry)
    Runtime.run_function(plan, Keyword.merge(opts, plans: plans))
  end

  defp link_callees(decl_map, plans, opts) do
    pending =
      plans
      |> Map.values()
      |> Enum.flat_map(&FnTable.collect/1)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(plans, &1))

    if pending == [] do
      plans
    else
      new_plans =
        Enum.reduce(pending, plans, fn {module, name}, acc ->
          case lower_decl(decl_map, module, name, opts) do
            {:ok, plan} -> Map.put(acc, {module, name}, plan)
            _ -> acc
          end
        end)

      link_callees(decl_map, new_plans, opts)
    end
  end

  defp lower_decl(decl_map, module, name, opts) do
    case Map.fetch(decl_map, {module, name}) do
      {:ok, decl} ->
        rc_required? =
          Keyword.get_lazy(opts, :rc_required, fn ->
            RcRequired.rc_required?(module, name)
          end)

        case PlanLower.lower(decl, module, decl_map, rc_required: rc_required?) do
          {:ok, plan} -> {:ok, plan}
          other -> other
        end

      :error ->
        :unsupported
    end
  end
end
