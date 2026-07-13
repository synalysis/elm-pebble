defmodule Elmx.Runtime.Pebble.Dispatch.Companion do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.CompanionPreferences
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec send_cmd(Types.registry_args()) :: Types.wire_cmd()
  def send_cmd([message]), do: Cmd.protocol_watch_to_phone(message)

  def send_cmd([tag, value]) when is_integer(tag) and is_integer(value),
    do: Cmd.protocol_watch_to_phone_tag_value(tag, value)

  def send_cmd(_), do: Cmd.none()

  @spec send_phone_cmd(Types.registry_args()) :: Types.wire_cmd()
  def send_phone_cmd([message]), do: Cmd.protocol_phone_to_watch(message)
  def send_phone_cmd(_), do: Cmd.none()

  @spec storage_get_cmd(Types.registry_args()) :: Types.wire_cmd()
  def storage_get_cmd([key, callback]) when is_binary(key),
    do: Cmd.companion_bridge("storage", "get", key: key, callback: callback)

  def storage_get_cmd(_), do: Cmd.none()

  @spec storage_set_cmd(Types.registry_args()) :: Types.wire_cmd()
  def storage_set_cmd([key, value]) when is_binary(key),
    do: Cmd.companion_bridge("storage", "set", key: key, value: storage_value_wire(value))

  def storage_set_cmd(_), do: Cmd.none()

  @spec storage_remove_cmd(Types.registry_args()) :: Types.wire_cmd()
  def storage_remove_cmd([key]) when is_binary(key),
    do: Cmd.companion_bridge("storage", "remove", key: key, callback: "Ok")

  def storage_remove_cmd(_), do: Cmd.none()

  @spec preferences_get_cmd(Types.registry_args()) :: Types.wire_cmd()
  def preferences_get_cmd([key, callback]) when is_binary(key),
    do: Cmd.companion_bridge("preferences", "get", key: key, callback: callback)

  def preferences_get_cmd(_), do: Cmd.none()

  @spec preferences_set_cmd(Types.registry_args()) :: Types.wire_cmd()
  def preferences_set_cmd([key, value]) when is_binary(key),
    do: Cmd.companion_bridge("preferences", "set", key: key, value: value)

  def preferences_set_cmd(_), do: Cmd.none()

  @spec preferences_decode_response(Types.registry_args()) :: Types.result_like()
  def preferences_decode_response([schema, response]),
    do: CompanionPreferences.decode_response(schema, response)

  def preferences_decode_response(_), do: {:Err, :MissingResponse}

  @spec configuration_on_closed(Types.registry_args()) :: integer()
  def configuration_on_closed([_to_msg]), do: 0
  def configuration_on_closed(_), do: 0

  @spec bridge_cmd(Types.registry_args()) :: Types.wire_cmd()
  def bridge_cmd([api, op, callback]) when is_binary(api) and is_binary(op),
    do: Cmd.companion_bridge(api, op, callback: callback)

  def bridge_cmd(_), do: Cmd.none()

  @spec phone_send_cmd(Types.registry_args()) :: Types.wire_cmd()
  def phone_send_cmd([callback, request]), do: bridge_from_envelope(callback, request)
  def phone_send_cmd(_), do: Cmd.none()

  @spec send_bridge_command_cmd(Types.registry_args()) :: Types.wire_cmd()
  def send_bridge_command_cmd([envelope]), do: bridge_from_envelope("Unknown", envelope)
  def send_bridge_command_cmd(_), do: Cmd.none()

  @spec websocket_connect_cmd(Types.registry_args()) :: Types.wire_cmd()
  def websocket_connect_cmd([url, callback]) when is_binary(url) do
    Cmd.companion_bridge("webSocket", "connect",
      callback: callback,
      bridge_id: "webSocket-connect",
      payload: %{"url" => url}
    )
  end

  def websocket_connect_cmd(_), do: Cmd.none()

  @spec websocket_disconnect_cmd(Types.registry_args()) :: Types.wire_cmd()
  def websocket_disconnect_cmd([callback]) do
    Cmd.companion_bridge("webSocket", "disconnect",
      callback: callback,
      bridge_id: "webSocket-disconnect"
    )
  end

  def websocket_disconnect_cmd(_), do: Cmd.none()

  @spec websocket_send_cmd(Types.registry_args()) :: Types.wire_cmd()
  def websocket_send_cmd([message, callback]) when is_binary(message) do
    Cmd.companion_bridge("webSocket", "send",
      callback: callback,
      bridge_id: "webSocket-send",
      payload: %{"message" => message}
    )
  end

  def websocket_send_cmd(_), do: Cmd.none()

  @spec bridge_from_envelope(Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  def bridge_from_envelope(callback, request) do
    case command_envelope(request) do
      %{"api" => api, "op" => op} = envelope when is_binary(api) and is_binary(op) ->
        Cmd.companion_bridge(api, op,
          callback: callback,
          bridge_id: Map.get(envelope, "id"),
          payload: Map.get(envelope, "payload", %{})
        )

      _ ->
        Cmd.none()
    end
  end

  @spec command_envelope(Types.wire_value()) :: Types.wire_map()
  def command_envelope({:Request, envelope, _}), do: normalize_command_envelope(envelope)

  def command_envelope(%{"ctor" => "Request", "args" => [envelope | _]}),
    do: normalize_command_envelope(envelope)

  def command_envelope(envelope), do: normalize_command_envelope(envelope)

  @spec normalize_command_envelope(Types.wire_value()) :: Types.wire_map()
  defp normalize_command_envelope(envelope) when is_map(envelope) do
    %{
      "id" => envelope_field(envelope, "id"),
      "api" => envelope_field(envelope, "api"),
      "op" => envelope_field(envelope, "op"),
      "payload" => envelope_field(envelope, "payload") || %{}
    }
  end

  defp normalize_command_envelope(_), do: %{}

  defp envelope_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  @spec storage_value_wire(Types.storage_value_input()) :: Types.wire_value()
  defp storage_value_wire(%{"ctor" => "StringValue", "args" => [text]}),
    do: %{"ctor" => "StringValue", "args" => [text]}

  defp storage_value_wire(%{ctor: "StringValue", args: [text]}),
    do: %{"ctor" => "StringValue", "args" => [text]}

  defp storage_value_wire({:StringValue, text}), do: %{"ctor" => "StringValue", "args" => [text]}
  defp storage_value_wire(other), do: Values.wire_value(other)
end
