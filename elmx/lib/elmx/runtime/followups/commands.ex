defmodule Elmx.Runtime.Followups.Commands do
  @moduledoc false

  alias Elmx.Types

  @spec to_followups(Types.wire_cmd(), String.t()) :: [Types.followup_row()]
  def to_followups(%{"kind" => "protocol"} = command, source_root) do
    [
      %{
        "message" => Map.get(command, "message"),
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "protocol_command",
        "package" => Map.get(command, "package", "companion-protocol"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "cmd.timer.after"} = command, source_root) do
    [
      %{
        "message" => Map.get(command, "message") || "TimerFired",
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "timer_command",
        "package" => Map.get(command, "package", "pebble/cmd"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "cmd.device." <> _} = command, source_root) do
    [
      %{
        "message" => Map.get(command, "message") || "DeviceLoaded",
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "device_command",
        "package" => Map.get(command, "package", "elm-pebble/elm-watch"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "cmd.storage.read_" <> _} = command, source_root) do
    [
      %{
        "message" => Map.get(command, "message") || "StorageLoaded",
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "storage_command",
        "package" => Map.get(command, "package", "elm-pebble/elm-watch"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "cmd.dictation.followup"} = command, source_root) do
    [
      %{
        "message" => Map.get(command, "message"),
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "runtime_followup",
        "package" => Map.get(command, "package", "pebble/dictation"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "cmd.companion.bridge"} = command, source_root) do
    callback = Map.get(command, "callback_constructor") || "Unknown"

    [
      %{
        "message" => callback,
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "companion_bridge_command",
        "package" => Map.get(command, "package", "pebble/companion"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "http"} = command, source_root) do
    message =
      command
      |> Map.get("expect")
      |> case do
        %{"to_msg" => ctor} when is_binary(ctor) -> ctor
        %{to_msg: ctor} when is_binary(ctor) -> ctor
        _ -> "HttpResponse"
      end

    [
      %{
        "message" => message,
        "message_value" => nil,
        "source_root" => source_root,
        "source" => "http_command",
        "package" => Map.get(command, "package", "elm/http"),
        "command" => command
      }
    ]
  end

  def to_followups(%{"kind" => "cmd.task.immediate"} = command, source_root) do
    message = Map.get(command, "message")

    if is_binary(message) and message != "" do
      [
        %{
          "message" => message,
          "message_value" => Map.get(command, "message_value"),
          "source_root" => source_root,
          "source" => "task_command",
          "package" => Map.get(command, "package", "elm/core"),
          "command" => command
        }
      ]
    else
      []
    end
  end

  def to_followups(%{"kind" => "cmd.subscription.register"} = command, source_root) do
    message = Map.get(command, "message")

    if is_binary(message) and message != "" do
      [
        %{
          "message" => message,
          "message_value" => Map.get(command, "message_value"),
          "source_root" => source_root,
          "source" => "subscription_command",
          "package" => Map.get(command, "package", "elm-pebble/elm-watch"),
          "command" => command
        }
      ]
    else
      []
    end
  end

  def to_followups(%{"kind" => "cmd.storage." <> _} = command, source_root) do
    [
      %{
        "message" => Map.get(command, "message"),
        "message_value" => Map.get(command, "message_value"),
        "source_root" => source_root,
        "source" => "storage_command",
        "package" => Map.get(command, "package", "elm-pebble/elm-watch"),
        "command" => command
      }
    ]
  end

  def to_followups(_command, _source_root), do: []
end
