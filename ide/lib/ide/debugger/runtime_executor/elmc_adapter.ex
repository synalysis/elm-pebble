defmodule Ide.Debugger.RuntimeExecutor.ElmcAdapter do
  @moduledoc """
  Adapter shim for future elmc-backed runtime execution.

  This module keeps debugger/runtime contracts stable while probing for optional
  `elmc` runtime execution APIs as they land.
  """

  @behaviour Ide.Debugger.RuntimeExecutor

  @type execution_input :: Ide.Debugger.RuntimeExecutor.execution_input()
  @type execution_result :: Ide.Debugger.RuntimeExecutor.execution_result()

  @default_candidates [
    {Elmc.Runtime.Executor, :execute, 1},
    {Elmc.Runtime.Executor, :run, 1},
    {Elmc.Runtime.Debugger, :execute, 1},
    {Elmc.Runtime.Debugger, :run, 1},
    {Elmc.Runtime, :execute, 1},
    {Elmc.Runtime, :run, 1}
  ]

  @impl true
  @spec execute(execution_input()) :: {:ok, execution_result()} | {:error, term()}
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

  @spec maybe_put_optional_context(term(), term(), term()) :: term()
  defp maybe_put_optional_context(request, key, value)
       when is_map(request) and is_atom(key) and is_map(value) do
    Map.put(request, key, value)
  end

  defp maybe_put_optional_context(request, _key, _value) when is_map(request), do: request

  @spec normalize_result(map(), execution_input()) :: execution_result()
  defp normalize_result(payload, input) do
    if Map.has_key?(payload, :model_patch) or Map.has_key?(payload, "model_patch") do
      view_output = list_field(payload, :view_output)

      %{
        model_patch: payload |> map_field(:model_patch) |> put_runtime_view_output(view_output),
        view_tree: map_or_nil_field(payload, :view_tree),
        view_output: view_output,
        runtime: map_field(payload, :runtime),
        protocol_events: list_field(payload, :protocol_events),
        followup_messages: list_field(payload, :followup_messages)
      }
    else
      runtime_model = map_field(payload, :runtime_model)
      runtime_view_tree = map_or_nil_field(payload, :view_tree)
      view_output = list_field(payload, :view_output)

      runtime =
        map_field(payload, :runtime)
        |> Map.put_new("engine", "elmc_runtime_adapter_v0")
        |> Map.put_new("source_root", Map.get(input, :source_root))
        |> Map.put_new("rel_path", Map.get(input, :rel_path))

      %{
        model_patch:
          %{
            "runtime_model" => runtime_model,
            "elm_executor_mode" => "runtime_executed",
            "runtime_model_source" => "elmc_runtime",
            "elm_executor" => runtime
          }
          |> put_runtime_view_output(view_output),
        view_tree: runtime_view_tree,
        view_output: view_output,
        runtime: runtime,
        protocol_events: list_field(payload, :protocol_events),
        followup_messages: list_field(payload, :followup_messages)
      }
    end
  end

  @spec map_field(map(), atom()) :: map()
  defp map_field(map, key) when is_map(map) and is_atom(key) do
    value =
      Map.get(map, key) ||
        Map.get(map, Atom.to_string(key))

    if is_map(value), do: value, else: %{}
  end

  @spec map_or_nil_field(map(), atom()) :: map() | nil
  defp map_or_nil_field(map, key) when is_map(map) and is_atom(key) do
    value =
      Map.get(map, key) ||
        Map.get(map, Atom.to_string(key))

    if is_map(value), do: value, else: nil
  end

  @spec list_field(map(), atom()) :: list()
  defp list_field(map, key) when is_map(map) and is_atom(key) do
    value =
      Map.get(map, key) ||
        Map.get(map, Atom.to_string(key))

    if is_list(value), do: value, else: []
  end

  @spec put_runtime_view_output(map(), list()) :: map()
  defp put_runtime_view_output(model_patch, [_ | _] = view_output) when is_map(model_patch) do
    Map.put_new(model_patch, "runtime_view_output", view_output)
  end

  defp put_runtime_view_output(model_patch, _view_output) when is_map(model_patch),
    do: model_patch
end
