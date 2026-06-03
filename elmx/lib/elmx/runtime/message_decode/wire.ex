defmodule Elmx.Runtime.MessageDecode.Wire do
  @moduledoc false

  alias Elmx.Runtime.MessageDecode.Ctor
  alias Elmx.Types

  @spec decode(Types.wire_value(), String.t() | Types.elm_msg() | nil) :: Types.elm_msg()
  def decode(%{"ctor" => "FromPhone", "args" => [inner | _]}, _message),
    do: {:FromPhone, to_runtime(inner)}

  def decode(%{"ctor" => "FromPhone", "args" => []}, _message), do: :FromPhone

  def decode(wire, "FromPhone") when is_map(wire), do: {:FromPhone, to_runtime(wire)}

  def decode(wire, message) when is_map(wire) do
    ctor = Map.get(wire, "ctor") || Map.get(wire, :ctor)

    cond do
      matches_parent?(ctor, message) ->
        to_runtime(wire)

      parent_wraps_payload?(message, ctor) ->
        {String.to_atom(message), to_runtime(wire)}

      is_binary(message) and message != "" and (is_nil(ctor) or ctor == "") ->
        {String.to_atom(message_ctor(message)), to_runtime(wire)}

      true ->
        to_runtime(wire)
    end
  end

  def decode(wire, _message), do: wire

  @spec to_runtime(Types.wire_value()) :: Types.elm_msg()
  def to_runtime(%{"ctor" => "True", "args" => []}), do: true
  def to_runtime(%{"ctor" => "False", "args" => []}), do: false
  def to_runtime(%{"ctor" => "()", "args" => []}), do: nil

  def to_runtime(%{"ctor" => ctor, "args" => args})
      when is_binary(ctor) and is_list(args) do
    Ctor.build(ctor, Enum.map(args, &to_runtime/1))
  end

  def to_runtime(list) when is_list(list), do: Enum.map(list, &to_runtime/1)

  def to_runtime(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_runtime(v)} end)
  end

  def to_runtime(:True), do: true
  def to_runtime(:False), do: false
  def to_runtime(value), do: value

  @spec message_ctor(String.t()) :: String.t()
  def message_ctor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/[\s{(]/, parts: 2)
    |> List.first()
    |> to_string()
  end

  defp matches_parent?(ctor, message) when is_binary(ctor) and is_binary(message) do
    String.downcase(ctor) == String.downcase(message_ctor(message))
  end

  defp matches_parent?(_ctor, _message), do: false

  defp parent_wraps_payload?(_message, ctor) when ctor in ["Ok", "Err", "Nothing", "Just"], do: true
  defp parent_wraps_payload?(_message, _ctor), do: false
end
