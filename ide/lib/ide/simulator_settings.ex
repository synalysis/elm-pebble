defmodule Ide.SimulatorSettings do
  @moduledoc """
  Canonical simulator settings catalog, normalization, and capability-filtered field groups.
  """

  alias Ide.Debugger
  alias Ide.Debugger.Types
  alias Ide.Projects.Project
  alias Ide.SimulatorCapabilities

  @type t :: Types.simulator_settings()

  @type form_params :: %{optional(String.t()) => Types.wire_input()}
  @type display_values :: %{optional(String.t()) => Types.wire_input()}

  @type field_type :: :range | :checkbox | :text | :number | :date | :time | :select | :json
  @type field_spec :: %{
          key: String.t(),
          type: field_type(),
          label: String.t(),
          capabilities: [String.t()],
          group: atom(),
          optional: boolean(),
          debugger_only: boolean(),
          min: number() | nil,
          max: number() | nil,
          step: number() | nil,
          options: [{String.t(), String.t()}] | nil,
          hint: String.t() | nil
        }

  @group_titles %{
    watch_device: "Battery & connection",
    watch_time: "Watch time",
    companion_battery: "Phone battery",
    companion_locale: "Locale & timezone",
    companion_network: "Network",
    companion_notifications: "Notifications",
    companion_weather: "Weather",
    companion_calendar: "Calendar",
    companion_environment: "Environment",
    companion_geolocation: "Geolocation",
    companion_storage: "Storage",
    companion_preferences: "Preferences",
    watch_sensors: "Sensors & input",
    watch_platform: "Platform & launch",
    emulator_extras: "Emulator"
  }

  @fields [
    %{
      key: "battery_percent",
      type: :range,
      label: "Battery",
      capabilities: ["watch_battery", "battery"],
      group: :watch_device,
      min: 0,
      max: 100,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "charging",
      type: :checkbox,
      label: "Charging",
      capabilities: ["watch_battery", "battery"],
      group: :watch_device,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "connected",
      type: :checkbox,
      label: "Bluetooth connected",
      capabilities: ["watch_connection"],
      group: :watch_device,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "clock_24h",
      type: :checkbox,
      label: "24h time",
      capabilities: ["watch_time", "locale"],
      group: :watch_time,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "use_simulated_time",
      type: :checkbox,
      label: "Use simulated time",
      capabilities: ["watch_time"],
      group: :watch_time,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      debugger_only: true,
      hint: "Disable to use the current host clock."
    },
    %{
      key: "simulated_date",
      type: :date,
      label: "Simulated date",
      capabilities: ["watch_time"],
      group: :watch_time,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: true,
      debugger_only: true,
      hint: nil
    },
    %{
      key: "simulated_time",
      type: :time,
      label: "Simulated time",
      capabilities: ["watch_time"],
      group: :watch_time,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: true,
      debugger_only: true,
      hint: nil
    },
    %{
      key: "locale",
      type: :text,
      label: "Locale",
      capabilities: ["locale"],
      group: :companion_locale,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "language",
      type: :text,
      label: "Language",
      capabilities: ["locale"],
      group: :companion_locale,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "region",
      type: :text,
      label: "Region",
      capabilities: ["locale"],
      group: :companion_locale,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "timezone_id",
      type: :text,
      label: "Timezone ID",
      capabilities: ["locale", "watch_time"],
      group: :companion_locale,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "timezone_offset_min",
      type: :number,
      label: "Timezone offset (minutes)",
      capabilities: ["locale", "watch_time"],
      group: :companion_locale,
      min: -720,
      max: 840,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "network_online",
      type: :checkbox,
      label: "Network online",
      capabilities: ["network"],
      group: :companion_network,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "notifications_enabled",
      type: :checkbox,
      label: "Notifications enabled",
      capabilities: ["notifications"],
      group: :companion_notifications,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "quiet_hours",
      type: :checkbox,
      label: "Quiet hours",
      capabilities: ["notifications"],
      group: :companion_notifications,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "use_simulator_weather",
      type: :checkbox,
      label: "Use simulator weather",
      capabilities: ["weather"],
      group: :companion_weather,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint:
        "When enabled, companion weather and Open-Meteo HTTP responses use the values below. When disabled, the companion uses live geolocation and network weather."
    },
    %{
      key: "weather_temperatureC",
      type: :number,
      label: "Temperature (°C)",
      capabilities: ["weather"],
      group: :companion_weather,
      min: -60,
      max: 60,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "weather_condition",
      type: :select,
      label: "Condition",
      capabilities: ["weather"],
      group: :companion_weather,
      min: nil,
      max: nil,
      step: nil,
      options: [
        {"clear", "Clear"},
        {"cloudy", "Cloudy"},
        {"fog", "Fog"},
        {"drizzle", "Drizzle"},
        {"rain", "Rain"},
        {"snow", "Snow"},
        {"showers", "Showers"},
        {"storm", "Storm"}
      ],
      optional: false,
      hint: nil
    },
    %{
      key: "weather_humidityPercent",
      type: :number,
      label: "Humidity (%)",
      capabilities: ["weather"],
      group: :companion_weather,
      min: 0,
      max: 100,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "weather_pressureHpa",
      type: :number,
      label: "Pressure (hPa)",
      capabilities: ["weather"],
      group: :companion_weather,
      min: 800,
      max: 1100,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "weather_windKph",
      type: :number,
      label: "Wind (km/h)",
      capabilities: ["weather"],
      group: :companion_weather,
      min: 0,
      max: 200,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "calendar_events_json",
      type: :json,
      label: "Calendar events (JSON array)",
      capabilities: ["calendar"],
      group: :companion_calendar,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: "Array of event objects consumed by the companion calendar API."
    },
    %{
      key: "environment_sunriseMin",
      type: :number,
      label: "Sunrise (minutes from midnight)",
      capabilities: ["environment"],
      group: :companion_environment,
      min: 0,
      max: 1440,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "environment_sunsetMin",
      type: :number,
      label: "Sunset (minutes from midnight)",
      capabilities: ["environment"],
      group: :companion_environment,
      min: 0,
      max: 1440,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "environment_polarDay",
      type: :checkbox,
      label: "Polar day",
      capabilities: ["environment"],
      group: :companion_environment,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "latitude",
      type: :number,
      label: "Latitude",
      capabilities: ["geolocation"],
      group: :companion_geolocation,
      min: -90,
      max: 90,
      step: 0.000001,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "longitude",
      type: :number,
      label: "Longitude",
      capabilities: ["geolocation"],
      group: :companion_geolocation,
      min: -180,
      max: 180,
      step: 0.000001,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "accuracy",
      type: :number,
      label: "Accuracy (m)",
      capabilities: ["geolocation"],
      group: :companion_geolocation,
      min: 0,
      max: 100_000,
      step: 0.1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "storage_values_json",
      type: :json,
      label: "Storage values (JSON object)",
      capabilities: ["storage"],
      group: :companion_storage,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: "Key/value map for companion storage API simulation."
    },
    %{
      key: "preferences_json",
      type: :json,
      label: "Preferences (JSON object)",
      capabilities: ["preferences"],
      group: :companion_preferences,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: "Key/value map for companion preference store simulation."
    },
    %{
      key: "timeline_peek",
      type: :checkbox,
      label: "Timeline peek",
      capabilities: ["emulator_timeline_peek"],
      group: :emulator_extras,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: "QEMU timeline quick view (emulator only)."
    },
    %{
      key: "compass_heading_deg",
      type: :range,
      label: "Compass heading",
      capabilities: ["watch_compass"],
      group: :watch_sensors,
      min: 0,
      max: 360,
      step: 1,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "compass_valid",
      type: :checkbox,
      label: "Compass reading valid",
      capabilities: ["watch_compass"],
      group: :watch_sensors,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: nil
    },
    %{
      key: "app_in_focus",
      type: :checkbox,
      label: "App in foreground",
      capabilities: ["watch_app_focus"],
      group: :watch_sensors,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: "Toggle to simulate focus changes."
    },
    %{
      key: "dictation_transcript",
      type: :text,
      label: "Dictation transcript",
      capabilities: ["watch_dictation"],
      group: :watch_sensors,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: true,
      hint: "Simulated speech-to-text result."
    },
    %{
      key: "dictation_error",
      type: :text,
      label: "Dictation error",
      capabilities: ["watch_dictation"],
      group: :watch_sensors,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: true,
      hint: "When set, simulated dictation fails with this message."
    },
    %{
      key: "vibe_pattern_ms",
      type: :json,
      label: "Vibration pattern (ms)",
      capabilities: ["watch_vibes"],
      group: :watch_sensors,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: true,
      hint: "JSON array of segment durations; ON/OFF alternating from ON."
    },
    %{
      key: "backlight_on",
      type: :checkbox,
      label: "Backlight on",
      capabilities: ["watch_light"],
      group: :watch_sensors,
      min: nil,
      max: nil,
      step: nil,
      options: nil,
      optional: false,
      hint: "Toggle to simulate backlight state changes."
    },
    %{
      key: "launch_reason",
      type: :select,
      label: "Launch reason",
      capabilities: ["watch_launch"],
      group: :watch_platform,
      min: nil,
      max: nil,
      step: nil,
      options: [
        {"LaunchUser", "User launch"},
        {"LaunchSystem", "System launch"},
        {"LaunchPhone", "Phone launch"},
        {"LaunchWakeup", "Wakeup launch"},
        {"LaunchWorker", "Worker launch"},
        {"LaunchQuickLaunch", "Quick launch"},
        {"LaunchTimelineAction", "Timeline action"},
        {"LaunchUnknown", "Unknown"}
      ],
      optional: false,
      hint: nil
    },
    %{
      key: "launch_button",
      type: :select,
      label: "Launch button",
      capabilities: ["watch_launch"],
      group: :watch_platform,
      min: nil,
      max: nil,
      step: nil,
      options: [
        {"", "None"},
        {"Back", "Back"},
        {"Up", "Up"},
        {"Select", "Select"},
        {"Down", "Down"}
      ],
      optional: true,
      hint: "Physical button that launched the app, when applicable."
    },
    %{
      key: "quick_launch_action",
      type: :select,
      label: "Quick launch action",
      capabilities: ["watch_launch"],
      group: :watch_platform,
      min: nil,
      max: nil,
      step: nil,
      options: [
        {"QuickLaunchNone", "None"},
        {"QuickLaunchHold", "Hold"},
        {"QuickLaunchTap", "Tap"},
        {"QuickLaunchCombo", "Combo"},
        {"QuickLaunchUnknown", "Unknown"}
      ],
      optional: false,
      hint: "Used when launch reason is Quick launch."
    }
  ]

  @doc """
  Returns `{latitude, longitude, accuracy}` from normalized simulator settings.
  """
  @spec geolocation(t()) :: {float() | nil, float() | nil, float() | nil}
  def geolocation(settings) when is_map(settings) do
    {
      numeric_setting(settings, "latitude"),
      numeric_setting(settings, "longitude"),
      numeric_setting(settings, "accuracy")
    }
  end

  def geolocation(_settings), do: {nil, nil, nil}

  @spec numeric_setting(display_values(), String.t()) :: float() | nil
  defp numeric_setting(settings, key) do
    case Map.get(settings, key) do
      value when is_integer(value) -> value * 1.0
      value when is_float(value) -> value
      _ -> nil
    end
  end

  @doc """
  Returns active field groups for the given project, optional debugger state, and UI mode.
  """
  @spec active_groups(Project.t() | nil, Types.runtime_state() | nil, :debugger | :emulator) :: [
          {atom(), String.t(), [field_spec()]}
        ]
  def active_groups(project, debugger_state \\ nil, mode \\ :debugger) do
    caps = capabilities_for(project, debugger_state, mode)

    @fields
    |> Enum.filter(fn field ->
      field_active?(field, caps) and field_visible_in_mode?(field, mode)
    end)
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group_order(group) end)
    |> Enum.map(fn {group, fields} ->
      {group, Map.fetch!(@group_titles, group), fields}
    end)
  end

  @doc false
  @spec capabilities_for(Project.t() | nil, Types.runtime_state() | nil, :debugger | :emulator) ::
          MapSet.t(String.t())
  def capabilities_for(project, debugger_state, mode) do
    caps = SimulatorCapabilities.infer(project, debugger_state)

    if mode == :emulator do
      MapSet.union(caps, SimulatorCapabilities.emulator_only_caps())
    else
      caps
    end
  end

  @doc """
  Loads normalized simulator settings for display, including derived flat weather/environment/json fields.
  """
  @spec values_for(Project.t() | nil, Types.runtime_state() | nil) :: display_values()
  def values_for(project, debugger_state \\ nil) do
    base =
      cond do
        is_map(debugger_state) and is_map(Map.get(debugger_state, :simulator_settings)) ->
          Map.get(debugger_state, :simulator_settings)

        is_map(debugger_state) and is_map(Map.get(debugger_state, "simulator_settings")) ->
          Map.get(debugger_state, "simulator_settings")

        match?(%Project{}, project) ->
          project
          |> project_simulator_settings()
          |> Map.new()

        true ->
          %{}
      end

    base
    |> Debugger.normalize_simulator_settings()
    |> expand_display_values()
  end

  @doc """
  Merges form params with existing project simulator settings and normalizes the result.
  """
  @spec save_from_form(t(), form_params()) :: t()
  def save_from_form(existing_settings, form_params) when is_map(form_params) do
    canonical = existing_settings |> Debugger.normalize_simulator_settings()
    display = expand_display_values(canonical)

    form_params
    |> collapse_form_params()
    |> then(&Map.merge(display, &1))
    |> expand_structured_fields()
    |> Debugger.normalize_simulator_settings()
  end

  def save_from_form(existing_settings, _form_params) when is_map(existing_settings),
    do: Debugger.normalize_simulator_settings(existing_settings)

  @doc false
  @spec raw_settings_for(Project.t() | nil, Types.runtime_state() | nil) :: t()
  def raw_settings_for(project, debugger_state \\ nil) do
    cond do
      is_map(debugger_state) and is_map(Map.get(debugger_state, :simulator_settings)) ->
        Map.get(debugger_state, :simulator_settings)

      is_map(debugger_state) and is_map(Map.get(debugger_state, "simulator_settings")) ->
        Map.get(debugger_state, "simulator_settings")

      match?(%Project{}, project) ->
        project |> project_simulator_settings() |> Map.new()

      true ->
        %{}
    end
  end

  @doc """
  Normalizes form params from the shared simulator settings component.
  """
  @spec normalize_form(form_params()) :: t()
  def normalize_form(params) when is_map(params) do
    params
    |> collapse_form_params()
    |> expand_structured_fields()
    |> Debugger.normalize_simulator_settings()
  end

  def normalize_form(_), do: Debugger.default_simulator_settings()

  @spec field_active?(field_spec(), MapSet.t(String.t())) :: boolean()
  defp field_active?(field, caps) do
    Enum.any?(field.capabilities, &MapSet.member?(caps, &1))
  end

  @spec field_visible_in_mode?(field_spec(), :debugger | :emulator) :: boolean()
  defp field_visible_in_mode?(field, :emulator) do
    not Map.get(field, :debugger_only, false)
  end

  defp field_visible_in_mode?(_field, _mode), do: true

  @spec group_order(atom()) :: integer()
  defp group_order(:watch_device), do: 0
  defp group_order(:watch_time), do: 1
  defp group_order(:watch_sensors), do: 2
  defp group_order(:watch_platform), do: 3
  defp group_order(:companion_battery), do: 4
  defp group_order(:companion_locale), do: 5
  defp group_order(:companion_network), do: 6
  defp group_order(:companion_notifications), do: 7
  defp group_order(:companion_weather), do: 8
  defp group_order(:companion_calendar), do: 9
  defp group_order(:companion_environment), do: 10
  defp group_order(:companion_geolocation), do: 11
  defp group_order(:companion_storage), do: 12
  defp group_order(:companion_preferences), do: 13
  defp group_order(:emulator_extras), do: 14
  defp group_order(_), do: 99

  @spec project_simulator_settings(Project.t()) :: Ide.Projects.Types.debugger_settings()
  defp project_simulator_settings(%Project{} = project) do
    settings = project.debugger_settings || %{}

    case Map.get(settings, "simulator") do
      simulator when is_map(simulator) -> simulator
      _ -> %{}
    end
  end

  @spec expand_display_values(t()) :: display_values()
  defp expand_display_values(settings) do
    weather = Map.get(settings, "weather", %{})
    environment = Map.get(settings, "environment", %{})

    sun =
      case Map.get(environment, "sun") do
        %{} = sun -> sun
        _ -> %{}
      end

    settings
    |> Map.put("weather_temperatureC", Map.get(weather, "temperatureC"))
    |> Map.put("weather_condition", Map.get(weather, "condition"))
    |> Map.put("weather_humidityPercent", Map.get(weather, "humidityPercent"))
    |> Map.put("weather_pressureHpa", Map.get(weather, "pressureHpa"))
    |> Map.put("weather_windKph", Map.get(weather, "windKph"))
    |> Map.put("environment_sunriseMin", Map.get(sun, "sunriseMin"))
    |> Map.put("environment_sunsetMin", Map.get(sun, "sunsetMin"))
    |> Map.put("environment_polarDay", Map.get(sun, "polarDay"))
    |> Map.put("calendar_events_json", encode_json(Map.get(settings, "calendar_events")))
    |> Map.put("storage_values_json", encode_json(Map.get(settings, "storage_values")))
    |> Map.put("preferences_json", encode_json(Map.get(settings, "preferences")))
    |> Map.put("timeline_peek", Map.get(settings, "timeline_peek", false))
  end

  @spec expand_structured_fields(display_values() | form_params()) :: t()
  defp expand_structured_fields(params) do
    weather =
      %{
        "temperatureC" => map_get(params, "weather_temperatureC"),
        "condition" => map_get(params, "weather_condition"),
        "humidityPercent" => map_get(params, "weather_humidityPercent"),
        "pressureHpa" => map_get(params, "weather_pressureHpa"),
        "windKph" => map_get(params, "weather_windKph")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    environment =
      if present?(map_get(params, "environment_sunriseMin")) or
           present?(map_get(params, "environment_sunsetMin")) or
           present?(map_get(params, "environment_polarDay")) do
        %{
          "sun" => %{
            "sunriseMin" => map_get(params, "environment_sunriseMin"),
            "sunsetMin" => map_get(params, "environment_sunsetMin"),
            "polarDay" => map_get(params, "environment_polarDay")
          },
          "moon" => %{"moonriseMin" => 900, "moonsetMin" => 300, "phaseE6" => 500_000},
          "tide" => nil
        }
      else
        nil
      end

    params
    |> Map.drop([
      "weather_temperatureC",
      "weather_condition",
      "weather_humidityPercent",
      "weather_pressureHpa",
      "weather_windKph",
      "environment_sunriseMin",
      "environment_sunsetMin",
      "environment_polarDay",
      "calendar_events_json",
      "storage_values_json",
      "preferences_json",
      "calendar_events_json"
    ])
    |> maybe_put("weather", weather)
    |> maybe_put("environment", environment)
    |> maybe_put("calendar_events", decode_json_list(map_get(params, "calendar_events_json")))
    |> maybe_put("storage_values", decode_json_map(map_get(params, "storage_values_json")))
    |> maybe_put("preferences", decode_json_map(map_get(params, "preferences_json")))
  end

  @spec collapse_form_params(form_params()) :: form_params()
  defp collapse_form_params(params) do
    Enum.reduce(params, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, Atom.to_string(key), value)

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)
    end)
  end

  @spec maybe_put(form_params(), String.t(), Types.wire_input() | nil) :: form_params()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec map_get(form_params(), String.t()) :: Types.wire_input() | nil
  defp map_get(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> find_atom_key(map, key)
    end
  end

  @spec find_atom_key(form_params(), String.t()) :: Types.wire_input() | nil
  defp find_atom_key(map, key) do
    Enum.find_value(map, fn
      {atom_key, value} when is_atom(atom_key) ->
        if Atom.to_string(atom_key) == key, do: value, else: nil

      _ ->
        nil
    end)
  end

  @spec present?(Types.wire_input()) :: boolean()
  defp present?(value) when value in [nil, ""], do: false
  defp present?(_value), do: true

  @spec encode_json(Types.wire_input()) :: String.t()
  defp encode_json(value) when is_binary(value), do: value

  defp encode_json(value) do
    case Jason.encode(value, pretty: true) do
      {:ok, encoded} -> encoded
      _ -> "[]"
    end
  end

  @spec decode_json_list(Types.wire_input()) :: list() | nil
  defp decode_json_list(value) when is_list(value), do: value

  defp decode_json_list(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      []
    else
      case Jason.decode(trimmed) do
        {:ok, list} when is_list(list) -> list
        _ -> nil
      end
    end
  end

  defp decode_json_list(_value), do: nil

  @spec decode_json_map(Types.wire_input()) :: Types.wire_string_map() | nil
  defp decode_json_map(value) when is_map(value), do: value

  defp decode_json_map(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      %{}
    else
      case Jason.decode(trimmed) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end
    end
  end

  defp decode_json_map(_value), do: nil
end
