defmodule Elmx.Runtime.Subscriptions.ActiveSet do
  @moduledoc """
  Flattens runtime `Sub` values from `subscriptions/1` into `cmd.subscription.register` maps.
  """

  alias Elmx.Runtime.Followups.Flatten
  alias Elmx.Types

  @register_kind "cmd.subscription.register"

  @spec from_value(term()) :: [Types.wire_cmd()]
  def from_value(nil), do: []
  def from_value(0), do: []
  def from_value(value) when is_integer(value) and value <= 0, do: []
  def from_value(value) when is_integer(value), do: []

  def from_value(%{"kind" => @register_kind} = command), do: register_commands(command)

  def from_value(%{kind: kind} = command) when is_binary(kind) or is_atom(kind) do
    from_value(stringify_keys(command))
  end

  def from_value(%{"$" => 2, "m" => items}) when is_list(items) do
    Enum.flat_map(items, &from_value/1)
  end

  def from_value(%{"$" => 3, "o" => inner}), do: from_value(inner)

  def from_value(items) when is_list(items), do: Enum.flat_map(items, &from_value/1)
  def from_value(_), do: []

  @spec register_commands(Types.wire_cmd() | map()) :: [Types.wire_cmd()]
  defp register_commands(command) do
    Flatten.flatten(command)
    |> Enum.filter(&register_command?/1)
    |> Enum.map(&normalize_register/1)
  end

  @spec register_command?(Types.wire_cmd()) :: boolean()
  defp register_command?(%{"kind" => @register_kind}), do: true
  defp register_command?(%{kind: kind}) when kind in [@register_kind, :cmd_subscription_register], do: true
  defp register_command?(_), do: false

  @spec normalize_register(Types.wire_cmd()) :: Types.wire_cmd()
  defp normalize_register(command) when is_map(command) do
    command
    |> stringify_keys()
    |> Map.update("message", "", &wire_string/1)
    |> Map.update("target", "", &wire_string/1)
  end

  @spec stringify_keys(map()) :: map()
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  @spec wire_string(term()) :: String.t()
  defp wire_string(value) when is_binary(value), do: value
  defp wire_string(value) when is_atom(value), do: Atom.to_string(value)
  defp wire_string(value), do: to_string(value)
end
