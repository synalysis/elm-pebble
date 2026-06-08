defmodule Ide.Debugger.CompanionSubscriptionTrigger do
  @moduledoc false

  alias Ide.Debugger.Types

  @type field_value :: boolean() | integer() | String.t()
  @type raw_value :: Types.wire_scalar() | Types.wire_map() | list() | nil

  defmodule ApiSuffixes do
    @moduledoc false

    @spec suffixes(String.t(), [String.t()]) :: [String.t()]
    def suffixes(module, ops) when is_binary(module) and is_list(ops) do
      Enum.flat_map(ops, fn op ->
        [
          ".Pebble.Companion.#{module}.#{op}",
          ".#{module}.#{op}",
          "#{module}.#{op}"
        ]
      end)
    end
  end

  @contracts [
    %{
      source: "battery",
      target_suffixes: ApiSuffixes.suffixes("Battery", ["onBattery"]),
      trigger_slugs: ["on_battery"],
      payload: :battery,
      fields: [
        %{
          key: "percent",
          label: "Percent",
          type: :integer,
          setting: "battery_percent",
          default: 88
        },
        %{key: "charging", label: "Charging", type: :boolean, setting: "charging", default: false}
      ]
    },
    %{
      source: "locale",
      target_suffixes: ApiSuffixes.suffixes("Locale", ["onLocale"]),
      trigger_slugs: ["on_locale"],
      payload: :locale,
      fields: [
        %{key: "locale", label: "Locale", type: :string, setting: "locale", default: "en-US"},
        %{key: "language", label: "Language", type: :string, setting: "language", default: "en"},
        %{key: "region", label: "Region", type: :string, setting: "region", default: "US"},
        %{
          key: "uses24h",
          label: "24-hour clock",
          type: :boolean,
          setting: "clock_24h",
          default: false
        }
      ]
    },
    %{
      source: "network",
      target_suffixes: ApiSuffixes.suffixes("Connectivity", ["onConnectivity"]),
      trigger_slugs: ["on_connectivity"],
      payload: :network,
      plain_result: true,
      fields: [
        %{
          key: "online",
          label: "Online",
          type: :boolean,
          setting: "network_online",
          default: true
        }
      ]
    },
    %{
      source: "notifications",
      target_suffixes: ApiSuffixes.suffixes("Notifications", ["onNotificationStatus"]),
      trigger_slugs: ["on_notification_status"],
      payload: :notifications,
      fields: [
        %{
          key: "quietHours",
          label: "Quiet hours",
          type: :boolean,
          setting: "quiet_hours",
          default: false
        },
        %{
          key: "notificationsEnabled",
          label: "Notifications enabled",
          type: :boolean,
          setting: "notifications_enabled",
          default: true
        }
      ]
    },
    %{
      source: "environment",
      target_suffixes: ApiSuffixes.suffixes("Environment", ["onEnvironment"]),
      trigger_slugs: ["on_environment"],
      payload: :environment,
      fields: [
        %{
          key: "sunriseMin",
          label: "Sunrise (minutes)",
          type: :integer,
          setting: "environment_sunriseMin",
          default: 360
        },
        %{
          key: "sunsetMin",
          label: "Sunset (minutes)",
          type: :integer,
          setting: "environment_sunsetMin",
          default: 1080
        },
        %{
          key: "polarDay",
          label: "Polar day",
          type: :boolean,
          setting: "environment_polarDay",
          default: false
        }
      ]
    },
    %{
      source: "weather",
      target_suffixes: ApiSuffixes.suffixes("Weather", ["onWeather", "onCurrent", "onForecast"]),
      trigger_slugs: ["on_weather", "on_weather_current", "on_weather_forecast"],
      payload: :weather,
      fields: [
        %{
          key: "temperatureC",
          label: "Temperature (°C)",
          type: :integer,
          setting: "weather_temperatureC",
          default: 20
        },
        %{
          key: "condition",
          label: "Condition",
          type: :string,
          setting: "weather_condition",
          default: "clear"
        },
        %{
          key: "humidityPercent",
          label: "Humidity (%)",
          type: :integer,
          setting: "weather_humidityPercent",
          default: 50
        },
        %{
          key: "pressureHpa",
          label: "Pressure (hPa)",
          type: :integer,
          setting: "weather_pressureHpa",
          default: 1013
        },
        %{
          key: "windKph",
          label: "Wind (km/h)",
          type: :integer,
          setting: "weather_windKph",
          default: 0
        }
      ]
    },
    %{
      source: "calendar",
      target_suffixes:
        ApiSuffixes.suffixes("Calendar", ["onCalendar", "onCurrent", "onUpcoming"]),
      trigger_slugs: ["on_calendar", "on_calendar_current", "on_calendar_upcoming"],
      payload: :calendar,
      fields: [
        %{key: "id", label: "ID", type: :string, default: "event-1"},
        %{key: "title", label: "Title", type: :string, default: "Meeting"},
        %{key: "location", label: "Location", type: :string, default: ""},
        %{
          key: "startMillis",
          label: "Start (unix ms)",
          type: :integer,
          default: 1_704_067_200_000
        },
        %{
          key: "endMillis",
          label: "End (unix ms)",
          type: :integer,
          default: 1_704_070_800_000
        },
        %{key: "allDay", label: "All day", type: :boolean, default: false}
      ]
    }
  ]

  @spec contracts() :: [Types.companion_subscription_contract()]
  def contracts, do: @contracts

  @spec companion_trigger?(String.t()) :: boolean()
  def companion_trigger?(trigger) when is_binary(trigger) do
    match?({:ok, _contract}, contract_for_trigger(trigger))
  end

  def companion_trigger?(_trigger), do: false

  @spec contract_for_trigger(String.t()) ::
          {:ok, Types.companion_subscription_contract()} | :error
  def contract_for_trigger(trigger) when is_binary(trigger) do
    case Enum.find(@contracts, &trigger_matches_contract?(trigger, &1)) do
      %{} = contract -> {:ok, contract}
      _ -> :error
    end
  end

  def contract_for_trigger(_trigger), do: :error

  @spec form_data(Types.runtime_state() | nil, String.t(), String.t()) ::
          Types.companion_injection_form_data() | nil
  def form_data(state, trigger, message_constructor) when is_binary(trigger) do
    with {:ok, contract} <- contract_for_trigger(trigger) do
      settings = simulator_settings(state)
      constructor = message_constructor |> to_string() |> String.trim()

      base = %{
        "payload_kind" => "companion_bridge",
        "companion_contract" => Map.fetch!(contract, :source),
        "message_constructor" => constructor,
        "result" => "Ok",
        "error_message" => ""
      }

      field_entries =
        contract
        |> Map.get(:fields, [])
        |> Enum.map(fn field ->
          value = setting_value(settings, field)

          %{
            "key" => field.key,
            "label" => field.label,
            "type" => Atom.to_string(field.type),
            "value" => encode_field_value(field.type, value)
          }
        end)

      flat_fields =
        Enum.reduce(field_entries, %{}, fn field, acc ->
          Map.put(acc, "companion_field_#{field["key"]}", field["value"])
        end)

      base
      |> Map.merge(flat_fields)
      |> Map.put("companion_fields", field_entries)
      |> Map.put("companion_plain_result", Map.get(contract, :plain_result, false))
      |> Map.put("companion_json_payload", false)
    else
      _ -> nil
    end
  end

  def form_data(_state, _trigger, _message_constructor), do: nil

  @spec message_value(Types.wire_map()) :: Types.protocol_ctor_value() | nil
  def message_value(params) when is_map(params) do
    contract_source =
      Map.get(params, "companion_contract") || Map.get(params, :companion_contract)

    constructor = Map.get(params, "message_constructor") || Map.get(params, :message_constructor)

    with source when is_binary(source) <- contract_source,
         %{} = contract <- Enum.find(@contracts, &(Map.fetch!(&1, :source) == source)),
         constructor when is_binary(constructor) <- constructor |> to_string() |> String.trim(),
         true <- constructor != "" do
      if Map.get(contract, :plain_result) == true do
        online = field_param(params, "online") in [true, "true", "True", "1", 1]

        connectivity =
          if(online,
            do: %{"ctor" => "Online", "args" => []},
            else: %{"ctor" => "Offline", "args" => []}
          )

        %{
          "ctor" => constructor,
          "args" => [connectivity]
        }
      else
        result = Map.get(params, "result") || Map.get(params, :result) || "Ok"

        payload = build_record_payload(contract, params)

        result_payload =
          case result do
            "Err" ->
              error =
                Map.get(params, "error_message") || Map.get(params, :error_message) ||
                  "Unavailable"

              %{"ctor" => "Err", "args" => [to_string(error)]}

            _ ->
              %{"ctor" => "Ok", "args" => [payload]}
          end

        %{
          "ctor" => constructor,
          "args" => [result_payload]
        }
      end
    else
      _ -> nil
    end
  end

  def message_value(_params), do: nil

  @spec trigger_matches_contract?(String.t(), Types.companion_subscription_contract()) ::
          boolean()
  defp trigger_matches_contract?(trigger, contract) when is_binary(trigger) do
    normalized = normalize_trigger(trigger)
    suffixes = Map.get(contract, :target_suffixes, []) |> List.wrap()
    slugs = Map.get(contract, :trigger_slugs, []) |> List.wrap()

    Enum.any?(slugs, &(trigger_slug(&1) == trigger_slug(trigger))) or
      Enum.any?(suffixes, fn suffix ->
        suffix_norm = normalize_trigger(suffix)
        String.ends_with?(normalized, suffix_norm)
      end)
  end

  @spec trigger_slug(String.t()) :: String.t()
  defp trigger_slug(trigger) when is_binary(trigger) do
    trigger
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "")
  end

  defp trigger_slug(_trigger), do: ""

  @spec normalize_trigger(String.t()) :: String.t()
  defp normalize_trigger(trigger) when is_binary(trigger) do
    trigger
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_.]/, "")
    |> String.downcase()
    |> String.replace("_", "")
    |> String.replace(".", "")
  end

  defp normalize_trigger(_trigger), do: ""

  @spec simulator_settings(Types.runtime_state() | nil) :: Types.simulator_settings()
  defp simulator_settings(%{} = state) do
    case Map.get(state, :simulator_settings) || Map.get(state, "simulator_settings") do
      %{} = settings -> settings
      _ -> %{}
    end
  end

  defp simulator_settings(_state), do: %{}

  @spec setting_value(Types.simulator_settings(), Types.companion_subscription_field_def()) ::
          field_value()
  defp setting_value(settings, %{type: type, default: default, key: field_key} = field)
       when is_map(settings) do
    lookup_key = Map.get(field, :setting) || field_key

    value =
      Map.get(settings, lookup_key) ||
        nested_setting_value(settings, lookup_key) ||
        calendar_event_setting_value(settings, field_key)

    case value do
      nil ->
        default

      resolved ->
        case type do
          :boolean -> resolved in [true, "true", "1", 1]
          :integer -> normalize_integer(resolved, default)
          _ -> resolved
        end
    end
  end

  defp setting_value(_settings, %{default: default}), do: default

  @spec nested_setting_value(Types.simulator_settings(), String.t()) :: raw_value()
  defp nested_setting_value(settings, "weather_" <> field) do
    get_in(settings, ["weather", field])
  end

  defp nested_setting_value(settings, "environment_" <> field) do
    get_in(settings, ["environment", "sun", field])
  end

  defp nested_setting_value(_settings, _key), do: nil

  @spec calendar_event_setting_value(Types.simulator_settings(), String.t()) :: raw_value()
  defp calendar_event_setting_value(settings, key) when is_map(settings) and is_binary(key) do
    case Map.get(settings, "calendar_events", []) |> List.first() do
      %{} = event -> Map.get(event, key)
      _ -> nil
    end
  end

  defp calendar_event_setting_value(_settings, _key), do: nil

  @spec encode_field_value(atom(), raw_value()) :: String.t()
  defp encode_field_value(:boolean, value),
    do: if(value in [true, "true", "1", 1], do: "true", else: "false")

  defp encode_field_value(:integer, value) when is_integer(value), do: Integer.to_string(value)
  defp encode_field_value(_type, value), do: to_string(value)

  @spec build_record_payload(Types.companion_subscription_contract(), Types.wire_map()) ::
          Types.protocol_ctor_value() | Types.wire_map() | list()
  defp build_record_payload(%{payload: :environment} = contract, params) do
    contract
    |> Map.get(:fields, [])
    |> Enum.reduce(%{}, fn field, acc ->
      Map.put(acc, field.key, decode_field_value(field.type, field_param(params, field.key)))
    end)
    |> then(&%{"sun" => &1})
  end

  defp build_record_payload(%{payload: :calendar} = contract, params) do
    trigger = Map.get(params, "trigger") || Map.get(params, :trigger) || ""
    event = build_calendar_event(contract, params)

    if calendar_current_trigger?(trigger) do
      %{"ctor" => "Just", "args" => [event]}
    else
      [event]
    end
  end

  defp build_record_payload(%{payload: :weather} = contract, params) do
    trigger = Map.get(params, "trigger") || Map.get(params, :trigger) || ""
    info = build_weather_info(contract, params)

    cond do
      weather_current_trigger?(trigger) ->
        info

      weather_forecast_trigger?(trigger) ->
        [info]

      true ->
        %{"ctor" => "Current", "args" => [info]}
    end
  end

  defp build_record_payload(contract, params) do
    contract
    |> Map.get(:fields, [])
    |> Enum.reduce(%{}, fn field, acc ->
      Map.put(acc, field.key, decode_field_value(field.type, field_param(params, field.key)))
    end)
  end

  @spec build_calendar_event(Types.companion_subscription_contract(), Types.wire_map()) ::
          Types.wire_map()
  defp build_calendar_event(contract, params) do
    contract
    |> Map.get(:fields, [])
    |> Enum.reduce(%{}, fn field, acc ->
      Map.put(acc, field.key, decode_field_value(field.type, field_param(params, field.key)))
    end)
    |> drop_blank_calendar_location()
  end

  @spec drop_blank_calendar_location(Types.wire_map()) :: Types.wire_map()
  defp drop_blank_calendar_location(%{"location" => location} = event)
       when location in [nil, ""] do
    Map.delete(event, "location")
  end

  defp drop_blank_calendar_location(event), do: event

  @spec build_weather_info(Types.companion_subscription_contract(), Types.wire_map()) ::
          Types.wire_map()
  defp build_weather_info(contract, params) do
    contract
    |> Map.get(:fields, [])
    |> Enum.reduce(%{}, fn field, acc ->
      Map.put(acc, field.key, decode_field_value(field.type, field_param(params, field.key)))
    end)
  end

  @spec field_param(Types.wire_map(), String.t()) :: raw_value()
  defp field_param(params, key) when is_map(params) and is_binary(key) do
    Map.get(params, "companion_field_" <> key) ||
      Map.get(params, :"companion_field_#{key}") ||
      nested_companion_field(params, key)
  end

  defp field_param(_params, _key), do: nil

  @spec nested_companion_field(Types.wire_map(), String.t()) :: raw_value()
  defp nested_companion_field(params, key) do
    case Map.get(params, "companion_fields") || Map.get(params, :companion_fields) do
      fields when is_list(fields) ->
        Enum.find_value(fields, fn
          %{"key" => ^key, "value" => value} -> value
          %{key: ^key, value: value} -> value
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  @spec decode_field_value(atom(), raw_value()) :: field_value()
  defp decode_field_value(:boolean, value), do: value in [true, "true", "True", "1", 1]
  defp decode_field_value(:integer, value), do: normalize_integer(value, 0)
  defp decode_field_value(_type, value), do: to_string(value || "")

  @spec normalize_integer(raw_value(), integer()) :: integer()
  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  defp normalize_integer(_value, default), do: default

  @spec weather_current_trigger?(String.t()) :: boolean()
  defp weather_current_trigger?(trigger) do
    normalized = normalize_trigger(trigger)

    (String.contains?(normalized, "weather") and String.contains?(normalized, "oncurrent")) or
      normalized == "onweathercurrent"
  end

  @spec weather_forecast_trigger?(String.t()) :: boolean()
  defp weather_forecast_trigger?(trigger) do
    normalized = normalize_trigger(trigger)

    (String.contains?(normalized, "weather") and String.contains?(normalized, "onforecast")) or
      normalized == "onweatherforecast"
  end

  @spec calendar_current_trigger?(String.t()) :: boolean()
  defp calendar_current_trigger?(trigger) do
    normalized = normalize_trigger(trigger)

    (String.contains?(normalized, "calendar") and String.contains?(normalized, "oncurrent")) or
      normalized == "oncalendarcurrent"
  end
end
