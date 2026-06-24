defmodule Ide.PackageDocs.NativeApiLinks do
  @moduledoc false

  @base_url "https://developer.repebble.com/docs/c"

  @module_paths %{
    "Pebble.Accel" => ["Foundation/Event_Service/AccelerometerService"],
    "Pebble.AppFocus" => ["Foundation/Event_Service/AppFocusService"],
    "Pebble.Button" => ["User_Interface/Clicks"],
    "Pebble.Cmd" => ["Foundation/Timer"],
    "Pebble.Compass" => ["Foundation/Event_Service/CompassService"],
    "Pebble.DataLog" => ["Foundation/DataLogging"],
    "Pebble.Dictation" => ["Foundation/Dictation"],
    "Pebble.Events" => ["Foundation/Event_Service/TickTimerService"],
    "Pebble.Health" => ["Foundation/Event_Service/HealthService"],
    "Pebble.Light" => ["User_Interface/Light"],
    "Pebble.Log" => ["Foundation/Logging"],
    "Pebble.Platform" => ["Foundation/App"],
    "Pebble.Storage" => ["Foundation/Storage"],
    "Pebble.System" => [
      "Foundation/Event_Service/BatteryStateService",
      "Foundation/Event_Service/ConnectionService"
    ],
    "Pebble.Time" => ["Foundation/Wall_Time"],
    "Pebble.Ui" => ["Graphics/Drawing_Primitives"],
    "Pebble.Ui.Resources" => ["Graphics/Fonts"],
    "Pebble.UnobstructedArea" => ["User_Interface/UnobstructedArea"],
    "Pebble.Vibes" => ["User_Interface/Vibes"],
    "Pebble.Wakeup" => ["Foundation/Wakeup"],
    "Pebble.Speaker" => ["User_Interface/Speaker"],
    "Pebble.Frame" => ["Foundation/Event_Service/TickTimerService"],
    "Pebble.WatchInfo" => ["Foundation/WatchInfo"],
    "Pebble.Companion.Preferences" => ["User_Interface/Preferences"]
  }

  alias Ide.PackageDocs.NativeApiLinks.Types, as: LinkTypes

  @spec links_for_module(String.t()) :: [LinkTypes.api_link()]
  def links_for_module(module_name) when is_binary(module_name) do
    @module_paths
    |> Map.get(module_name, [])
    |> Enum.map(&link_entry/1)
  end

  def links_for_module(_module_name), do: []

  @spec link_entry(String.t()) :: LinkTypes.api_link()
  defp link_entry(path) when is_binary(path) do
    %{
      "label" => path |> String.split("/") |> List.last(),
      "url" => @base_url <> "/" <> path <> "/"
    }
  end
end
