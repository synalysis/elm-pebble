defmodule Elmx.Runtime.Pebble.SpecialValues.Companion do
  @moduledoc false

  @behaviour Elmx.Runtime.Pebble.SpecialValues.Dispatcher

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "Companion.Watch.sendWatchToPhone" -> ui_call("elmx_companion_send", args)
      "Companion.Watch.onPhoneToWatch" ->
        subscription_register_call("Companion.Watch.onPhoneToWatch", args)
      "Pebble.Companion.Phone.sendPhoneToWatch" -> ui_call("elmx_companion_send_phone", args)
      "Pebble.Companion.Phone.outgoing" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Phone.send" -> companion_phone_send(args)
      "Pebble.Companion.Phone.request" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Phone.requestWithPayload" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.WebSocket.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.WebSocket.setupCommands" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.WebSocket.connect" -> ui_call("elmx_companion_websocket_connect", args)
      "Pebble.Companion.WebSocket.disconnect" -> ui_call("elmx_companion_websocket_disconnect", args)
      "Pebble.Companion.WebSocket.send" -> ui_call("elmx_companion_websocket_send", args)
      "Pebble.Companion.WebSocket.onWebSocket" -> companion_subscription_stub(args)
      "Pebble.Companion.WebSocket.onCommands" -> companion_subscription_stub(args)
      "Pebble.Companion.Timeline.setupToken" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Timeline.setupCommands" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Timeline.getToken" -> companion_bridge_call("timeline", "getToken", args)
      "Pebble.Companion.Timeline.insertPin" -> companion_bridge_call("timeline", "insertPin", args)
      "Pebble.Companion.Timeline.deletePin" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Timeline.onToken" -> companion_subscription_stub(args)
      "Pebble.Companion.Timeline.onCommands" -> companion_subscription_stub(args)
      "Pebble.Companion.Configuration.open" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Configuration.onClosed" -> companion_configuration_on_closed(args)
      "Pebble.Companion.Preferences.decodeResponse" -> companion_preferences_decode_response(args)
      "Pebble.Companion.Lifecycle.onLifecycle" -> companion_subscription_stub(args)
      "Pebble.Companion.Battery.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Battery.current" -> companion_bridge_call("battery", "status", args)
      "Pebble.Companion.Locale.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Locale.current" -> companion_bridge_call("locale", "status", args)
      "Pebble.Companion.Connectivity.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Connectivity.current" -> companion_bridge_call("network", "status", args)
      "Pebble.Companion.Notifications.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Notifications.current" -> companion_bridge_call("notifications", "status", args)
      "Pebble.Companion.Platform.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Calendar.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Calendar.current" -> companion_bridge_call("calendar", "nextEvent", args)
      "Pebble.Companion.Calendar.onCalendar" -> companion_subscription_stub(args)
      "Pebble.Companion.Calendar.onCurrent" -> companion_subscription_stub(args)
      "Pebble.Companion.Calendar.onUpcoming" -> companion_subscription_stub(args)
      "Pebble.Companion.Environment.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Environment.current" -> companion_bridge_call("environment", "current", args)
      "Pebble.Companion.Environment.onEnvironment" -> companion_subscription_stub(args)
      "Pebble.Companion.Weather.current" -> companion_bridge_call("weather", "current", args)
      "Pebble.Companion.Weather.forecast" -> companion_bridge_call("weather", "forecast", args)
      "Pebble.Companion.Weather.onWeather" -> companion_subscription_stub(args)
      "Pebble.Companion.Weather.onCurrent" -> companion_subscription_stub(args)
      "Pebble.Companion.Weather.onForecast" -> companion_subscription_stub(args)
      "Pebble.Companion.Geolocation.currentPosition" ->
        companion_bridge_call("geolocation", "getCurrentPosition", args)

      "Pebble.Companion.Geolocation.onCurrentPosition" -> companion_subscription_stub(args)
      "Pebble.Companion.Battery.onBattery" -> companion_subscription_stub(args)
      "Pebble.Companion.Locale.onLocale" -> companion_subscription_stub(args)
      "Pebble.Companion.Connectivity.onConnectivity" -> companion_subscription_stub(args)
      "Pebble.Companion.Notifications.onNotificationStatus" -> companion_subscription_stub(args)
      "Pebble.Companion.Phone.sendBridgeCommand" -> ui_call("elmx_companion_send_bridge_command", args)
      "Pebble.Companion.Phone.registerResponseHandler" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Phone.registerHandler" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Platform.subscribe" -> companion_subscription_stub(args)
      "Pebble.Companion.Configuration.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Lifecycle.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Phone.onWatchToPhone" ->
        subscription_register_call("Pebble.Companion.Phone.onWatchToPhone", args)
      "Pebble.Companion.Storage.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Storage.get" -> ui_call("elmx_companion_storage_get", args)
      "Pebble.Companion.Storage.set" -> ui_call("elmx_companion_storage_set", args)
      "Pebble.Companion.Storage.remove" -> ui_call("elmx_companion_storage_remove", args)
      "Pebble.Companion.Storage.clear" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.Storage.onStorage" ->
        subscription_register_call("Pebble.Companion.Storage.onStorage", args)
      "Pebble.Companion.PreferenceStore.setup" -> {:ok, %{op: :cmd_none}}
      "Pebble.Companion.PreferenceStore.get" -> ui_call("elmx_companion_preferences_get", args)
      "Pebble.Companion.PreferenceStore.set" -> ui_call("elmx_companion_preferences_set", args)
      "Pebble.Companion.PreferenceStore.onPreference" ->
        subscription_register_call("Pebble.Companion.PreferenceStore.onPreference", args)

      "Pebble.Companion." <> _rest ->
        fallback_rewrite(target, args)

      _ ->
        :unmatched
    end
  end

  @spec fallback_rewrite(String.t(), Types.ir_arg_list()) :: Types.rewrite_result() | :unmatched
  def fallback_rewrite("Pebble.Companion." <> _rest = target, args) do
    cond do
      companion_json_encode?(target) -> :unmatched
      companion_emit_module_api?(target) -> :unmatched
      companion_storage_or_preference_api?(target) -> :unmatched
      companion_phone_protocol_send?(target) -> :unmatched
      companion_subscription_api?(target) -> companion_subscription_stub(args)
      true -> {:ok, %{op: :cmd_none}}
    end
  end

  def fallback_rewrite(_target, _args), do: :unmatched

  defp companion_subscription_stub(_args), do: companion_subscription_zero()

  defp companion_configuration_on_closed([]), do: companion_subscription_zero()

  defp companion_configuration_on_closed([to_msg]) do
    {:ok, %{op: :runtime_call, function: "elmx_companion_configuration_on_closed", args: [to_msg]}}
  end

  defp companion_configuration_on_closed(_), do: :unmatched

  defp companion_preferences_decode_response([schema, response]) do
    {:ok,
     %{
       op: :runtime_call,
       function: "elmx_companion_preferences_decode_response",
       args: [schema, response]
     }}
  end

  defp companion_preferences_decode_response(_), do: :unmatched

  defp companion_json_encode?(target), do: String.starts_with?(target, "Json.Encode.")

  defp companion_emit_module_api?(target) do
    Enum.any?(
      [
        "Pebble.Companion.Platform.",
        "Pebble.Companion.Codec.",
        "Pebble.Companion.Command.",
        "Pebble.Companion.Contract.",
        "Pebble.Companion.Lifecycle."
      ],
      &String.starts_with?(target, &1)
    )
  end

  defp companion_storage_or_preference_api?(target) do
    String.starts_with?(target, "Pebble.Companion.Storage.") or
      String.starts_with?(target, "Pebble.Companion.PreferenceStore.")
  end

  defp companion_phone_protocol_send?(target) do
    target == "Pebble.Companion.Phone.sendPhoneToWatch"
  end

  defp companion_subscription_api?(target) do
    case String.split(target, ".") do
      ["Pebble", "Companion", _module, fun | _] when is_binary(fun) ->
        String.starts_with?(fun, "on") and byte_size(fun) > 2

      _ ->
        false
    end
  end
end
