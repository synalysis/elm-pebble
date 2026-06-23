defmodule Elmc.Backend.CCodegen.SpecialValues.Phone do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()


  def special_value_from_target("Elm.Kernel.PebblePhone.httpGet", [url, to_msg]),
    do: Helpers.http_request_constructor_expr("GET", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpPost", [url, to_msg]),
    do: Helpers.http_request_constructor_expr("POST", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpPut", [url, to_msg]),
    do: Helpers.http_request_constructor_expr("PUT", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpDelete", [url, to_msg]),
    do: Helpers.http_request_constructor_expr("DELETE", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpRequest", [method, url]),
    do: %{op: :qualified_call, target: "Pebble.Http.requestImpl", args: [method, url]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpWithHeader", [name, value, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withHeaderImpl", args: [name, value, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpWithTimeout", [timeout, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withTimeoutImpl", args: [timeout, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpWithBody", [body, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withBodyImpl", args: [body, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpExpectString", [to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectStringImpl", args: [to_msg, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpExpectJson", [decoder, to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectJsonImpl", args: [decoder, to_msg, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpExpectBytes", [to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectBytesImpl", args: [to_msg, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSave", [key, value, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Save", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoad", [key, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Load", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageRemove", [key, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Remove", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageClear", [to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Clear", args: [to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSaveJson", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveJsonImpl", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoadJson", [key, decoder, to_msg]),
    do: %{
      op: :qualified_call,
      target: "Pebble.Storage.loadJsonImpl",
      args: [key, decoder, to_msg]
    }

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSaveInt", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveIntImpl", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoadInt", [key, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.loadIntImpl", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSaveBool", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveBoolImpl", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoadBool", [key, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.loadBoolImpl", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketConnect", [url, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Connect", args: [url, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketDisconnect", [to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Disconnect", args: [to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketSend", [message, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Send", args: [message, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketSendJson", [json_data, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.SendJson", args: [json_data, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketIsConnected", [state]),
    do: %{op: :qualified_call, target: "Pebble.WebSocket.isConnectedImpl", args: [state]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketGetState", [state]),
    do: %{op: :qualified_call, target: "Pebble.WebSocket.getStateImpl", args: [state]}


  def special_value_from_target(_target, _args), do: nil
end
