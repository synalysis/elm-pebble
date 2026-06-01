defmodule Elmx.Runtime.Executor do
  @moduledoc """
  Debugger execution contract for compiled Elixir Elm apps (`elmx.runtime_executor.v1`).
  """

  alias Elmx.Runtime.Followups
  alias Elmx.Runtime.LaunchContext
  alias Elmx.Runtime.MessageDecode
  alias Elmx.Runtime.Values
  alias Elmx.Runtime.ViewShape
  alias Elmx.Types

  @contract "elmx.runtime_executor.v1"

  @spec execute_generated(module(), map()) :: {:ok, Types.execution_payload()} | {:error, term()}
  def execute_generated(module, request) when is_atom(module) and is_map(request) do
    message = Map.get(request, :message) || Map.get(request, "message")
    message_value = Map.get(request, :message_value) || Map.get(request, "message_value")
    current_model = Map.get(request, :current_model) || Map.get(request, "current_model") || %{}

    launch_context =
      current_model
      |> Map.get("launch_context", Map.get(current_model, :launch_context, %{}))
      |> LaunchContext.normalize()

    runtime_model =
      Map.get(current_model, "runtime_model") || Map.get(current_model, :runtime_model) || %{}

    try do
      {runtime_model, runtime_model_source, commands} =
        if blank_message?(message) do
          init_execution(module, launch_context, runtime_model)
        else
          step_execution(module, message, message_value, runtime_model)
        end

      view_tree = safe_view(module, runtime_model)
      view_output = preview_rows(view_tree)

      {:ok,
       %{
         model_patch: %{
           "runtime_model" => runtime_model,
           "runtime_model_source" => runtime_model_source,
           "elm_executor_mode" => "runtime_executed"
         },
         view_tree: view_tree,
         view_output: view_output,
         runtime: %{
           "engine" => "elmx_runtime_v1",
           "compiler" => "elmx",
           "contract" => @contract,
           "execution_backend" => "compiled_elixir",
           "runtime_model_source" => runtime_model_source
         },
         followup_messages:
           commands_to_followups(commands, Map.get(request, :source_root) || Map.get(request, "source_root")),
         protocol_events: Followups.protocol_events(commands)
       }}
    rescue
      e ->
        {:error, {:elmx_execution_failed, Exception.message(e)}}
    end
  end

  @spec init_execution(module(), map(), map()) :: {map(), String.t(), term()}
  defp init_execution(module, launch_context, previous_runtime_model) do
    if function_exported?(module, :init, 1) do
      {model, cmd} = apply(module, :init, [launch_context])
      {runtime_model, _} = Values.tuple_result_to_model_cmd({model, cmd})
      {merge_runtime_model(previous_runtime_model, runtime_model), "init_model", cmd}
    else
      {previous_runtime_model, "init_model", Values.cmd_none()}
    end
  end

  @spec step_execution(module(), term(), term(), map()) :: {map(), String.t(), term()}
  defp step_execution(module, message, message_value, runtime_model) do
    msg = MessageDecode.decode(message, message_value)

    if function_exported?(module, :update, 2) do
      {model, cmd} = apply(module, :update, [msg, runtime_model_from_elm(runtime_model)])
      {runtime_model, _} = Values.tuple_result_to_model_cmd({model, cmd})
      {runtime_model, "step_message", cmd}
    else
      {runtime_model, "unmapped_message", Values.cmd_none()}
    end
  end

  defp safe_view(module, runtime_model) do
    if function_exported?(module, :view, 1) do
      apply(module, :view, [runtime_model_from_elm(runtime_model)])
      |> normalize_view_tree()
    else
      %{type: "empty", children: []}
    end
  rescue
    _ -> %{type: "previewUnavailable", label: "view evaluation failed", children: []}
  end

  defp normalize_view_tree(tree) do
    tree
    |> ViewShape.normalize()
    |> stringify_view_tree()
  end

  defp stringify_view_tree(%{"type" => type} = node) do
    children =
      (Map.get(node, "children") || [])
      |> Enum.map(&stringify_view_tree/1)

    node
    |> Map.put("type", type)
    |> Map.put("kind", type)
    |> Map.put("children", children)
  end

  defp stringify_view_tree(other), do: %{"type" => "node", "kind" => "node", "label" => inspect(other), "children" => []}

  defp preview_rows(%{"type" => _} = tree), do: [tree]
  defp preview_rows(%{type: type} = tree) when is_binary(type) or is_atom(type),
    do: [stringify_view_tree(Values.wire_value(tree))]

  defp preview_rows(_), do: []

  defp commands_to_followups(cmd, source_root) when is_map(cmd) do
    Followups.from_commands(cmd, source_root: source_root || "watch")
  end

  defp commands_to_followups(_cmd, _source_root), do: []

  defp blank_message?(nil), do: true
  defp blank_message?(""), do: true
  defp blank_message?(_), do: false

  @doc false
  def runtime_model_from_elm(model) when is_map(model) do
    Map.new(model, fn
      {k, %{"ctor" => _, "args" => _} = value} ->
        {to_string(k), from_elm_value(value)}

      {k, v} ->
        {to_string(k), from_elm_value(v)}
    end)
  end

  def runtime_model_from_elm(model), do: model

  defp from_elm_value(%{"ctor" => "True", "args" => []}), do: true
  defp from_elm_value(%{"ctor" => "False", "args" => []}), do: false

  defp from_elm_value(%{"ctor" => ctor, "args" => args}) when is_list(args) do
    ctor_atom = String.to_atom(ctor)
    converted = Enum.map(args, &from_elm_value/1)

    case converted do
      [] -> ctor_atom
      [single] -> {ctor_atom, single}
      many -> List.to_tuple([ctor_atom | many])
    end
  end

  defp from_elm_value(list) when is_list(list), do: Enum.map(list, &from_elm_value/1)

  defp from_elm_value(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), from_elm_value(v)} end)
  end

  defp from_elm_value({ctor, args}) when is_atom(ctor) and is_list(args) do
    converted = Enum.map(args, &from_elm_value/1)

    case converted do
      [] -> ctor
      [single] -> {ctor, single}
      many -> List.to_tuple([ctor | many])
    end
  end

  defp from_elm_value(:True), do: true
  defp from_elm_value(:False), do: false
  defp from_elm_value(v), do: v

  defp merge_runtime_model(previous, model) when is_map(previous) and map_size(previous) > 0 do
    Map.merge(previous, model, fn _k, _prev, next -> next end)
  end

  defp merge_runtime_model(_previous, model), do: model
end
