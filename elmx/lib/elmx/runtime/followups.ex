defmodule Elmx.Runtime.Followups do
  @moduledoc """
  Maps wire-format runtime commands to debugger `followup_messages` rows.
  """

  alias Elmx.Types

  @default_source_root "watch"

  @spec protocol_events(term()) :: [Types.wire_cmd()]
  def protocol_events(commands) do
    commands
    |> flatten_commands()
    |> Enum.filter(&(Map.get(&1, "kind") == "protocol"))
    |> Enum.flat_map(&protocol_event_pair/1)
  end

  @spec from_commands(term(), keyword()) :: [Types.followup_row()]
  def from_commands(commands, opts \\ []) do
    source_root = Keyword.get(opts, :source_root, @default_source_root)

    commands
    |> flatten_commands()
    |> Enum.flat_map(&command_to_followups(&1, source_root))
  end

  @spec flatten_commands(term()) :: [Types.wire_cmd()]
  def flatten_commands(%{"kind" => "batch", "commands" => commands}) when is_list(commands) do
    Enum.flat_map(commands, &flatten_commands/1)
  end

  def flatten_commands(%{kind: "batch", commands: commands}) when is_list(commands) do
    flatten_commands(%{"kind" => "batch", "commands" => commands})
  end

  def flatten_commands(%{"kind" => "none"}), do: []
  def flatten_commands(%{kind: "none"}), do: []
  def flatten_commands(%{"kind" => _} = command), do: [command]
  def flatten_commands(%{kind: _} = command), do: [stringify_keys(command)]
  def flatten_commands(commands) when is_list(commands), do: Enum.flat_map(commands, &flatten_commands/1)
  def flatten_commands(_), do: []

  defp command_to_followups(%{"kind" => "protocol"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.timer.after"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.device." <> _} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.storage.read_" <> _} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.dictation.followup"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.companion.bridge"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "http"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.task.immediate"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.subscription.register"} = command, source_root) do
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

  defp command_to_followups(%{"kind" => "cmd.storage." <> _} = command, source_root) do
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

  defp command_to_followups(_command, _source_root), do: []

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp protocol_event_pair(command) when is_map(command) do
    message = Map.get(command, "message")
    message_value = Map.get(command, "message_value")

    if is_binary(message) and message != "" do
      payload = %{
        "from" => Map.get(command, "from", "watch"),
        "to" => Map.get(command, "to", "companion"),
        "message" => message,
        "message_value" => message_value,
        "trigger" => "runtime_cmd",
        "message_source" => "runtime_cmd"
      }

      [
        %{type: "debugger.protocol_tx", payload: payload},
        %{type: "debugger.protocol_rx", payload: payload}
      ]
    else
      []
    end
  end
end
