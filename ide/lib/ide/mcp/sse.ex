defmodule Ide.Mcp.Sse do
  @moduledoc false

  alias Ide.Mcp.WireTypes

  @spec priming_event() :: String.t()
  def priming_event, do: "id: 0\ndata:\n\n"

  @spec comment(String.t()) :: String.t()
  def comment(text), do: ": #{text}\n\n"

  @spec message_event(WireTypes.sse_message() | String.t()) :: String.t()
  def message_event(json) when is_binary(json), do: "event: message\ndata: #{json}\n\n"

  def message_event(payload) when is_map(payload), do: message_event(Jason.encode!(payload))
end
