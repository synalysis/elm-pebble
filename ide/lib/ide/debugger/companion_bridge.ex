defmodule Ide.Debugger.CompanionBridge do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.ApiSuffixes
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.Types

  @spec configuration_contract() :: Types.api_suffix_contract()
  def configuration_contract do
    %{
      target_suffixes:
        ApiSuffixes.suffixes("Configuration", ["onConfiguration", "onClosed"]) ++
          ApiSuffixes.suffixes("GeneratedPreferences", ["onConfiguration", "onClosed"])
    }
  end

  @spec geolocation_contract() :: Types.api_suffix_contract()
  def geolocation_contract do
    %{target_suffixes: ApiSuffixes.suffixes("Geolocation", ["onCurrentPosition"])}
  end

  @spec storage_contract() :: Types.api_suffix_contract()
  def storage_contract do
    %{target_suffixes: ApiSuffixes.suffixes("Storage", ["onStorage"])}
  end

  @spec preferences_contract() :: Types.api_suffix_contract()
  def preferences_contract do
    %{target_suffixes: ApiSuffixes.suffixes("PreferenceStore", ["onPreference"])}
  end

  @spec subscription_contracts() :: [Types.companion_subscription_contract()]
  def subscription_contracts do
    [
      %{
        source: "battery",
        target_suffixes: ApiSuffixes.suffixes("Battery", ["onBattery"]),
        payload: :battery
      },
      %{
        source: "locale",
        target_suffixes: ApiSuffixes.suffixes("Locale", ["onLocale"]),
        payload: :locale
      },
      %{
        source: "network",
        target_suffixes: ApiSuffixes.suffixes("Connectivity", ["onConnectivity"]),
        payload: :network,
        plain_result: true
      },
      %{
        source: "notifications",
        target_suffixes: ApiSuffixes.suffixes("Notifications", ["onNotificationStatus"]),
        payload: :notifications
      },
      %{
        source: "weather",
        target_suffixes:
          ApiSuffixes.suffixes("Weather", ["onWeather", "onCurrent", "onForecast"]),
        payload: :weather,
        ok_result_variant: "Current"
      },
      %{
        source: "calendar",
        target_suffixes:
          ApiSuffixes.suffixes("Calendar", ["onCalendar", "onCurrent", "onUpcoming"]),
        payload: :calendar
      },
      %{
        source: "environment",
        target_suffixes: ApiSuffixes.suffixes("Environment", ["onEnvironment"]),
        payload: :environment
      },
      %{
        source: "timeline",
        target_suffixes: ApiSuffixes.suffixes("Timeline", ["onToken", "onCommands"]),
        payload: :timeline
      }
    ]
  end

  @spec sources() :: [String.t()]
  def sources do
    subscription_contracts() |> Enum.map(&Map.fetch!(&1, :source))
  end

  @spec contract_for_source(String.t()) :: Types.companion_subscription_contract() | nil
  def contract_for_source(source) when is_binary(source) do
    Enum.find(subscription_contracts(), &(Map.fetch!(&1, :source) == source))
  end

  @spec payload(Types.simulator_settings(), atom(), Types.companion_bridge_request()) ::
          Types.companion_bridge_payload()
  def payload(settings, :calendar, request) when is_map(settings) and is_map(request) do
    events = settings["calendar_events"]

    case Map.get(request, :op) do
      "nextEvent" -> List.first(events)
      "subscribe" -> events
      _ -> events
    end
  end

  def payload(settings, :weather, request)
      when is_map(settings) and is_map(request) do
    weather = weather_info(settings["weather"])

    case Map.get(request, :op) do
      "forecast" -> [weather]
      "subscribe" -> %{"ctor" => "Current", "args" => [weather]}
      _ -> weather
    end
  end

  def payload(settings, :network, _request) when is_map(settings) do
    bool_setting(settings, "network_online", true)
  end

  def payload(settings, kind, _request) when is_map(settings) and is_atom(kind) do
    case kind do
      :battery ->
        %{"percent" => settings["battery_percent"], "charging" => settings["charging"]}

      :locale ->
        %{
          "locale" => settings["locale"],
          "language" => settings["language"],
          "region" => settings["region"],
          "uses24h" => settings["clock_24h"]
        }

      :notifications ->
        %{
          "quietHours" => settings["quiet_hours"],
          "notificationsEnabled" => settings["notifications_enabled"]
        }

      :environment ->
        environment_info(settings["environment"])

      :timeline ->
        settings["companion_timeline_token"] || "demo-timeline-token"
    end
  end

  def payload(_settings, :timeline, %{op: "insertPin"}) do
    %{}
  end

  @spec weather_info(Types.simulator_settings() | nil) :: Types.weather_info_map()
  def weather_info(weather) when is_map(weather) do
    weather
    |> Map.take(["temperatureC", "condition", "humidityPercent", "pressureHpa", "windKph", "windDirectionDeg"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> normalize_weather_info_fields()
  end

  def weather_info(_weather), do: %{}

  @spec normalize_weather_info_fields(Types.wire_map()) :: Types.wire_map()
  defp normalize_weather_info_fields(info) when is_map(info) do
    info
    |> normalize_weather_condition_field()
    |> wrap_optional_weather_int_field("humidityPercent")
    |> wrap_optional_weather_int_field("pressureHpa")
    |> wrap_optional_weather_int_field("windKph")
    |> wrap_optional_weather_int_field("windDirectionDeg")
  end

  defp normalize_weather_condition_field(info) do
    case Map.get(info, "condition") do
      %{"ctor" => ctor, "args" => []} when is_binary(ctor) ->
        info

      %{"$ctor" => ctor, "args" => []} when is_binary(ctor) ->
        Map.put(info, "condition", %{"ctor" => ctor, "args" => []})

      condition when is_binary(condition) ->
        Map.put(
          info,
          "condition",
          ProtocolEvents.weather_condition_from_settings(%{"weather" => %{"condition" => condition}})
        )

      _ ->
        info
    end
  end

  defp wrap_optional_weather_int_field(info, key) when is_map(info) and is_binary(key) do
    case Map.get(info, key) do
      value when is_integer(value) -> Map.put(info, key, wire_just(value))
      %{"ctor" => _} = value -> Map.put(info, key, value)
      _ -> info
    end
  end

  @spec environment_info(Types.simulator_settings() | nil) :: Types.environment_info_map()
  def environment_info(environment) when is_map(environment) do
    %{}
    |> Map.put("sun", maybe_wire_value(Map.get(environment, "sun"), &sun_info/1))
    |> Map.put("moon", maybe_wire_value(Map.get(environment, "moon"), &moon_info/1))
    |> Map.put("tide", maybe_wire_value(Map.get(environment, "tide"), &tide_info/1))
  end

  def environment_info(_environment) do
    %{
      "sun" => wire_nothing(),
      "moon" => wire_nothing(),
      "tide" => wire_nothing()
    }
  end

  defp sun_info(sun) when is_map(sun) do
    %{}
    |> maybe_put("sunriseMin", coerce_sun_int(Map.get(sun, "sunriseMin")))
    |> maybe_put("sunsetMin", coerce_sun_int(Map.get(sun, "sunsetMin")))
    |> maybe_put("polarDay", coerce_polar_day(Map.get(sun, "polarDay")))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp coerce_sun_int(value) when is_integer(value), do: value

  defp coerce_sun_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp coerce_sun_int(_value), do: nil

  defp coerce_polar_day(true), do: true
  defp coerce_polar_day(false), do: false

  defp coerce_polar_day(value) when is_binary(value) do
    value |> String.downcase() |> then(&(&1 in ["true", "1", "yes"]))
  end

  defp coerce_polar_day(_value), do: false

  defp moon_info(moon) when is_map(moon) do
    %{}
    |> maybe_put("moonriseMin", maybe_int_wire_value(Map.get(moon, "moonriseMin")))
    |> maybe_put("moonsetMin", maybe_int_wire_value(Map.get(moon, "moonsetMin")))
    |> maybe_put("phaseE6", Map.get(moon, "phaseE6"))
  end

  defp tide_info(tide) when is_map(tide) do
    tide
    |> Map.take(["nextMin", "levelCm", "rising"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_wire_value(%{"ctor" => ctor} = value, _normalize)
       when ctor in ["Just", "Nothing"] do
    value
  end

  defp maybe_wire_value(%{"$ctor" => ctor} = value, _normalize)
       when ctor in ["Just", "Nothing"] do
    ProtocolEvents.CmdCall.normalize_elmc_wire_ctor(value)
  end

  defp maybe_wire_value(nil, _normalize), do: wire_nothing()

  defp maybe_wire_value(value, normalize) when is_function(normalize, 1) do
    wire_just(normalize.(value))
  end

  defp maybe_int_wire_value(%{"ctor" => ctor} = value) when ctor in ["Just", "Nothing"], do: value

  defp maybe_int_wire_value(%{"$ctor" => ctor} = value) when ctor in ["Just", "Nothing"] do
    ProtocolEvents.CmdCall.normalize_elmc_wire_ctor(value)
  end

  defp maybe_int_wire_value(value) when is_integer(value), do: wire_just(value)
  defp maybe_int_wire_value(_value), do: wire_nothing()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp wire_just(value), do: %{"ctor" => "Just", "args" => [value]}
  defp wire_nothing, do: %{"ctor" => "Nothing", "args" => []}

  @spec subscription_message_value(
          String.t(),
          String.t(),
          String.t(),
          Types.companion_bridge_payload()
        ) ::
          Types.protocol_ctor_value()
  def subscription_message_value("weather", callback, result_ctor, payload) do
    wrapped_payload = wrap_weather_ok_payload(result_ctor, payload, "Current")
    subscription_result_message_value(callback, result_ctor, wrapped_payload)
  end

  def subscription_message_value(_api, callback, result_ctor, payload) do
    subscription_result_message_value(callback, result_ctor, payload)
  end

  @spec wrap_weather_ok_payload(String.t(), Types.companion_bridge_payload(), String.t()) ::
          Types.companion_bridge_payload()
  def wrap_weather_ok_payload("Ok", %{"ctor" => variant, "args" => [info | _]}, _default_variant)
      when is_binary(variant) and is_map(info) do
    %{"ctor" => variant, "args" => [weather_info(info)]}
  end

  def wrap_weather_ok_payload("Ok", info, default_variant) when is_map(info) do
    %{"ctor" => default_variant, "args" => [weather_info(info)]}
  end

  def wrap_weather_ok_payload(_result_ctor, payload, _default_variant), do: payload

  @spec plain_connectivity_parts(String.t(), Types.companion_connectivity_callback_result()) ::
          {String.t(), Types.companion_bridge_payload(), Types.protocol_ctor_value()}
  def plain_connectivity_parts(callback, result) when is_binary(callback) do
    connectivity =
      case result do
        {:ok, true} -> %{"ctor" => "Online", "args" => []}
        {:ok, false} -> %{"ctor" => "Offline", "args" => []}
        {:ok, value} -> value
        _ -> %{"ctor" => "Offline", "args" => []}
      end

    {"plain", connectivity, %{"ctor" => callback, "args" => [connectivity]}}
  end

  @spec callback_result_parts(Types.companion_callback_result()) ::
          {String.t(), Types.companion_bridge_payload()}
  def callback_result_parts(result) do
    case result do
      {:ok, value} -> {"Ok", value}
      {:error, message} -> {"Err", message}
    end
  end

  @spec subscription_result_message_value(String.t(), String.t(), Types.subscription_payload()) ::
          Types.protocol_ctor_value()
  def subscription_result_message_value(callback, result_ctor, payload)
      when is_binary(callback) and is_binary(result_ctor) do
    %{
      "ctor" => callback,
      "args" => [
        %{
          "ctor" => result_ctor,
          "args" => [payload]
        }
      ]
    }
  end

  defp bool_setting(settings, key, default) when is_map(settings) do
    case Map.get(settings, key) || Map.get(settings, to_string(key)) do
      value when is_boolean(value) -> value
      _ -> default
    end
  end
end
