defmodule IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadata do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeModelQuality
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type runtime_input :: SupportTypes.runtime_input()
  @type model_map :: SupportTypes.model_map()

  @debugger_model_metadata_keys ~w(
    last_message
    last_operation
    step_counter
    last_runtime_step_message
    last_runtime_step_op
    runtime_last_message
    runtime_message_source
    runtime_model_source
    runtime_view_output
    runtime_view_output_model_sha256
    runtime_view_tree
    runtime_view_tree_source
    runtime_view_tree_sha256
    runtime_model_sha256
    protocol_last_inbound_message
    protocol_last_inbound_from
    protocol_inbound_count
    protocol_last_trigger
    configuration
  )

  @companion_protocol_runtime_keys ~w(
    status
    protocol_message_count
    protocol_inbound_count
    protocol_outbound_count
    protocol_last_inbound_message
    protocol_last_inbound_from
    colorMode
  )

  @spec public_model(runtime_input() | nil, runtime_input() | nil) :: model_map()
  def public_model(runtime, context_runtime \\ nil) do
    runtime
    |> raw_model()
    |> RuntimeModelQuality.public_runtime_model()
    |> hide_metadata()
    |> hide_companion_protocol(context_runtime || runtime)
    |> drop_undeclared_screen_fields(context_runtime || runtime)
  end

  @spec raw_model(runtime_input() | nil) :: model_map()
  def raw_model(%{} = runtime) do
    Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
  end

  def raw_model(_runtime), do: %{}

  @spec hide_metadata(model_map()) :: model_map()
  def hide_metadata(model) when is_map(model) do
    atom_keys = Enum.map(@debugger_model_metadata_keys, &String.to_atom/1)

    model
    |> Map.drop(@debugger_model_metadata_keys ++ atom_keys)
    |> RuntimeArtifacts.strip_shell_artifacts()
  end

  @spec hide_companion_protocol(model_map(), runtime_input() | nil) :: model_map()
  def hide_companion_protocol(model, runtime) when is_map(model) do
    if companion_protocol_placeholder?(model, runtime) do
      %{}
    else
      Map.drop(model, companion_protocol_drop_keys(runtime))
    end
  end

  @spec companion_protocol_drop_keys(runtime_input() | nil) :: [String.t()]
  defp companion_protocol_drop_keys(%{} = runtime) do
    declared_init_model_keys =
      runtime
      |> RuntimeArtifacts.introspect()
      |> case do
        %{"init_model" => init_model} when is_map(init_model) ->
          init_model |> Map.keys() |> Enum.map(&to_string/1)

        _ ->
          []
      end

    @companion_protocol_runtime_keys
    |> Enum.reject(&(&1 in declared_init_model_keys))
  end

  defp companion_protocol_drop_keys(_runtime), do: @companion_protocol_runtime_keys

  @spec companion_protocol_placeholder?(model_map(), runtime_input() | nil) :: boolean()
  defp companion_protocol_placeholder?(runtime_model, %{} = runtime) when is_map(runtime_model) do
    app_bootstrapped? =
      case RuntimeArtifacts.introspect(runtime) do
        ei when is_map(ei) and map_size(ei) > 0 ->
          true

        _ ->
          runtime
          |> RuntimeArtifacts.execution_model()
          |> RuntimeArtifacts.versioned_elmx_artifacts?()
      end

    not app_bootstrapped? and
      Map.keys(runtime_model)
      |> Enum.map(&to_string/1)
      |> Enum.all?(&(&1 in @companion_protocol_runtime_keys))
  end

  defp companion_protocol_placeholder?(_runtime_model, _runtime), do: false

  @undeclared_screen_fields ~w(screenW screenH displayShape)

  @spec drop_undeclared_screen_fields(model_map(), runtime_input() | nil) :: model_map()
  defp drop_undeclared_screen_fields(model, runtime) when is_map(model) do
    declared = declared_init_model_keys(runtime)

    if MapSet.member?(declared, "settings") or MapSet.member?(declared, "lastLocation") do
      Enum.reduce(@undeclared_screen_fields, model, fn key, acc ->
        if MapSet.member?(declared, key), do: acc, else: Map.delete(acc, key)
      end)
    else
      model
    end
  end

  @spec declared_init_model_keys(runtime_input() | nil) :: MapSet.t()
  defp declared_init_model_keys(%{} = runtime) do
    runtime
    |> RuntimeArtifacts.introspect()
    |> case do
      %{"init_model" => init_model} when is_map(init_model) ->
        init_model |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp declared_init_model_keys(_runtime), do: MapSet.new()
end
