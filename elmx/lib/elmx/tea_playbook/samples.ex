defmodule Elmx.TeaPlaybook.Samples do
  @moduledoc """
  Shared wire `message_value` samples for TEA playbooks (elmc host + elmx debugger).

  Phone samples are keyed by `PhoneToWatch` constructor name from the companion
  contract (`Types.elm`), not by app `Msg` names.
  """

  @spec current_datetime() :: map()
  def current_datetime do
    %{
      "year" => 2026,
      "month" => 7,
      "day" => 1,
      "dayOfWeek" => %{"ctor" => "Wednesday", "args" => []},
      "hour" => 10,
      "minute" => 30,
      "second" => 0,
      "utcOffsetMinutes" => 120
    }
  end

  @spec current_time_string() :: String.t()
  def current_time_string, do: "10:30"

  @spec frame(non_neg_integer(), non_neg_integer()) :: map()
  def frame(frame, dt_ms \\ 33) do
    %{
      "dtMs" => dt_ms,
      "elapsedMs" => dt_ms * max(frame, 1),
      "frame" => frame
    }
  end

  @spec from_phone(String.t(), list()) :: map()
  def from_phone(inner_ctor, args) when is_binary(inner_ctor) and is_list(args) do
    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => inner_ctor,
          "args" => Enum.map(args, &wire_arg/1)
        }
      ]
    }
  end

  @doc """
  Wire sample for a `PhoneToWatch` constructor, or `nil` when unsupported.

  `type_args` are the declared Elm type tokens (used for arity / type-token fallback).
  """
  @spec phone_sample(String.t(), [String.t()]) :: map() | nil
  def phone_sample(name, type_args \\ []) when is_binary(name) and is_list(type_args) do
    arity = length(type_args)

    case known_phone_args(name, arity) do
      :unsupported ->
        nil

      wire_args when is_list(wire_args) ->
        from_phone(name, wire_args)

      :from_types ->
        from_phone(name, Enum.map(type_args, &sample_type_arg/1))
    end
  end

  @spec phone_sample_supported?(String.t(), [String.t()]) :: boolean()
  def phone_sample_supported?(name, type_args \\ [])
      when is_binary(name) and is_list(type_args) do
    known_phone_args(name, length(type_args)) != :unsupported
  end

  @spec provide_sun() :: map()
  def provide_sun, do: phone_sample!("ProvideSun")

  @spec provide_weather() :: map()
  def provide_weather, do: phone_sample!("ProvideWeather")

  @spec provide_condition() :: map()
  def provide_condition, do: phone_sample!("ProvideCondition")

  @spec provide_temperature() :: map()
  def provide_temperature, do: phone_sample!("ProvideTemperature")

  @spec provide_moon_phase() :: map()
  def provide_moon_phase, do: phone_sample!("ProvideMoonPhase")

  @spec provide_moon() :: map()
  def provide_moon, do: phone_sample!("ProvideMoon")

  defp phone_sample!(name) do
    case phone_sample(name) do
      nil -> raise "missing TEA phone sample for #{name}"
      sample -> sample
    end
  end

  # Explicit contract samples (constructor name from Types.elm). Prefer these over
  # type-token guesses when payloads must match app `case` expectations.
  defp known_phone_args("ProvideSun", _),
    do: [360, 1080, %{"ctor" => "PolarDay", "args" => []}]

  defp known_phone_args("ProvideWeather", 2),
    do: [18, %{"ctor" => "Clear", "args" => []}]

  defp known_phone_args("ProvideWeather", _),
    do: [
      %{"ctor" => "Celsius", "args" => [210]},
      %{"ctor" => "Cloudy", "args" => []},
      0,
      0,
      1013
    ]

  defp known_phone_args("ProvideCondition", _), do: [%{"ctor" => "Cloudy", "args" => []}]
  defp known_phone_args("ProvideTemperature", _), do: [%{"ctor" => "Celsius", "args" => [210]}]
  defp known_phone_args("ProvideMoonPhase", _), do: [250_000]
  defp known_phone_args("ProvideMoon", _), do: [360, 1080, 250_000]
  defp known_phone_args("ProvideTimezone", _), do: [120]
  defp known_phone_args("ProvideWind", _),
    do: [%{"ctor" => "North", "args" => []}, %{"ctor" => "Knots", "args" => [10]}]

  defp known_phone_args("ClearTide", _), do: []
  defp known_phone_args("ProvideAltitude", _), do: [%{"ctor" => "Meters", "args" => [100]}]
  defp known_phone_args("SetCornerUpdateInterval", _), do: [60]

  defp known_phone_args("Pong", _), do: []
  defp known_phone_args("EchoColor", _), do: [%{"ctor" => "Red", "args" => []}]
  defp known_phone_args("EchoMeasure", _), do: [%{"ctor" => "Liters", "args" => [3]}]
  defp known_phone_args("EchoPoint", _), do: [%{"x" => 1, "y" => 2}]
  defp known_phone_args("EchoCounts", _), do: [[1, 2, 3]]
  defp known_phone_args("PushBool", _), do: [true]
  # Match companion_demo_protocol_matrix Main.handleExtras expectations.
  defp known_phone_args("PushString", _), do: ["elm"]
  defp known_phone_args("PushPoints", _), do: [[%{"x" => 4, "y" => 5}]]
  defp known_phone_args("PushLabels", _), do: [%{"k" => 9}]

  defp known_phone_args("ProvideBattery", _), do: [88, true]
  defp known_phone_args("ProvideLocale", _), do: ["en-US"]
  defp known_phone_args("ProvideConnectivity", _), do: [true]
  defp known_phone_args("ProvideNotifications", _), do: [true, false]

  defp known_phone_args("ProvideNextEvent", _), do: ["Standup", 9, 30]
  defp known_phone_args("NoUpcomingEvents", _), do: []

  defp known_phone_args("ProvidePosition", _), do: [12_345_000, -98_765_000, 25]

  defp known_phone_args("ProvideTheme", _),
    do: [%{"ctor" => "Dark", "args" => []}, %{"ctor" => "Metric", "args" => []}]

  defp known_phone_args("SettingsReady", _), do: []
  defp known_phone_args("SettingsClosed", _), do: [%{"ctor" => "Dismissed", "args" => []}]

  defp known_phone_args("ProvideWebSocketStatus", _),
    do: [%{"ctor" => "Open", "args" => []}, "connected"]

  defp known_phone_args("ProvideTimelineToken", _), do: ["tea-token"]
  defp known_phone_args("ProvideTimelineStatus", _), do: [%{"ctor" => "PinOk", "args" => []}]

  defp known_phone_args("ProvideEnvironment", _), do: [360, 1080, 500_000]

  defp known_phone_args("ProvideFigure", _), do: [1]
  defp known_phone_args("BeginFigure", _), do: [1]
  defp known_phone_args("ProvidePiece", _), do: [0, [0, 3, -3, -5]]
  defp known_phone_args("EndFigure", _), do: [1]

  defp known_phone_args("ProvideTide", _), do: :unsupported

  defp known_phone_args(_name, _arity), do: :from_types

  defp sample_type_arg("Int"), do: 0
  defp sample_type_arg("String"), do: "tea"
  defp sample_type_arg("Bool"), do: true
  defp sample_type_arg("(List Int)"), do: [1, 2, 3]
  defp sample_type_arg("List Int"), do: [1, 2, 3]
  defp sample_type_arg("Point"), do: %{"x" => 1, "y" => 2}
  defp sample_type_arg("(List Point)"), do: [%{"x" => 1, "y" => 2}]
  defp sample_type_arg("List Point"), do: [%{"x" => 1, "y" => 2}]
  defp sample_type_arg("(Dict.Dict String Int)"), do: %{"a" => 1}
  defp sample_type_arg("Dict.Dict String Int"), do: %{"a" => 1}
  defp sample_type_arg(type) when is_binary(type), do: %{"ctor" => first_type_ctor(type), "args" => []}

  defp first_type_ctor(type) do
    type
    |> String.split(~r/[\s\.\(]/)
    |> Enum.reject(&(&1 == ""))
    |> List.first()
    |> case do
      nil -> "Unknown"
      name -> name
    end
  end

  defp wire_arg(%{"ctor" => _, "args" => _} = map), do: map
  defp wire_arg(%{"x" => _, "y" => _} = map), do: map
  defp wire_arg(value) when is_binary(value) or is_integer(value) or is_boolean(value), do: value
  defp wire_arg(values) when is_list(values), do: Enum.map(values, &wire_arg/1)
  defp wire_arg(map) when is_map(map), do: map
end
