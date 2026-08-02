defmodule Elmx.TeaPlaybook.Samples do
  @moduledoc """
  Shared wire `message_value` samples for TEA playbooks (elmc host + elmx debugger).
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

  @spec provide_sun() :: map()
  def provide_sun do
    # Tag order matches Companion.Types PhoneToWatch constructors (0-based).
    from_phone("ProvideSun", [360, 1080, %{"ctor" => "PolarDay", "args" => []}])
  end

  @spec provide_weather() :: map()
  def provide_weather do
    from_phone("ProvideWeather", [
      %{"ctor" => "Celsius", "args" => [210]},
      %{"ctor" => "Cloudy", "args" => []},
      0,
      0,
      1013
    ])
  end

  @spec provide_condition() :: map()
  def provide_condition do
    from_phone("ProvideCondition", [%{"ctor" => "Cloudy", "args" => []}])
  end

  @spec provide_temperature() :: map()
  def provide_temperature do
    from_phone("ProvideTemperature", [%{"ctor" => "Celsius", "args" => [210]}])
  end

  @spec provide_moon_phase() :: map()
  def provide_moon_phase do
    # Waxing crescent: exercises drawMoonPhase overlay path.
    from_phone("ProvideMoonPhase", [250_000])
  end

  @spec provide_moon() :: map()
  def provide_moon do
    from_phone("ProvideMoon", [360, 1080, 250_000])
  end

  defp wire_arg(%{"ctor" => _, "args" => _} = map), do: map
  defp wire_arg(value) when is_binary(value) or is_integer(value) or is_boolean(value), do: value
  defp wire_arg(values) when is_list(values), do: values
end
