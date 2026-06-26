defmodule Ide.Debugger.TimelineMessage do
  @moduledoc false

  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Types
  alias Ide.Debugger.WireDisplay

  @subscription_wrapper_ctors ~w(FromPhone FromWatch)

  @spec format(String.t(), Types.timeline_step_message_value()) :: String.t()
  def format(message, message_value \\ nil)

  def format(message, message_value) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      trimmed == "" ->
        ""

      message_value != nil ->
        ctor = RuntimeModelMessages.wire_constructor(trimmed) || trimmed

        payload =
          case matching_ctor_payload(ctor, message_value) do
            nil -> payload_text(message_value)
            text -> text
          end

        case payload do
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

  @spec message_value_for_step(String.t(), Types.timeline_step_message_value()) ::
          {String.t(), Types.timeline_step_message_value()}
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
          {String.t(), String.t(), Types.timeline_step_message_value()}
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
          Types.timeline_step_message_value()
  defp wire_value_from_payload(_ctor, ""), do: nil

  defp wire_value_from_payload(ctor, payload) when is_binary(ctor) and is_binary(payload) do
    case literal_payload(payload) do
      nil ->
        if protocol_constructor_token?(payload) do
          %{"ctor" => ctor, "args" => [%{"ctor" => payload, "args" => []}]}
        else
          nil
        end

      value when is_integer(value) or is_boolean(value) or is_binary(value) ->
        %{"ctor" => ctor, "args" => [value]}

      value when is_map(value) or is_list(value) ->
        %{"ctor" => ctor, "args" => [value]}
    end
  end

  @spec protocol_constructor_token?(String.t()) :: boolean()
  defp protocol_constructor_token?(token) when is_binary(token) do
    Regex.match?(~r/^[A-Z][a-zA-Z0-9]*$/, token)
  end

  @spec literal_payload(String.t()) :: Types.protocol_wire_arg() | nil
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

  @spec matching_ctor_payload(String.t(), Types.protocol_wire_arg()) :: String.t() | nil
  defp matching_ctor_payload(ctor, _message_value) when ctor in @subscription_wrapper_ctors, do: nil

  defp matching_ctor_payload(ctor, message_value) when is_binary(ctor) do
    case wire_ctor_parts(message_value) do
      {^ctor, args} -> display_args_payload(args)
      _ -> nil
    end
  end

  defp matching_ctor_payload(_ctor, _message_value), do: nil

  @spec display_args_payload([Types.protocol_wire_arg()]) :: String.t()
  defp display_args_payload([]), do: ""

  defp display_args_payload([single]) do
    if is_map(single) and not protocol_constructor?(single) do
      WireDisplay.format(single)
    else
      protocol_arg_display(single)
    end
  end

  defp display_args_payload(args) when is_list(args),
    do: Enum.map_join(args, " ", &protocol_arg_display/1)

  @spec payload_text(Types.protocol_wire_arg()) :: String.t()
  defp payload_text(value) do
    case wire_ctor_parts(value) do
      {ctor, args} when ctor in @subscription_wrapper_ctors ->
        case args do
          [inner] -> "(#{wire_ctor_display(inner)})"
          _ -> wire_ctor_display(value)
        end

      {ctor, args} when is_binary(ctor) ->
        wire_ctor_display(%{"ctor" => ctor, "args" => args})

      _ ->
        primitive_payload_text(value)
    end
  end

  @spec wire_ctor_parts(Types.protocol_wire_arg()) :: {String.t() | nil, list()}
  defp wire_ctor_parts(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: {ctor, List.wrap(args)}

  defp wire_ctor_parts(%{ctor: ctor, args: args}) when is_binary(ctor),
    do: {ctor, List.wrap(args)}

  defp wire_ctor_parts(_value), do: {nil, []}

  @spec wire_ctor_display(Types.protocol_wire_arg()) :: String.t()
  defp wire_ctor_display(value), do: wire_ctor_display_inner(value)

  defp wire_ctor_display_inner(value) do
    case wire_ctor_parts(value) do
      {ctor, args} when is_binary(ctor) ->
        protocol_message_display(ctor, args)

      _ ->
        primitive_payload_text(value)
    end
  end

  @spec protocol_constructor?(Types.wire_input()) :: boolean()
  defp protocol_constructor?(%{"ctor" => ctor}) when is_binary(ctor), do: true
  defp protocol_constructor?(%{ctor: ctor}) when is_binary(ctor), do: true
  defp protocol_constructor?(_), do: false

  @spec protocol_message_display(String.t(), [Types.protocol_wire_arg()]) :: String.t()
  defp protocol_message_display(ctor, args) when is_binary(ctor) and is_list(args) do
    case args do
      [] -> ctor
      _ -> ctor <> " " <> Enum.map_join(args, " ", &protocol_arg_display/1)
    end
  end

  @spec protocol_arg_display(Types.protocol_wire_arg()) :: String.t()
  defp protocol_arg_display(%{"ctor" => ctor, "args" => []}) when is_binary(ctor), do: ctor
  defp protocol_arg_display(%{ctor: ctor, args: []}) when is_binary(ctor), do: ctor

  defp protocol_arg_display(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args) do
    inner = protocol_message_display(ctor, args)
    if String.contains?(inner, " "), do: "(#{inner})", else: inner
  end

  defp protocol_arg_display(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args) do
    protocol_arg_display(%{"ctor" => ctor, "args" => args})
  end

  defp protocol_arg_display(value) when is_list(value), do: WireDisplay.format(value)

  defp protocol_arg_display(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: WireDisplay.format(value)

  defp protocol_arg_display(value) when is_binary(value), do: WireDisplay.format(value)
  defp protocol_arg_display(value) when is_map(value), do: WireDisplay.format(value)
  defp protocol_arg_display(value), do: WireDisplay.format(value)

  @spec primitive_payload_text(Types.protocol_wire_arg()) :: String.t()
  defp primitive_payload_text(value), do: WireDisplay.format(value)
end
