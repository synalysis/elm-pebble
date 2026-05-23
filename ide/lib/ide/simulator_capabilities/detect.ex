defmodule Ide.SimulatorCapabilities.Detect do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.ProjectCapabilities.Detect, as: PublishDetect

  @companion_modules %{
    "battery" => "Battery",
    "locale" => "Locale",
    "network" => "Connectivity",
    "notifications" => "Notifications",
    "weather" => "Weather",
    "calendar" => "Calendar",
    "environment" => "Environment",
    "storage" => "Storage",
    "preferences" => "PreferenceStore"
  }

  @watch_battery_names ~w(onBatteryChange batteryLevel battery_level)
  @watch_connection_names ~w(onConnectionChange connectionStatus connection_status)
  @watch_time_names ~w(
    onMinuteChange
    onHourChange
    onSecondChange
    onDayChange
    onMonthChange
    onYearChange
    current_date_time
    getCurrentTimeString
  )

  @spec watch_caps(Types.elm_introspect() | nil) :: MapSet.t(String.t())
  def watch_caps(introspect) when is_map(introspect) do
    MapSet.new()
    |> maybe_put("watch_battery", watch_battery?(introspect))
    |> maybe_put("watch_connection", watch_connection?(introspect))
    |> maybe_put("watch_time", watch_time?(introspect))
  end

  def watch_caps(_), do: MapSet.new()

  @spec phone_caps(Types.elm_introspect() | nil) :: MapSet.t(String.t())
  def phone_caps(introspect) when is_map(introspect) do
    MapSet.new()
    |> maybe_put("geolocation", PublishDetect.location?(introspect))
    |> MapSet.union(companion_caps(introspect))
  end

  def phone_caps(_), do: MapSet.new()

  @spec companion_caps(Types.elm_introspect() | nil) :: MapSet.t(String.t())
  def companion_caps(introspect) when is_map(introspect) do
    for {cap, module_name} <- @companion_modules,
        companion_module?(introspect, module_name),
        into: MapSet.new(),
        do: cap
  end

  def companion_caps(_), do: MapSet.new()

  @spec watch_battery?(Types.elm_introspect()) :: boolean()
  defp watch_battery?(introspect) do
    Enum.any?(subscription_calls(introspect), &watch_name_match?(&1, @watch_battery_names)) or
      Enum.any?(cmd_calls(introspect), &watch_name_match?(&1, @watch_battery_names)) or
      imported_module?(introspect, "Pebble.System")
  end

  @spec watch_connection?(Types.elm_introspect()) :: boolean()
  defp watch_connection?(introspect) do
    Enum.any?(subscription_calls(introspect), &watch_name_match?(&1, @watch_connection_names)) or
      Enum.any?(cmd_calls(introspect), &watch_name_match?(&1, @watch_connection_names)) or
      imported_module?(introspect, "Pebble.System")
  end

  @spec watch_time?(Types.elm_introspect()) :: boolean()
  defp watch_time?(introspect) do
    Enum.any?(subscription_calls(introspect), &watch_name_match?(&1, @watch_time_names)) or
      Enum.any?(cmd_calls(introspect), &watch_name_match?(&1, @watch_time_names)) or
      imported_module?(introspect, "Pebble.Events")
  end

  @spec companion_module?(Types.elm_introspect(), String.t()) :: boolean()
  defp companion_module?(introspect, module_name) when is_binary(module_name) do
    imported_module?(introspect, "Pebble.Companion." <> module_name) or
      imported_module?(introspect, module_name) or
      Enum.any?(subscription_calls(introspect), &companion_call?(&1, module_name)) or
      Enum.any?(cmd_calls(introspect), &companion_call?(&1, module_name))
  end

  @spec companion_call?(map(), String.t()) :: boolean()
  defp companion_call?(row, module_name) do
    target = call_target(row)

    String.contains?(target, "Companion." <> module_name) or
      String.contains?(target, "Pebble.Companion." <> module_name) or
      String.contains?(target, "." <> module_name <> ".")
  end

  @spec watch_name_match?(map(), [String.t()]) :: boolean()
  defp watch_name_match?(row, names) do
    name = call_name(row)
    target = call_target(row)

    name in names or
      Enum.any?(names, fn pattern ->
        String.contains?(target, pattern) or String.contains?(target, "PebbleWatch." <> pattern)
      end)
  end

  @spec imported_module?(Types.elm_introspect(), String.t()) :: boolean()
  defp imported_module?(introspect, module_name) do
    introspect
    |> Map.get("imported_modules", [])
    |> List.wrap()
    |> Enum.any?(fn
      imported when is_binary(imported) ->
        imported == module_name or String.ends_with?(imported, "." <> module_name)

      _ ->
        false
    end)
  end

  @spec maybe_put(MapSet.t(String.t()), String.t(), boolean()) :: MapSet.t(String.t())
  defp maybe_put(set, _name, false), do: set
  defp maybe_put(set, name, true), do: MapSet.put(set, name)

  @spec cmd_calls(Types.elm_introspect()) :: [Types.cmd_call()]
  defp cmd_calls(introspect) when is_map(introspect) do
    init_calls = Map.get(introspect, "init_cmd_calls", [])
    update_calls = Map.get(introspect, "update_cmd_calls", [])

    function_calls =
      introspect
      |> Map.get("function_cmd_calls", %{})
      |> Map.values()
      |> List.flatten()

    init_calls ++ update_calls ++ function_calls
  end

  @spec subscription_calls(Types.elm_introspect()) :: [Types.cmd_call()]
  defp subscription_calls(introspect) when is_map(introspect),
    do: Map.get(introspect, "subscription_calls", [])

  @spec call_target(Types.cmd_call()) :: String.t()
  defp call_target(row) do
    row
    |> Map.get("target", Map.get(row, :target, ""))
    |> to_string()
  end

  @spec call_name(Types.cmd_call()) :: String.t()
  defp call_name(row) do
    row
    |> Map.get("name", Map.get(row, :name, ""))
    |> to_string()
  end
end
