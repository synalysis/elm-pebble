defmodule Elmx.Runtime.Executor do
  @moduledoc """
  Debugger execution contract for compiled Elixir Elm apps (`elmx.runtime_executor.v1`).
  """

  alias Elmx.Runtime.Executor.{Model, Run, Subscriptions, View}
  alias Elmx.Runtime.Followups
  alias Elmx.Runtime.LaunchContext
  alias Elmx.Types

  @contract "elmx.runtime_executor.v1"

  @spec contract() :: String.t()
  def contract, do: @contract

  @doc """
  Evaluates `view/1` for the current runtime model without running `init/1` or `update/2`.
  """
  @spec view_generated(module(), Types.executor_request()) ::
          {:ok, Types.view_preview_payload()} | {:error, Types.execution_error()}
  def view_generated(module, request) when is_atom(module) and is_map(request) do
    {_launch_context, runtime_model} = request_context(request)

    try do
      view_tree = View.safe_view(module, runtime_model)

      {:ok,
       %{
         view_tree: view_tree,
         view_output: View.preview_rows(view_tree, request, runtime_model)
       }}
    rescue
      e ->
        {:error, {:elmx_execution_failed, Exception.message(e)}}
    end
  end

  @spec execute_generated(module(), Types.executor_request()) ::
          {:ok, Types.execution_payload()} | {:error, Types.execution_error()}
  def execute_generated(module, request) when is_atom(module) and is_map(request) do
    message = Map.get(request, :message) || Map.get(request, "message")
    message_value = Map.get(request, :message_value) || Map.get(request, "message_value")
    {launch_context, runtime_model} = request_context(request)

    try do
      {runtime_model, runtime_model_source, commands} =
        if Run.blank_message?(message) do
          Run.init_execution(module, launch_context, runtime_model)
        else
          Run.step_execution(module, message, message_value, runtime_model)
        end

      view_tree = View.safe_view(module, runtime_model)
      view_output = View.preview_rows(view_tree, request, runtime_model)
      active_subscriptions = Subscriptions.evaluate(module, runtime_model)

      {:ok,
       %{
         model_patch: %{
           "runtime_model" => runtime_model,
           "runtime_model_source" => runtime_model_source,
           "runtime_execution_mode" => "runtime_executed",
           "active_subscriptions" => active_subscriptions
         },
         view_tree: view_tree,
         view_output: view_output,
         runtime: %{
           "engine" => "elmx_runtime_v1",
           "compiler" => "elmx",
           "contract" => @contract,
           "execution_backend" => "compiled_elixir",
           "runtime_model_source" => runtime_model_source,
           "operation_source" => runtime_model_source
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

  @doc false
  defdelegate runtime_model_from_elm(model), to: Model

  @spec request_context(Types.executor_request()) ::
          {Types.launch_context(), Types.runtime_model()}
  defp request_context(request) do
    current_model = Map.get(request, :current_model) || Map.get(request, "current_model") || %{}

    launch_context =
      current_model
      |> Map.get("launch_context", Map.get(current_model, :launch_context, %{}))
      |> LaunchContext.normalize()

    runtime_model =
      current_model
      |> Map.get("runtime_model", Map.get(current_model, :runtime_model, %{}))
      |> sync_launch_screen_fields(launch_context)

    {launch_context, runtime_model}
  end

  @spec sync_launch_screen_fields(Types.runtime_model(), Types.launch_context()) ::
          Types.runtime_model()
  defp sync_launch_screen_fields(runtime_model, launch_context)
       when is_map(runtime_model) and is_map(launch_context) do
    screen = Map.get(launch_context, "screen") || %{}

    runtime_model
    |> maybe_put_screen_dimension("screenW", Map.get(screen, "width"))
    |> maybe_put_screen_dimension("screenH", Map.get(screen, "height"))
    |> maybe_put_display_shape(Map.get(screen, "shape"))
  end

  defp sync_launch_screen_fields(runtime_model, _launch_context) when is_map(runtime_model),
    do: runtime_model

  defp sync_launch_screen_fields(_runtime_model, _launch_context), do: %{}

  defp maybe_put_screen_dimension(model, key, value)
       when is_map(model) and is_binary(key) and is_integer(value) and value > 0 do
    if Map.has_key?(model, key) or Map.has_key?(model, String.to_atom(key)) do
      Map.put(model, key, value)
    else
      model
    end
  end

  defp maybe_put_screen_dimension(model, _key, _value), do: model

  defp maybe_put_display_shape(model, %{"ctor" => _, "args" => _} = shape)
       when is_map(model) and is_map(shape) do
    if Map.has_key?(model, "displayShape") or Map.has_key?(model, :displayShape) do
      Map.put(model, "displayShape", shape)
    else
      model
    end
  end

  defp maybe_put_display_shape(model, _), do: model

  defp commands_to_followups(cmd, source_root) when is_map(cmd) do
    Followups.from_commands(cmd, source_root: source_root || "watch")
  end
end
