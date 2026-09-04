defmodule ElmEx.Typesys.Kernel.PebbleCompanion do
  @moduledoc """
  Declared `Pebble.Companion.*` schemes for phone/companion Elm.
  """

  alias ElmEx.Typesys.{Env, Parser}

  @signatures %{
    "Pebble.Companion.Command.command" =>
      "String -> String -> String -> Pebble.Companion.Contract.CommandEnvelope",
    "Pebble.Companion.Command.withPayload" =>
      "Value -> Pebble.Companion.Contract.CommandEnvelope -> Pebble.Companion.Contract.CommandEnvelope",
    "Pebble.Companion.AppMessage.send" =>
      "String -> Value -> Pebble.Companion.Contract.CommandEnvelope",
    "Pebble.Companion.AppMessage.subscribeIncoming" =>
      "String -> Pebble.Companion.Contract.CommandEnvelope",
    "Pebble.Companion.AppMessage.decodeIncoming" =>
      "Pebble.Companion.Contract.BridgeEvent -> Result String Value",
    "Pebble.Companion.Codec.encodeCommand" =>
      "Pebble.Companion.Contract.CommandEnvelope -> Value",
    "Pebble.Companion.Phone.request" =>
      "String -> String -> String -> (Value -> Result String a) -> Pebble.Companion.Phone.Request a",
    "Pebble.Companion.Phone.send" =>
      "(Result String a -> msg) -> Pebble.Companion.Phone.Request a -> Cmd msg",
    "Pebble.Companion.Phone.sendBridgeCommand" =>
      "Pebble.Companion.Contract.CommandEnvelope -> Cmd msg",
    "Pebble.Companion.Phone.registerHandler" => "String -> Value -> Cmd msg",
    "Pebble.Companion.Phone.platformIncomingFor" =>
      "String -> (Value -> msg) -> Sub msg",
    "Pebble.Companion.Phone.sendPhoneToWatch" => "Companion.Types.PhoneToWatch -> Cmd msg",
    "Pebble.Companion.Phone.onWatchToPhone" =>
      "(Result String Companion.Types.WatchToPhone -> msg) -> Sub msg",
    "Companion.Watch.sendWatchToPhone" => "Companion.Types.WatchToPhone -> Cmd msg",
    "Companion.Watch.onPhoneToWatch" => "(Companion.Types.PhoneToWatch -> msg) -> Sub msg",
    "Pebble.Companion.Weather.current" =>
      "(Result String Pebble.Companion.Weather.WeatherInfo -> msg) -> Cmd msg",
    "Pebble.Companion.Weather.forecast" =>
      "(Result String (List Pebble.Companion.Weather.WeatherInfo) -> msg) -> Cmd msg",
    "Pebble.Companion.Weather.onWeather" =>
      "(Result String Pebble.Companion.Weather.WeatherUpdate -> msg) -> Sub msg",
    "Pebble.Companion.Weather.onCurrent" =>
      "(Result String Pebble.Companion.Weather.WeatherInfo -> msg) -> Sub msg",
    "Pebble.Companion.Weather.onForecast" =>
      "(Result String (List Pebble.Companion.Weather.WeatherInfo) -> msg) -> Sub msg",
    "Pebble.Companion.Battery.current" =>
      "(Result String Pebble.Companion.Battery.BatteryInfo -> msg) -> Cmd msg",
    "Pebble.Companion.Battery.onBattery" =>
      "(Result String Pebble.Companion.Battery.BatteryInfo -> msg) -> Sub msg",
    "Pebble.Companion.Battery.setup" => "Cmd msg",
    "Pebble.Companion.Connectivity.current" =>
      "(Pebble.Companion.Connectivity.Connectivity -> msg) -> Cmd msg",
    "Pebble.Companion.Connectivity.onConnectivity" =>
      "(Pebble.Companion.Connectivity.Connectivity -> msg) -> Sub msg",
    "Pebble.Companion.Connectivity.setup" => "Cmd msg",
    "Pebble.Companion.Geolocation.currentPosition" =>
      "(Result String Pebble.Companion.Geolocation.Location -> msg) -> Cmd msg",
    "Pebble.Companion.Geolocation.onCurrentPosition" =>
      "(Result String Pebble.Companion.Geolocation.Location -> msg) -> Sub msg",
    "Pebble.Companion.Locale.current" =>
      "(Result String Pebble.Companion.Locale.LocaleInfo -> msg) -> Cmd msg",
    "Pebble.Companion.Locale.onLocale" =>
      "(Result String Pebble.Companion.Locale.LocaleInfo -> msg) -> Sub msg",
    "Pebble.Companion.Locale.setup" => "Cmd msg",
    "Pebble.Companion.Lifecycle.onLifecycle" =>
      "(Pebble.Companion.Lifecycle.Event -> msg) -> Sub msg",
    "Pebble.Companion.Lifecycle.setup" => "Cmd msg",
    "Pebble.Companion.Notifications.current" =>
      "(Result String Pebble.Companion.Notifications.NotificationStatus -> msg) -> Cmd msg",
    "Pebble.Companion.Notifications.onNotificationStatus" =>
      "(Result String Pebble.Companion.Notifications.NotificationStatus -> msg) -> Sub msg",
    "Pebble.Companion.Notifications.setup" => "Cmd msg",
    "Pebble.Companion.Timeline.getToken" => "(Result String String -> msg) -> Cmd msg",
    "Pebble.Companion.Timeline.insertPin" => "Value -> (Result String () -> msg) -> Cmd msg",
    "Pebble.Companion.Timeline.deletePin" => "String -> (Result String () -> msg) -> Cmd msg",
    "Pebble.Companion.Configuration.open" => "String -> Cmd msg",
    "Pebble.Companion.Storage.set" => "String -> Pebble.Companion.Storage.Value -> Cmd msg",
    "Pebble.Companion.Storage.get" =>
      "String -> (Result Pebble.Companion.Storage.Error Pebble.Companion.Storage.Value -> msg) -> Cmd msg",
    "Pebble.Companion.Calendar.current" =>
      "(Result String (Maybe Pebble.Companion.Calendar.CalendarEvent) -> msg) -> Cmd msg",
    "Pebble.Companion.Calendar.upcoming" =>
      "Int -> (Result String (List Pebble.Companion.Calendar.CalendarEvent) -> msg) -> Cmd msg",
    "Pebble.Companion.Environment.current" =>
      "(Result String Pebble.Companion.Environment.EnvironmentInfo -> msg) -> Cmd msg"
  }

  @aliases %{
    "Pebble.Companion.Contract.CommandEnvelope" =>
      "{ id : String, api : String, op : String, payload : Value }",
    "Pebble.Companion.Contract.BridgeError" =>
      "{ type_ : String, message : String, retryable : Maybe Bool }",
    "Pebble.Companion.Contract.ResultEnvelope" =>
      "{ id : String, ok : Bool, payload : Maybe Value, error : Maybe Pebble.Companion.Contract.BridgeError }",
    "Pebble.Companion.Contract.BridgeEvent" => "{ event : String, payload : Value }",
    "Pebble.Companion.Weather.WeatherInfo" =>
      "{ temperatureC : Int, condition : Pebble.Companion.Weather.Condition, humidityPercent : Maybe Int, pressureHpa : Maybe Int, windKph : Maybe Int, windDirectionDeg : Maybe Int }",
    "Pebble.Companion.Battery.BatteryInfo" => "{ percent : Int, charging : Bool }",
    "Pebble.Companion.Geolocation.Location" =>
      "{ latitude : Float, longitude : Float, accuracy : Float }",
    "Pebble.Companion.Locale.LocaleInfo" =>
      "{ locale : String, language : String, region : String, uses24h : Bool }"
  }

  @zero_ctors [
    {"Pebble.Companion.Weather.Clear", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Cloudy", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Fog", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Drizzle", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Rain", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Snow", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Showers", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.Storm", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Weather.UnknownWeather", "Pebble.Companion.Weather.Condition"},
    {"Pebble.Companion.Connectivity.Online", "Pebble.Companion.Connectivity.Connectivity"},
    {"Pebble.Companion.Connectivity.Offline", "Pebble.Companion.Connectivity.Connectivity"}
  ]

  @payload_ctors [
    {"Pebble.Companion.Weather.Current", "Pebble.Companion.Weather.WeatherUpdate", 1,
     "Pebble.Companion.Weather.WeatherInfo -> Pebble.Companion.Weather.WeatherUpdate"},
    {"Pebble.Companion.Weather.Forecast", "Pebble.Companion.Weather.WeatherUpdate", 1,
     "List Pebble.Companion.Weather.WeatherInfo -> Pebble.Companion.Weather.WeatherUpdate"},
    {"Pebble.Companion.Storage.StringValue", "Pebble.Companion.Storage.Value", 1,
     "String -> Pebble.Companion.Storage.Value"},
    {"Pebble.Companion.Storage.IntValue", "Pebble.Companion.Storage.Value", 1,
     "Int -> Pebble.Companion.Storage.Value"},
    {"Pebble.Companion.Storage.BoolValue", "Pebble.Companion.Storage.Value", 1,
     "Bool -> Pebble.Companion.Storage.Value"},
    {"Pebble.Companion.Storage.JsonValue", "Pebble.Companion.Storage.Value", 1,
     "Value -> Pebble.Companion.Storage.Value"},
    {"Pebble.Companion.Storage.MissingPayload", "Pebble.Companion.Storage.Error", 0,
     "Pebble.Companion.Storage.Error"},
    {"Pebble.Companion.Storage.DecodeFailure", "Pebble.Companion.Storage.Error", 1,
     "String -> Pebble.Companion.Storage.Error"},
    {"Pebble.Companion.Storage.BridgeFailure", "Pebble.Companion.Storage.Error", 1,
     "Pebble.Companion.Contract.BridgeError -> Pebble.Companion.Storage.Error"}
  ]

  @spec install(Env.t()) :: Env.t()
  def install(env) do
    env
    |> install_aliases()
    |> install_signatures()
    |> install_zero_ctors()
    |> install_payload_ctors()
  end

  defp install_signatures(env) do
    Enum.reduce(@signatures, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} -> Env.put_value(acc, name, Env.generalize(acc, type))
        {:error, _} -> acc
      end
    end)
  end

  defp install_aliases(env) do
    Enum.reduce(@aliases, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, body} ->
          fields =
            case body do
              {:record, fs, _} -> fs
              _ -> %{}
            end

          Env.put_alias(acc, name, %{name: name, params: [], body: body, fields: fields})

        {:error, _} ->
          acc
      end
    end)
  end

  defp install_zero_ctors(env) do
    Enum.reduce(@zero_ctors, env, fn {name, union}, acc ->
      put_ctor(acc, name, union, 0, union)
    end)
  end

  defp install_payload_ctors(env) do
    Enum.reduce(@payload_ctors, env, fn {name, union, arity, src}, acc ->
      put_ctor(acc, name, union, arity, src)
    end)
  end

  defp put_ctor(env, name, union, arity, src) do
    case Parser.parse(src) do
      {:ok, type} ->
        scheme = Env.generalize(env, type)
        info = %{name: name, union: union, arity: arity, scheme: scheme}

        env
        |> Map.update!(:constructors, &Map.put(&1, name, info))
        |> Env.put_value(name, scheme)

      {:error, _} ->
        env
    end
  end
end
