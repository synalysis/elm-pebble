defmodule Ide.Debugger.SubscriptionActivation do
  @moduledoc false

  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.TriggerCandidate

  @spec model_active?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  def model_active?(state, target, row)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    active = RuntimeActiveSubscriptions.for_surface(state, target)

    if RuntimeActiveSubscriptions.present?(state, target) do
      RuntimeActiveSubscriptions.row_active?(row, active)
    else
      true
    end
  end

  def model_active?(_state, _target, _row), do: true
end
