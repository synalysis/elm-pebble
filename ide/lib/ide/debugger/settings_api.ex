defmodule Ide.Debugger.SettingsApi do
  @moduledoc false

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SimulatorSettings
  alias Ide.Debugger.SimulatorSettingsApply
  alias Ide.Debugger.Types

  @spec watch_profiles() :: [Types.watch_profile_list_item()]
  def watch_profiles, do: RuntimeSurfaces.watch_profile_list_items()

  @spec default() :: Types.simulator_settings()
  def default, do: SimulatorSettings.default()

  @spec normalize(Types.SimulatorSettings.wire_map()) :: Types.simulator_settings()
  def normalize(settings) when is_map(settings), do: SimulatorSettings.normalize(settings)

  def normalize(_settings), do: SimulatorSettings.default()

  @spec apply_to_state(
          Types.runtime_state(),
          Types.simulator_settings(),
          SimulatorSettingsApply.host()
        ) :: Types.runtime_state()
  def apply_to_state(state, settings, host)
      when is_map(state) and is_map(settings) and is_map(host) do
    state
    |> SessionDefaults.ensure_phone_state()
    |> then(fn prepared ->
      previous_settings = Map.get(prepared, :simulator_settings) || %{}
      SimulatorSettingsApply.apply(prepared, settings, previous_settings, host)
    end)
  end
end
