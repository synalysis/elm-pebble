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
    screenW
    screenH
    displayShape
    colorMode
  )

  @spec public_model(runtime_input() | nil, runtime_input() | nil) :: model_map()
  def public_model(runtime, context_runtime \\ nil) do
    runtime
    |> raw_model()
    |> RuntimeModelQuality.public_runtime_model()
    |> hide_metadata()
    |> hide_companion_protocol(context_runtime || runtime)
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
      Map.drop(model, @companion_protocol_runtime_keys)
    end
  end

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
end
