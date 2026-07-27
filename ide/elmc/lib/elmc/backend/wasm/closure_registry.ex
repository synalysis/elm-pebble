defmodule Elmc.Backend.Wasm.ClosureRegistry do
  @moduledoc false

  alias Elmc.Backend.C.Lower.Lambda, as: CLambda
  alias Elmc.Backend.Plan.Types.FunctionPlan
  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @type closure_entry :: %{
          index: non_neg_integer(),
          export: String.t(),
          parent_module: String.t(),
          parent_name: String.t(),
          parent_plan: FunctionPlan.t(),
          lambda_index: non_neg_integer(),
          arity: non_neg_integer(),
          capture_count: non_neg_integer(),
          rc_required: boolean(),
          lambda: FunctionPlan.t()
        }

  @type t :: %{
          entries: [closure_entry()],
          index_map: %{{String.t(), String.t(), non_neg_integer()} => non_neg_integer()}
        }

  @spec build([FunctionPlan.t()]) :: t()
  def build(plans) when is_list(plans) do
    plans =
      plans
      |> Enum.flat_map(&collect_plans/1)
      |> Enum.uniq_by(fn %FunctionPlan{} = plan -> {plan.module, plan.name} end)

    entries =
      plans
      |> Enum.flat_map(&closure_entries_for_plan/1)
      |> Enum.with_index()
      |> Enum.map(fn {entry, global_index} ->
        Map.put(entry, :index, global_index)
      end)

    index_map =
      Map.new(entries, fn entry ->
        {{entry.parent_module, entry.parent_name, entry.lambda_index}, entry.index}
      end)

    %{entries: entries, index_map: index_map}
  end

  defp collect_plans(%FunctionPlan{} = plan) do
    [plan | Enum.flat_map(plan.lambdas || [], &collect_plans/1)]
  end

  @spec export_name(FunctionPlan.t(), non_neg_integer()) :: String.t()
  def export_name(%FunctionPlan{} = parent, idx) when is_integer(idx) do
    WasmTypes.closure_ident(parent.module, parent.name, idx)
  end

  @spec global_index(t(), FunctionPlan.t(), non_neg_integer()) :: non_neg_integer()
  def global_index(%{index_map: index_map}, %FunctionPlan{} = parent, local_idx)
      when is_integer(local_idx) do
    Map.fetch!(index_map, {parent.module, parent.name, local_idx})
  end

  defp closure_entries_for_plan(%FunctionPlan{} = parent) do
    (parent.lambdas || [])
    |> Enum.with_index()
    |> Enum.map(fn {lambda, idx} ->
      %{
        export: export_name(parent, idx) |> strip_dollar(),
        parent_module: parent.module,
        parent_name: parent.name,
        parent_plan: parent,
        lambda_index: idx,
        arity: lambda.lambda_arg_count || length(lambda.params || []),
        capture_count: CLambda.capture_count(lambda),
        rc_required: lambda.rc_required == true,
        lambda: lambda
      }
    end)
  end

  defp strip_dollar("$" <> rest), do: rest
  defp strip_dollar(other), do: other
end
