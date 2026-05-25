defmodule Ide.Debugger.Types.SimulatorSettingsSetEventPayload do
  @moduledoc "Payload for `debugger.simulator_settings_set` events."

  alias Ide.Debugger.Types.SimulatorSettings

  @type t :: %{
          optional(:simulator_settings) => SimulatorSettings.t() | map(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec from_settings(SimulatorSettings.t() | map()) :: t()
  def from_settings(settings) when is_map(settings), do: %{simulator_settings: settings}
end
