defmodule Elmx.Runtime.Followups.Protocol do
  @moduledoc false

  alias Elmx.Runtime.Followups.Flatten
  alias Elmx.Types

  @spec events(Types.wire_cmd() | [Types.wire_cmd()]) :: [Types.protocol_event()]
  def events(commands) do
    commands
    |> Flatten.flatten()
    |> Enum.filter(&(Map.get(&1, "kind") == "protocol"))
    |> Enum.flat_map(&event_pair/1)
  end

  @spec event_pair(Types.wire_cmd()) :: [Types.protocol_event()]
  def event_pair(command) when is_map(command) do
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
