defmodule Elmx.Runtime.Pebble.DeviceStubs do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Types

  @spec device(String.t(), Types.registry_args()) :: Types.wire_cmd()
  def device(kind, [callback]) when is_binary(kind) do
    Cmd.device(kind, callback, value(kind))
  end

  def device(kind, args) when is_binary(kind) and is_list(args) do
    callback = List.first(args)
    Cmd.device(kind, callback, value(kind))
  end

  @spec value(String.t()) :: Types.wire_value() | nil
  def value("current_date_time") do
    %{
      "year" => 2026,
      "month" => 1,
      "day" => 1,
      "dayOfWeek" => %{"ctor" => "Thursday", "args" => []},
      "hour" => 12,
      "minute" => 0,
      "second" => 0,
      "utcOffsetMinutes" => 0
    }
  end

  def value("current_time_string"), do: "12:00"
  def value("clock_style_24h"), do: true
  def value("timezone_is_set"), do: true
  def value("timezone"), do: "UTC"
  def value("watch_model"), do: %{"ctor" => "PebbleTime", "args" => []}
  def value("firmware_version"), do: %{"major" => 4, "minor" => 4, "patch" => 0}
  def value("watch_color"), do: %{"ctor" => "Black", "args" => []}
  def value("battery_level"), do: 88
  def value("health_supported"), do: false
  def value("health_value"), do: %{"value" => 0}
  def value("health_sum_today"), do: %{"value" => 0}
  def value("health_sum"), do: %{"value" => 0}
  def value("health_accessible"), do: true
  def value("connection_status"), do: true
  def value("unobstructed_bounds"), do: %{"x" => 0, "y" => 0, "w" => 144, "h" => 168}
  def value(_), do: nil
end
