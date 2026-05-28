defmodule Ide.Debugger.CompanionBridge do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.ApiSuffixes
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
        target_suffixes: ApiSuffixes.suffixes("Weather", ["onWeather", "onCurrent", "onForecast"]),
        payload: :weather,
        ok_result_variant: "Current"
      },
      %{
        source: "calendar",
        target_suffixes: ApiSuffixes.suffixes("Calendar", ["onCalendar", "onCurrent", "onUpcoming"]),
        payload: :calendar
      },
      %{
        source: "environment",
        target_suffixes: ApiSuffixes.suffixes("Environment", ["onEnvironment"]),
        payload: :environment
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

  @spec payload(Types.simulator_settings(), atom(), Types.wire_map()) :: Types.companion_bridge_payload()
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
        settings["environment"]
    end
  end

  @spec weather_info(Types.simulator_settings() | nil) :: Types.weather_info_map()
  def weather_info(weather) when is_map(weather) do
    weather
    |> Map.take(["temperatureC", "condition", "humidityPercent", "pressureHpa", "windKph"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def weather_info(_weather), do: %{}

  @spec subscription_message_value(String.t(), String.t(), String.t(), Types.companion_bridge_payload()) ::
          map()
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
          {String.t(), Types.companion_bridge_payload(), map()}
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
