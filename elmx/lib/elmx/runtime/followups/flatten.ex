defmodule Elmx.Runtime.Followups.Flatten do
  @moduledoc false

  alias Elmx.Types

  @spec flatten(Types.wire_cmd_input() | [Types.wire_cmd_input()]) :: [Types.wire_cmd()]
  def flatten(%{"kind" => "batch", "commands" => commands}) when is_list(commands) do
    Enum.flat_map(commands, &flatten/1)
  end

  def flatten(%{kind: "batch", commands: commands}) when is_list(commands) do
    flatten(%{"kind" => "batch", "commands" => commands})
  end

  def flatten(%{"kind" => "none"}), do: []
  def flatten(%{kind: "none"}), do: []
  def flatten(%{"kind" => _} = command), do: [command]
  def flatten(%{kind: _} = command), do: [stringify_keys(command)]
  def flatten(commands) when is_list(commands), do: Enum.flat_map(commands, &flatten/1)
  def flatten(_), do: []

  @spec stringify_keys(map()) :: Types.wire_cmd()
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
