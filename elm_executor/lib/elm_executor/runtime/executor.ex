defmodule ElmExecutor.Runtime.Executor do
  @moduledoc """
  Runtime executor contract for IDE and generic embedding.

  This module currently anchors deterministic execution with a compiled-module
  contract and delegates semantic execution to the in-repo runtime engine while
  preserving backend metadata/versioning.
  """

  @spec execute(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(request, core_ir, metadata)
      when is_map(request) and is_map(core_ir) and is_map(metadata) do
    request =
      request
      |> Map.put(:elm_executor_core_ir, core_ir)
      |> Map.put(:elm_executor_metadata, metadata)

    case ElmExecutor.Runtime.SemanticExecutor.execute(request) do
      {:ok, result} when is_map(result) ->
        {:ok, annotate_result(result, metadata)}

      {:error, _} = err ->
        err
    end
  end

  @spec execute(map()) :: {:ok, map()} | {:error, term()}
  def execute(request) when is_map(request) do
    metadata =
      case Map.get(request, :elm_executor_metadata) || Map.get(request, "elm_executor_metadata") do
        value when is_map(value) -> value
        _ -> %{}
      end

    case ElmExecutor.Runtime.SemanticExecutor.execute(request) do
      {:ok, result} when is_map(result) -> {:ok, annotate_result(result, metadata)}
      {:error, _} = err -> err
    end
  end

  def execute(_), do: {:error, :invalid_execution_request}

  @spec annotate_result(term(), term()) :: term()
  defp annotate_result(result, metadata) do
    runtime =
      map_field(result, :runtime)
      |> Map.put("engine", "elm_executor_runtime_v1")
      |> Map.put("compiler", "elm_executor")
      |> Map.put("contract", "elm_executor.runtime_executor.v1")
      |> Map.merge(stringify_keys(metadata))

    model_patch =
      map_field(result, :model_patch)
      |> Map.put("elm_executor", runtime)
      |> Map.put("runtime_model_source", Map.get(runtime, "runtime_model_source", "step_message"))

    result
    |> Map.put(:runtime, runtime)
    |> Map.put("runtime", runtime)
    |> Map.put(:model_patch, model_patch)
    |> Map.put("model_patch", model_patch)
  end

  @spec map_field(term(), term()) :: term()
  defp map_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: %{}
  end

  @spec stringify_keys(term()) :: term()
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
