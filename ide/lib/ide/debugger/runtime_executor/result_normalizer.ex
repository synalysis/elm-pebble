defmodule Ide.Debugger.RuntimeExecutor.ResultNormalizer do
  @moduledoc """
  Normalizes runtime executor wire results into `RuntimeExecutor.Types.execution_result/0`.
  """

  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Types

  @spec normalize(ExecutorTypes.executor_wire_result()) :: ExecutorTypes.execution_result()
  def normalize(result) when is_map(result) do
    %{
      model_patch: map_field(result, :model_patch),
      view_tree: map_or_nil_field(result, :view_tree),
      view_output: list_field(result, :view_output),
      runtime: map_field(result, :runtime),
      protocol_events: list_field(result, :protocol_events),
      followup_messages: list_field(result, :followup_messages)
    }
  end

  @spec normalize_elmc_loose(
          ExecutorTypes.executor_wire_result(),
          ExecutorTypes.execution_input()
        ) ::
          ExecutorTypes.execution_result()
  def normalize_elmc_loose(payload, input) when is_map(payload) and is_map(input) do
    runtime_model = map_field(payload, :runtime_model)
    runtime_view_tree = map_or_nil_field(payload, :view_tree)
    view_output = list_field(payload, :view_output)

    runtime =
      map_field(payload, :runtime)
      |> Map.put_new("engine", "elmc_runtime_adapter_v0")
      |> Map.put_new("source_root", Map.get(input, :source_root))
      |> Map.put_new("rel_path", Map.get(input, :rel_path))

    model_patch =
      %{
        "runtime_model" => runtime_model,
        "runtime_execution_mode" => "runtime_executed",
        "runtime_model_source" => "elmc_runtime",
        "runtime_execution" => runtime
      }
      |> put_runtime_view_output(view_output)

    %{
      model_patch: model_patch,
      view_tree: runtime_view_tree,
      view_output: view_output,
      runtime: runtime,
      protocol_events: list_field(payload, :protocol_events),
      followup_messages: list_field(payload, :followup_messages)
    }
  end

  @spec annotate_backend(
          ExecutorTypes.execution_result(),
          String.t(),
          Types.execution_fallback_reason() | nil
        ) ::
          ExecutorTypes.execution_result()
  def annotate_backend(%{} = payload, backend, reason \\ nil)
      when is_binary(backend) do
    runtime =
      payload
      |> Map.get(:runtime, %{})
      |> Map.put("execution_backend", backend)
      |> Map.put("runtime_mode", runtime_mode_string())
      |> maybe_put_fallback_reason(reason)

    model_patch =
      payload
      |> Map.get(:model_patch, %{})
      |> Map.put("runtime_execution", runtime)
      |> maybe_put_fallback_reason(reason)

    %{payload | model_patch: model_patch, runtime: runtime}
  end

  @spec runtime_mode_string() :: String.t()
  defp runtime_mode_string do
    "runtime_first"
  end

  @spec maybe_put_fallback_reason(
          Types.ExecutionRuntimeSnapshot.wire_map(),
          Types.execution_fallback_reason() | nil
        ) ::
          Types.ExecutionRuntimeSnapshot.wire_map()
  defp maybe_put_fallback_reason(map, nil) when is_map(map), do: map

  defp maybe_put_fallback_reason(map, reason) when is_map(map) do
    Map.put(map, "external_fallback_reason", inspect(reason))
  end

  @spec put_runtime_view_output(Types.RuntimeStepResult.model_patch(), Types.runtime_view_nodes()) ::
          Types.RuntimeStepResult.model_patch()
  def put_runtime_view_output(model_patch, [_ | _] = view_output) when is_map(model_patch) do
    Map.put_new(model_patch, "runtime_view_output", view_output)
  end

  def put_runtime_view_output(model_patch, _view_output) when is_map(model_patch), do: model_patch

  @spec normalize_step_result(ExecutorTypes.execution_result()) ::
          Ide.Debugger.Types.RuntimeStepResult.t()
  def normalize_step_result(%{} = result) do
    %{
      model_patch: Map.get(result, :model_patch, %{}),
      view_tree: Map.get(result, :view_tree),
      view_output: Map.get(result, :view_output, []),
      runtime: Map.get(result, :runtime, %{}),
      protocol_events: Map.get(result, :protocol_events, []),
      followup_messages: Map.get(result, :followup_messages, [])
    }
  end

  @spec map_field(ExecutorTypes.executor_wire_result(), atom()) :: Types.wire_map()
  defp map_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: %{}
  end

  @spec map_or_nil_field(ExecutorTypes.executor_wire_result(), atom()) :: Types.wire_map() | nil
  defp map_or_nil_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: nil
  end

  @spec list_field(ExecutorTypes.executor_wire_result(), atom()) :: list()
  defp list_field(map, key) when is_map(map) and is_atom(key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_list(value), do: value, else: []
  end
end
