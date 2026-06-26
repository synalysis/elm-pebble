defmodule Ide.Debugger.Types.SimulatorSettingsSetEventPayload do
  @moduledoc "Payload for `debugger.simulator_settings_set` events."

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:simulator_settings) => Types.simulator_settings(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_settings(Types.simulator_settings()) :: t()
  def from_settings(settings) when is_map(settings), do: %{simulator_settings: settings}
end
