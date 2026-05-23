defmodule Ide.ProjectCapabilities.Detect do
  @moduledoc "Internal capability detection."

  alias Ide.Debugger.Types

  @geolocation_commands ~w(currentPosition getCurrentPosition watch clearWatch)
  @geolocation_subscriptions ~w(onCurrentPosition onWatchPosition)

  @configuration_commands ~w(open subscribe)
  @configuration_subscriptions ~w(onConfiguration onClosed)

  @health_api_commands ~w(value sumToday sum accessible onEvent)

  @spec phone_caps(Types.elm_introspect()) :: MapSet.t(String.t())
  def phone_caps(introspect) do
    MapSet.new(cap_names(introspect))
  end

  @spec watch_caps(Types.elm_introspect()) :: MapSet.t(String.t())
  def watch_caps(introspect) do
    MapSet.new(watch_cap_names(introspect))
  end

  @spec cap_names(Types.elm_introspect()) :: [String.t()]
  defp cap_names(introspect) do
    []
    |> Kernel.++(location_cap_names(introspect))
    |> Kernel.++(configuration_cap_names(introspect))
  end

  @spec watch_cap_names(Types.elm_introspect()) :: [String.t()]
  defp watch_cap_names(introspect), do: cap_name_when(introspect, &health?/1, "health")

  @spec location_cap_names(Types.elm_introspect()) :: [String.t()]
  defp location_cap_names(introspect), do: cap_name_when(introspect, &location?/1, "location")

  @spec configuration_cap_names(Types.elm_introspect()) :: [String.t()]
  defp configuration_cap_names(introspect),
    do: cap_name_when(introspect, &configurable?/1, "configurable")

  @spec cap_name_when(Types.elm_introspect(), (Types.elm_introspect() -> boolean()), String.t()) ::
          [String.t()]
  @dialyzer :no_match
  defp cap_name_when(introspect, predicate, name) when is_function(predicate, 1) do
    for cap <- [name], predicate.(introspect), do: cap
  end

  @spec location?(Types.elm_introspect()) :: boolean()
  def location?(introspect) when is_map(introspect) do
    Enum.any?(cmd_calls(introspect), &geolocation_command?/1) or
      Enum.any?(subscription_calls(introspect), &geolocation_subscription?/1)
  end

  @spec configurable?(Types.elm_introspect()) :: boolean()
  def configurable?(introspect) when is_map(introspect) do
    Enum.any?(cmd_calls(introspect), &configuration_command?/1) or
      Enum.any?(subscription_calls(introspect), &configuration_subscription?/1)
  end

  @spec health?(Types.elm_introspect()) :: boolean()
  def health?(introspect) when is_map(introspect) do
    Enum.any?(cmd_calls(introspect), &health_command?/1) or
      Enum.any?(subscription_calls(introspect), &health_subscription?/1)
  end

  @spec geolocation_command?(Types.cmd_call()) :: boolean()
  defp geolocation_command?(row) do
    (call_target_module?(row, "Geolocation") and call_name(row) in @geolocation_commands) or
      task_source_module?(row, "Geolocation")
  end

  @spec geolocation_subscription?(map()) :: boolean()
  defp geolocation_subscription?(row) do
    call_name(row) in @geolocation_subscriptions or
      (call_target_module?(row, "Geolocation") and call_name(row) in @geolocation_subscriptions)
  end

  @spec configuration_command?(map()) :: boolean()
  defp configuration_command?(row) do
    (call_target_module?(row, "Configuration") and call_name(row) in @configuration_commands) or
      task_source_module?(row, "Configuration") or
      Enum.any?(arg_value_calls(row), &configuration_call_source?/1)
  end

  @spec configuration_subscription?(map()) :: boolean()
  defp configuration_subscription?(row) do
    call_name(row) in @configuration_subscriptions or
      String.ends_with?(call_target(row), ".onConfiguration") or
        String.ends_with?(call_target(row), ".onClosed")
  end

  @spec health_command?(map()) :: boolean()
  defp health_command?(row) do
    (health_target?(call_target(row)) and call_name(row) in @health_api_commands) or
      task_source_module?(row, "Health")
  end

  @spec health_subscription?(map()) :: boolean()
  defp health_subscription?(row) do
    target = call_target(row)

    health_target?(target) and call_name(row) == "onEvent" or
      String.contains?(target, "onHealthEvent")
  end

  @spec health_target?(String.t()) :: boolean()
  defp health_target?(target) when is_binary(target) do
    String.contains?(target, "Pebble.Health") or
      String.contains?(target, "Health.") or
      String.contains?(target, "PebbleWatch.onHealthEvent") or
      String.contains?(target, "Elm.Kernel.PebbleWatch.onHealthEvent")
  end

  @spec task_source_module?(map(), String.t()) :: boolean()
  defp task_source_module?(row, module_name) when is_binary(module_name) do
    row
    |> Map.get("task_sources", [])
    |> List.wrap()
    |> Enum.any?(fn source ->
      is_binary(source) and String.starts_with?(source, module_name <> ".")
    end)
  end

  @spec arg_value_calls(map()) :: [String.t()]
  defp arg_value_calls(row) do
    row
    |> Map.get("arg_values", [])
    |> List.wrap()
    |> Enum.flat_map(&collect_arg_calls/1)
  end

  @spec collect_arg_calls(map()) :: [String.t()]
  defp collect_arg_calls(%{"$call" => call}) when is_binary(call), do: [call]
  defp collect_arg_calls(_), do: []

  @spec configuration_call_source?(String.t()) :: boolean()
  defp configuration_call_source?(source) when is_binary(source) do
    parts = String.split(source, ".")

    Enum.at(parts, 0) == "Configuration" and Enum.at(parts, 1) in @configuration_commands
  end

  @spec call_target_module?(map(), String.t()) :: boolean()
  defp call_target_module?(row, module_name) when is_binary(module_name) do
    target = call_target(row)

    is_binary(target) and
      (String.contains?(target, module_name <> ".") or
         String.contains?(target, "Companion." <> module_name) or
         String.contains?(target, "Pebble.Companion." <> module_name))
  end

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
