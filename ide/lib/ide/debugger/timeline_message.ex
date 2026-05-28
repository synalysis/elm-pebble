defmodule Ide.Debugger.TimelineMessage do
  @moduledoc false

  alias Ide.Debugger.RuntimeModelMessages

  @spec format(String.t(), map() | integer() | boolean() | String.t() | nil) :: String.t()
  def format(message, message_value \\ nil)

  def format(message, message_value) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      trimmed == "" ->
        ""

      message_value != nil ->
        ctor = RuntimeModelMessages.wire_constructor(trimmed) || trimmed

        case payload_text(message_value) do
          "" -> ctor
          payload -> "#{ctor} #{payload}"
        end

      String.contains?(trimmed, " ") ->
        case split(trimmed) do
          {ctor, "", _} -> ctor
          _ -> trimmed
        end

      true ->
        trimmed
    end
  end

  def format(message, _message_value), do: format(to_string(message || ""), nil)

  @spec message_value_for_step(String.t(), map() | nil) ::
          {String.t(), map() | integer() | boolean() | String.t() | nil}
  def message_value_for_step(message, explicit_value \\ nil)

  def message_value_for_step(message, explicit_value) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      is_map(explicit_value) ->
        {RuntimeModelMessages.wire_constructor(trimmed) || trimmed, explicit_value}

      true ->
        case split(trimmed) do
          {ctor, "", nil} ->
            {ctor, nil}

          {ctor, _display, wire_value} ->
            {ctor, wire_value}
        end
    end
  end

  def message_value_for_step(message, explicit_value),
    do: message_value_for_step(to_string(message || ""), explicit_value)

  @spec split(String.t()) ::
          {String.t(), String.t(), map() | integer() | boolean() | String.t() | nil}
  def split(message) when is_binary(message) do
    trimmed = String.trim(message)

    case String.split(trimmed, ~r/\s+/, parts: 2) do
      [ctor] ->
        {ctor, "", nil}

      [ctor, payload] ->
        payload = String.trim(payload)
        wire_value = wire_value_from_payload(ctor, payload)
        display = if wire_value == nil, do: payload, else: payload_text(wire_value)
        {ctor, display, wire_value}
    end
  end

  @spec wire_value_from_payload(String.t(), String.t()) ::
          map() | integer() | boolean() | String.t() | nil
  defp wire_value_from_payload(_ctor, ""), do: nil

  defp wire_value_from_payload(ctor, payload) when is_binary(ctor) and is_binary(payload) do
    case literal_payload(payload) do
      nil ->
        nil

      value when is_integer(value) or is_boolean(value) or is_binary(value) ->
        %{"ctor" => ctor, "args" => [value]}

      value when is_map(value) or is_list(value) ->
        %{"ctor" => ctor, "args" => [value]}
    end
  end

  @spec literal_payload(String.t()) :: map() | list() | integer() | boolean() | String.t() | nil
  defp literal_payload(""), do: nil
  defp literal_payload("True"), do: true
  defp literal_payload("False"), do: false

  defp literal_payload(payload) when is_binary(payload) do
    cond do
      String.match?(payload, ~r/^-?\d+$/) ->
        case Integer.parse(payload) do
          {value, ""} -> value
          _ -> nil
        end

      String.starts_with?(payload, "{") or String.starts_with?(payload, "[") or
          String.starts_with?(payload, "\"") ->
        case Jason.decode(payload) do
          {:ok, value} -> value
          _ -> nil
        end

      true ->
        nil
    end
  end

  @spec payload_text(map() | integer() | boolean() | String.t()) :: String.t()
  defp payload_text(%{} = value), do: Jason.encode!(value)

  defp payload_text(value) when is_integer(value), do: Integer.to_string(value)
  defp payload_text(value) when is_boolean(value), do: if(value, do: "True", else: "False")
  defp payload_text(value) when is_binary(value), do: inspect(value, charlists: :as_lists)
  defp payload_text(value), do: inspect(value, charlists: :as_lists)
end
