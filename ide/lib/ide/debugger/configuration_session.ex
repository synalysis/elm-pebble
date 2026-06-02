defmodule Ide.Debugger.ConfigurationSession do
  @moduledoc false

  alias Ide.Debugger.CompanionConfiguration
  alias Ide.Debugger.ConfigurationProtocol
  alias Ide.Debugger.ConfigurationSave
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.Types

  @type apply_step_fn ::
          (Types.runtime_state(),
           Types.surface_target(),
           String.t(),
           Types.subscription_payload()
           | map(),
           String.t(),
           String.t() ->
             Types.runtime_state())

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type host :: %{
          required(:apply_step_once) => apply_step_fn(),
          required(:ensure_phone_state) => ensure_phone_fn(),
          required(:contexts) => (-> RuntimeContexts.t())
        }

  @spec save(Types.runtime_state(), String.t(), Types.save_configuration_attrs(), host()) ::
          Types.runtime_state()
  def save(state, project_slug, values, host)
      when is_map(state) and is_binary(project_slug) and is_map(values) and is_map(host) do
    ctx = host.contexts.()
    previous_values = CompanionConfiguration.values_from_state(state)

    state = CompanionConfiguration.attach_to_state(host.ensure_phone_state.(state), project_slug)

    configuration = CompanionConfiguration.configuration_from_state(state)

    previous_encoded_values = ConfigurationProtocol.encode_values(configuration, previous_values)
    encoded_values = ConfigurationProtocol.encode_values(configuration, values)
    changed_values = ConfigurationProtocol.changed_values(encoded_values, previous_encoded_values)

    bridge_event = ConfigurationSave.closed_bridge_event(encoded_values)

    {configuration_message, configuration_message_value} =
      ConfigurationSave.message_payload(state, encoded_values, bridge_event, ctx.companion_bridge)

    seq_before_configuration_update = Map.get(state, :seq, 0)

    state =
      host.apply_step_once.(
        state,
        :companion,
        configuration_message,
        configuration_message_value,
        "configuration",
        "configuration"
      )

    state
    |> ConfigurationSave.maybe_apply_protocol_messages(
      configuration,
      changed_values,
      seq_before_configuration_update,
      ctx.protocol_rx
    )
    |> CompanionConfiguration.attach_to_state(project_slug)
    |> CompanionConfiguration.put_state_values(encoded_values)
    |> RuntimeExecutorConfig.refresh_for_target(:watch)
  end
end
