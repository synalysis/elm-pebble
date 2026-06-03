defmodule Elmx.Runtime.Pebble.Registry.Companion do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_companion_send" => {Dispatch, :companion_send_cmd},
      "elmx_companion_send_phone" => {Dispatch, :companion_send_phone_cmd},
      "elmx_companion_storage_get" => {Dispatch, :companion_storage_get_cmd},
      "elmx_companion_storage_set" => {Dispatch, :companion_storage_set_cmd},
      "elmx_companion_storage_remove" => {Dispatch, :companion_storage_remove_cmd},
      "elmx_companion_preferences_get" => {Dispatch, :companion_preferences_get_cmd},
      "elmx_companion_preferences_set" => {Dispatch, :companion_preferences_set_cmd},
      "elmx_companion_preferences_decode_response" => {Dispatch, :companion_preferences_decode_response},
      "elmx_companion_configuration_on_closed" => {Dispatch, :companion_configuration_on_closed},
      "elmx_companion_bridge_cmd" => {Dispatch, :companion_bridge_cmd},
      "elmx_companion_phone_send" => {Dispatch, :companion_phone_send_cmd},
      "elmx_companion_send_bridge_command" => {Dispatch, :companion_send_bridge_command_cmd},
      "elmx_companion_websocket_connect" => {Dispatch, :companion_websocket_connect_cmd},
      "elmx_companion_websocket_disconnect" => {Dispatch, :companion_websocket_disconnect_cmd},
      "elmx_companion_websocket_send" => {Dispatch, :companion_websocket_send_cmd}
    }
  end
end
