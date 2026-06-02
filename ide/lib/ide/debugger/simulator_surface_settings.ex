defmodule Ide.Debugger.SimulatorSurfaceSettings do
  @moduledoc false

  alias Ide.Debugger.RuntimeModelPreview
  alias Ide.Debugger.SimulatorSettings
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type settings_preview :: %{
          optional(String.t()) => Types.protocol_wire_arg()
        }

  @spec apply_to_state(Types.runtime_state()) :: Types.runtime_state()
  def apply_to_state(state) when is_map(state) do
    settings = SimulatorSettings.normalize(Map.get(state, :simulator_settings))

    state
    |> Map.put(:simulator_settings, settings)
    |> update_surface(:watch, settings)
    |> update_surface(:companion, settings)
    |> update_surface(:phone, settings)
  end

  @spec merge_app_model(Types.app_model(), Types.simulator_settings()) :: Types.app_model()
  def merge_app_model(model, settings) when is_map(model) and is_map(settings) do
    model = Map.put(model, "simulator_settings", settings)

    case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
      runtime_model when is_map(runtime_model) ->
        Map.put(
          model,
          "runtime_model",
          RuntimeModelPreview.merge_matching_fields(runtime_model, preview(settings))
        )

      _ ->
        model
    end
  end

  def merge_app_model(model, _settings) when is_map(model), do: model
  def merge_app_model(_model, _settings), do: %{}

  @spec preview(Types.simulator_settings()) :: settings_preview()
  defp preview(settings) when is_map(settings) do
    %{
      "batteryLevel" => settings["battery_percent"],
      "connected" => settings["connected"],
      "charging" => settings["charging"],
      "timezone_id" => settings["timezone_id"],
      "timezone_offset_min" => settings["timezone_offset_min"],
      "locale" => settings["locale"],
      "language" => settings["language"],
      "region" => settings["region"],
      "network_online" => settings["network_online"],
      "notifications_enabled" => settings["notifications_enabled"],
      "quiet_hours" => settings["quiet_hours"]
    }
  end

  defp update_surface(state, target, settings)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(settings) do
    Surface.update_in_state(state, target, fn surface ->
      Surface.put_app_model(surface, merge_app_model(Surface.app_model(surface), settings))
    end)
  end
end
