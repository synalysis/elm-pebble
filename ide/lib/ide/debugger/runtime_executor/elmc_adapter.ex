defmodule Ide.Debugger.RuntimeExecutor.ElmcAdapter do
  @moduledoc """
  Adapter shim for future elmc-backed runtime execution.

  This module keeps debugger/runtime contracts stable while probing for optional
  `elmc` runtime execution APIs as they land.
  """

  @behaviour Ide.Debugger.RuntimeExecutor

  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Types

  @type execution_input :: Ide.Debugger.RuntimeExecutor.execution_input()
  @type execution_result :: Ide.Debugger.RuntimeExecutor.execution_result()

  @type elmc_wire_result :: ExecutorTypes.executor_wire_result() | map()

  @type executor_result :: {:ok, execution_result()} | {:error, Types.execution_error()}

  @default_candidates [
    {Elmc.Runtime.Executor, :execute, 1},
    {Elmc.Runtime.Executor, :run, 1},
    {Elmc.Runtime.Debugger, :execute, 1},
    {Elmc.Runtime.Debugger, :run, 1},
    {Elmc.Runtime, :execute, 1},
    {Elmc.Runtime, :run, 1}
  ]

  @impl true
  @spec execute(execution_input()) :: {:ok, execution_result()} | {:error, Types.execution_error()}
  def execute(input) when is_map(input) do
    case first_available_candidate(candidate_calls()) do
      {:ok, {mod, fun, _arity}} ->
        request = adapter_request(input)

        case apply(mod, fun, [request]) do
          {:ok, payload} when is_map(payload) ->
            {:ok, normalize_result(payload, input)}

          {:error, reason} ->
            {:error, {:elmc_runtime_executor_failed, reason}}

          other ->
            {:error, {:invalid_elmc_runtime_result, other}}
        end

      {:error, :no_candidate_available} ->
        {:error, {:elmc_runtime_unavailable, candidate_calls()}}
    end
  end

  def execute(_), do: {:error, :invalid_execution_input}

  @spec candidate_calls() :: [{module(), atom(), pos_integer()}]
  defp candidate_calls do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:candidates, @default_candidates)
  end

  @spec first_available_candidate([{module(), atom(), pos_integer()}]) ::
          {:ok, {module(), atom(), pos_integer()}} | {:error, :no_candidate_available}
  defp first_available_candidate(candidates) when is_list(candidates) do
    case Enum.find(candidates, fn
           {mod, fun, arity}
           when is_atom(mod) and is_atom(fun) and is_integer(arity) and arity > 0 ->
             case Code.ensure_loaded(mod) do
               {:module, _} -> function_exported?(mod, fun, arity)
               _ -> false
             end

           _ ->
             false
         end) do
      nil -> {:error, :no_candidate_available}
      tuple -> {:ok, tuple}
    end
  end

  @spec adapter_request(execution_input()) :: map()
  defp adapter_request(input) do
    base = %{
      source_root: Map.get(input, :source_root),
      rel_path: Map.get(input, :rel_path),
      source: Map.get(input, :source),
      introspect: Map.get(input, :introspect),
      current_model: Map.get(input, :current_model),
      current_view_tree: Map.get(input, :current_view_tree),
      message: Map.get(input, :message),
      update_branches: Map.get(input, :update_branches),
      debugger_contract: "ide.runtime_executor.v1"
    }

    base
    |> maybe_put_optional_context(:elm_executor_core_ir, Map.get(input, :elm_executor_core_ir))
    |> maybe_put_optional_context(:elm_executor_metadata, Map.get(input, :elm_executor_metadata))
  end

  @spec maybe_put_optional_context(map(), atom(), map()) :: map()
  defp maybe_put_optional_context(request, key, value)
       when is_map(request) and is_atom(key) and is_map(value) do
    Map.put(request, key, value)
  end

  defp maybe_put_optional_context(request, _key, _value) when is_map(request), do: request

  @spec normalize_result(elmc_wire_result(), execution_input()) :: execution_result()
  defp normalize_result(payload, input) do
    result =
      if Map.has_key?(payload, :model_patch) or Map.has_key?(payload, "model_patch") do
        ResultNormalizer.normalize(payload)
      else
        ResultNormalizer.normalize_elmc_loose(payload, input)
      end

    %{result | model_patch: ResultNormalizer.put_runtime_view_output(result.model_patch, result.view_output)}
  end
end
