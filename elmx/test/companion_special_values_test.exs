defmodule Elmx.CompanionSpecialValuesTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues

  test "sendPhoneToWatch rewrites to phone protocol runtime call" do
    message = %{
      op: :tuple2,
      left: %{op: :int_literal, value: 0, union_ctor: "Companion.Types.ProvideBattery"},
      right: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 42},
        right: %{op: :int_literal, value: 1}
      }
    }

    assert {:ok, %{op: :runtime_call, function: "elmx_companion_send_phone", args: [^message]}} =
             SpecialValues.rewrite("Pebble.Companion.Phone.sendPhoneToWatch", [message])
  end

  test "runtime phone protocol cmd uses phone_to_watch direction" do
    cmd =
      Pebble.runtime_dispatch("elmx_companion_send_phone", [
        {:ProvideBattery, 42, true}
      ])

    assert cmd["kind"] == "protocol"
    assert cmd["direction"] == "phone_to_watch"
    assert cmd["from"] == "companion"
    assert cmd["to"] == "watch"
    assert cmd["message"] == "ProvideBattery"
  end

  test "companion timeline getToken rewrites to bridge command" do
    callback = %{"ctor" => "GotToken", "args" => []}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_bridge_cmd",
              args: [
                %{op: :string_literal, value: "timeline"},
                %{op: :string_literal, value: "getToken"},
                %{op: :string_literal, value: "GotToken"}
              ]
            }} = SpecialValues.rewrite("Pebble.Companion.Timeline.getToken", [callback])
  end

  test "companion timeline getToken uses union ctor callback name" do
    callback = %{op: :int_literal, value: 0, union_ctor: "CompanionApp.Msg.GotToken"}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_bridge_cmd",
              args: [
                %{op: :string_literal, value: "timeline"},
                %{op: :string_literal, value: "getToken"},
                %{op: :string_literal, value: "GotToken"}
              ]
            }} = SpecialValues.rewrite("Pebble.Companion.Timeline.getToken", [callback])
  end

  test "companion timeline insertPin uses last arg as callback" do
    pin_json = %{op: :var, name: "pinJson"}
    callback = %{op: :int_literal, value: 1, union_ctor: "CompanionApp.Msg.PinInserted"}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_bridge_cmd",
              args: [
                %{op: :string_literal, value: "timeline"},
                %{op: :string_literal, value: "insertPin"},
                %{op: :string_literal, value: "PinInserted"}
              ]
            }} = SpecialValues.rewrite("Pebble.Companion.Timeline.insertPin", [pin_json, callback])
  end

  test "companion storage get/set rewrite to bridge commands" do
    callback = %{op: :var, name: "GotStorage"}

    assert {:ok, %{op: :runtime_call, function: "elmx_companion_storage_get", args: ["theme", ^callback]}} =
             SpecialValues.rewrite("Pebble.Companion.Storage.get", ["theme", callback])

    value = %{op: :constructor_call, target: "StringValue", args: [%{op: :string_literal, value: "light"}]}

    assert {:ok, %{op: :runtime_call, function: "elmx_companion_storage_set", args: ["theme", ^value]}} =
             SpecialValues.rewrite("Pebble.Companion.Storage.set", ["theme", value])
  end

  test "companion storage bridge runtime commands carry storage target" do
    cmd =
      Pebble.runtime_dispatch("elmx_companion_storage_get", [
        "theme",
        %{"ctor" => "GotStorage", "args" => []}
      ])

    assert cmd["kind"] == "cmd.companion.bridge"
    assert cmd["target"] == "Pebble.Companion.Storage.get"
    assert cmd["api"] == "storage"
    assert cmd["op"] == "get"
    assert cmd["key"] == "theme"
    assert cmd["callback_constructor"] == "GotStorage"
  end

  test "companion platform setup commands rewrite to cmd none" do
    for target <- [
          "Pebble.Companion.Battery.setup",
          "Pebble.Companion.Locale.setup",
          "Pebble.Companion.Calendar.setup",
          "Pebble.Companion.Configuration.setup",
          "Pebble.Companion.Lifecycle.setup",
          "Pebble.Companion.Environment.setup"
        ] do
      assert {:ok, %{op: :cmd_none}} = SpecialValues.rewrite(target, [])
    end
  end

  test "companion platform current commands rewrite to bridge commands" do
    callback = %{"ctor" => "GotBattery", "args" => []}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_bridge_cmd",
              args: [
                %{op: :string_literal, value: "battery"},
                %{op: :string_literal, value: "status"},
                %{op: :string_literal, value: "GotBattery"}
              ]
            }} = SpecialValues.rewrite("Pebble.Companion.Battery.current", [callback])
  end

  test "companion connectivity current rewrites to network status bridge" do
    callback = %{"ctor" => "GotConnectivity", "args" => []}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_bridge_cmd",
              args: [
                %{op: :string_literal, value: "network"},
                %{op: :string_literal, value: "status"},
                %{op: :string_literal, value: "GotConnectivity"}
              ]
            }} = SpecialValues.rewrite("Pebble.Companion.Connectivity.current", [callback])
  end

  test "companion platform subscriptions rewrite to zero mask" do
    for target <- [
          "Pebble.Companion.Weather.onWeather",
          "Pebble.Companion.Environment.onEnvironment",
          "Pebble.Companion.Battery.onBattery",
          "Pebble.Companion.WebSocket.onWebSocket",
          "Pebble.Companion.Timeline.onToken",
          "Pebble.Companion.Lifecycle.onLifecycle"
        ] do
      assert {:ok, %{op: :int_literal, value: 0}} = SpecialValues.rewrite(target, [])
    end
  end

  test "Phone.send rewrites nested Phone.request to envelope record for phone send" do
    callback = %{op: :var, name: "GotToken"}

    request_call = %{
      op: :qualified_call,
      target: "Pebble.Companion.Phone.request",
      args: [
        %{op: :string_literal, value: "timeline-get-token"},
        %{op: :string_literal, value: "timeline"},
        %{op: :string_literal, value: "getToken"},
        %{op: :var, name: "decodeTokenResponse"}
      ]
    }

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_phone_send",
              args: [
                ^callback,
                %{
                  op: :record_literal,
                  fields: [
                    {"id", %{op: :string_literal, value: "timeline-get-token"}},
                    {"api", %{op: :string_literal, value: "timeline"}},
                    {"op", %{op: :string_literal, value: "getToken"}},
                    {"payload", %{op: :record_literal, fields: []}}
                  ]
                }
              ]
            }} = SpecialValues.rewrite("Pebble.Companion.Phone.send", [callback, request_call])
  end

  test "Phone.send rewrites constructor Request envelope for phone send" do
    callback = %{op: :var, name: "Connected"}

    request = %{
      op: :constructor_call,
      target: "Request",
      args: [
        %{
          op: :record,
          fields: %{
            "id" => %{op: :string_literal, value: "webSocket-connect"},
            "api" => %{op: :string_literal, value: "webSocket"},
            "op" => %{op: :string_literal, value: "connect"},
            "payload" => %{op: :record, fields: %{"url" => %{op: :string_literal, value: "wss://example.test"}}}
          }
        }
      ]
    }

    assert {:ok, %{op: :runtime_call, function: "elmx_companion_phone_send", args: [^callback, ^request]}} =
             SpecialValues.rewrite("Pebble.Companion.Phone.send", [callback, request])
  end

  test "Phone.send runtime emits webSocket connect bridge command" do
    request = %{
      "ctor" => "Request",
      "args" => [
        %{
          "id" => "webSocket-connect",
          "api" => "webSocket",
          "op" => "connect",
          "payload" => %{"url" => "wss://example.test"}
        }
      ]
    }

    cmd = Pebble.runtime_dispatch("elmx_companion_phone_send", ["Connected", request])

    assert cmd["kind"] == "cmd.companion.bridge"
    assert cmd["api"] == "webSocket"
    assert cmd["op"] == "connect"
    assert cmd["callback_constructor"] == "Connected"
    assert cmd["bridge_id"] == "webSocket-connect"
    assert cmd["payload"] == %{"url" => "wss://example.test"}
  end

  test "WebSocket.connect rewrites to webSocket bridge command" do
    callback = %{op: :var, name: "Connected"}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_websocket_connect",
              args: ["wss://example.test", ^callback]
            }} =
             SpecialValues.rewrite("Pebble.Companion.WebSocket.connect", ["wss://example.test", callback])
  end

  test "WebSocket.connect runtime emits connect bridge command" do
    cmd = Pebble.runtime_dispatch("elmx_companion_websocket_connect", ["wss://example.test", "Connected"])

    assert cmd["api"] == "webSocket"
    assert cmd["op"] == "connect"
    assert cmd["callback_constructor"] == "Connected"
    assert cmd["payload"] == %{"url" => "wss://example.test"}
  end

  test "Phone.sendBridgeCommand rewrites and runtime emits companion bridge cmd" do
    envelope = %{
      op: :record_literal,
      fields: [
        {"id", %{op: :string_literal, value: "storage-get-theme"}},
        {"api", %{op: :string_literal, value: "storage"}},
        {"op", %{op: :string_literal, value: "get"}},
        {"payload", %{op: :record_literal, fields: [{"key", %{op: :string_literal, value: "theme"}}]}}
      ]
    }

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_send_bridge_command",
              args: [^envelope]
            }} = SpecialValues.rewrite("Pebble.Companion.Phone.sendBridgeCommand", [envelope])

    cmd = Pebble.runtime_dispatch("elmx_companion_send_bridge_command", [
      %{"id" => "storage-get-theme", "api" => "storage", "op" => "get", "payload" => %{"key" => "theme"}}
    ])

    assert cmd["kind"] == "cmd.companion.bridge"
    assert cmd["api"] == "storage"
    assert cmd["op"] == "get"
    assert cmd["bridge_id"] == "storage-get-theme"
    assert cmd["payload"] == %{"key" => "theme"}
  end

  test "companion request builders stay cmd none" do
    assert {:ok, %{op: :cmd_none}} =
             SpecialValues.rewrite("Pebble.Companion.Phone.requestWithPayload", [])
  end

  test "Phone.outgoing and registerHandler rewrite to cmd_none" do
    payload = %{op: :string_literal, value: "ping"}

    for target <- [
          "Pebble.Companion.Phone.outgoing",
          "Pebble.Companion.Phone.registerHandler",
          "Pebble.Companion.Phone.registerResponseHandler"
        ] do
      assert {:ok, %{op: :cmd_none}} = SpecialValues.rewrite(target, [payload])
    end
  end

  test "unlisted companion API falls back to cmd none" do
    assert {:ok, %{op: :cmd_none}} =
             SpecialValues.rewrite("Pebble.Companion.DemoBridge.probeCommand", [])
  end

  test "configuration onClosed with handler lowers to runtime subscribe" do
    to_msg = %{op: :var, name: "toMsg"}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_configuration_on_closed",
              args: [^to_msg]
            }} = SpecialValues.rewrite("Pebble.Companion.Configuration.onClosed", [to_msg])

    assert {:ok, %{op: :int_literal, value: 0}} =
             SpecialValues.rewrite("Pebble.Companion.Configuration.onClosed", [])
  end

  test "preferences decodeResponse lowers to runtime decode helper" do
    schema = %{op: :var, name: "schema"}
    response = %{op: :var, name: "response"}

    assert {:ok,
            %{
              op: :runtime_call,
              function: "elmx_companion_preferences_decode_response",
              args: [^schema, ^response]
            }} =
             SpecialValues.rewrite("Pebble.Companion.Preferences.decodeResponse", [
               schema,
               response
             ])
  end

  test "protocol_phone_to_watch followup uses companion source root" do
    cmd = Cmd.protocol_phone_to_watch({:ProvideLocale, "en-US"})

    assert [%{"source" => "protocol_command", "source_root" => "phone"}] =
             Elmx.Runtime.Followups.from_commands(cmd, source_root: "phone")
  end
end
