defmodule Ide.Debugger.SubscriptionApi do
  @moduledoc false

  alias Ide.Debugger.RuntimeHub
  alias Ide.Debugger.SubscriptionActivation
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.TriggerDisplay
  alias Ide.Debugger.Types

  @spec injection_modal_supported?(
          Types.runtime_state(),
          Types.replay_row() | Types.TriggerCandidate.wire_map(),
          RuntimeHub.config()
        ) :: boolean()
  def injection_modal_supported?(state, row, hub_config) when is_map(state) and is_map(row) and is_map(hub_config) do
    SubscriptionTriggerWire.injection_modal_supported?(
      state,
      row,
      RuntimeHub.contexts(hub_config).trigger_wire
    )
  end

  def injection_modal_supported?(_state, _row, _hub_config), do: false

  @spec model_active?(Types.runtime_state(), Types.surface_target(), Types.TriggerCandidate.wire_map()) ::
          boolean()
  def model_active?(state, target, row),
    do: SubscriptionActivation.model_active?(state, target, row)

  @spec trigger_display_label(Types.runtime_state(), String.t(), String.t()) :: String.t()
  def trigger_display_label(state, trigger, target_name),
    do: TriggerDisplay.label_for(state, trigger, target_name, TriggerDisplay.default_host())

  defdelegate trigger_display(op, trigger), to: TriggerCandidates, as: :subscription_trigger_display
end
