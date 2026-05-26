defmodule Ide.Debugger.ConfigurationProtocol do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.Types

  @spec events_applied?(map(), non_neg_integer()) :: boolean()
  def events_applied?(state, seq_before)
      when is_map(state) and is_integer(seq_before) do
    state
    |> Map.get(:events, [])
    |> Enum.any?(fn
      %{seq: seq, type: type, payload: payload} ->
        is_integer(seq) and seq > seq_before and
          type in ["debugger.protocol_tx", "debugger.protocol_rx"] and is_map(payload) and
          (Map.get(payload, :trigger) || Map.get(payload, "trigger")) == "configuration" and
          (Map.get(payload, :from) || Map.get(payload, "from")) == "companion" and
          (Map.get(payload, :to) || Map.get(payload, "to")) == "watch"

      %{"seq" => seq, "type" => type, "payload" => payload} ->
        is_integer(seq) and seq > seq_before and
          type in ["debugger.protocol_tx", "debugger.protocol_rx"] and is_map(payload) and
          (Map.get(payload, :trigger) || Map.get(payload, "trigger")) == "configuration" and
          (Map.get(payload, :from) || Map.get(payload, "from")) == "companion" and
          (Map.get(payload, :to) || Map.get(payload, "to")) == "watch"

      _ ->
        false
    end)
  end

  def events_applied?(_state, _seq_before), do: false

  @spec encode_values(map(), map()) :: map()
  def encode_values(configuration, values) when is_map(configuration) and is_map(values) do
    configuration
    |> fields()
    |> Enum.reduce(%{}, fn field, acc ->
      id = Map.get(field, "id")
      control = Map.get(field, "control", %{})

      if is_binary(id) and id != "" do
        Map.put(acc, id, encode_value(control, field_value(values, id, control)))
      else
        acc
      end
    end)
  end

  def encode_values(_configuration, values) when is_map(values), do: values

  @spec changed_values(map(), map()) :: map()
  def changed_values(next_values, previous_values)
      when is_map(next_values) and is_map(previous_values) do
    Map.new(next_values, fn {key, value} -> {key, value} end)
    |> Enum.reject(fn {key, value} -> Map.get(previous_values, key) == value end)
    |> Map.new()
  end

  @spec fields(map()) :: [map()]
  def fields(configuration) when is_map(configuration) do
    configuration
    |> Map.get("sections", [])
    |> Enum.flat_map(fn
      %{"fields" => fields} when is_list(fields) -> fields
      %{fields: fields} when is_list(fields) -> fields
      _ -> []
    end)
  end

  @spec apply_messages(map(), map(), map(), ProtocolRx.ctx()) :: map()
  def apply_messages(state, configuration, values, rx_ctx)
      when is_map(state) and is_map(configuration) and is_map(values) and is_map(rx_ctx) do
    events =
      configuration
      |> fields()
      |> Enum.flat_map(&protocol_events(&1, values))

    state
    |> ProtocolRx.append_events(events, rx_ctx)
    |> ProtocolRx.apply_state_effects(events, rx_ctx)
  end

  def apply_messages(state, _configuration, _values, _rx_ctx), do: state

  @spec field_value(map(), String.t(), map()) :: Types.wire_input()
  defp field_value(values, id, control) when is_map(values) and is_binary(id) and is_map(control) do
    if Map.has_key?(values, id), do: Map.get(values, id), else: Map.get(control, "default")
  end

  @spec encode_value(map(), Types.wire_input()) :: Types.wire_input()
  defp encode_value(%{"type" => "toggle"}, value), do: truthy?(value)

  defp encode_value(%{"type" => type}, value) when type in ["number", "slider"] do
    case value do
      n when is_number(n) ->
        n

      value when is_binary(value) ->
        case Float.parse(value) do
          {parsed, ""} -> parsed
          {parsed, _rest} -> parsed
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp encode_value(_control, value), do: value

  @spec truthy?(Types.wire_input()) :: boolean()
  defp truthy?(values) when is_list(values), do: Enum.any?(values, &truthy?/1)
  defp truthy?(value) when value in [true, "true", "True", "on", "1", 1], do: true
  defp truthy?(_value), do: false

  @spec protocol_events(map(), map()) :: [map()]
  defp protocol_events(field, values) when is_map(field) and is_map(values) do
    control = Map.get(field, "control", %{})
    constructor = Map.get(control, "send_to_watch")
    id = Map.get(field, "id")

    with true <- is_binary(constructor) and constructor != "",
         true <- is_binary(id) and id != "",
         value <- Map.get(values, id),
         {:ok, arg_label, arg_value} <- protocol_arg(control, value) do
      message = String.trim("#{constructor} #{arg_label}")

      ProtocolEvents.tx_rx_events("companion", "watch", message, "configuration", %{
        "ctor" => constructor,
        "args" => [arg_value]
      })
    else
      _ -> []
    end
  end

  defp protocol_events(_field, _values), do: []

  @spec protocol_arg(map(), Types.wire_input()) ::
          {:ok, String.t(), Types.protocol_wire_arg()} | :error
  defp protocol_arg(%{"type" => "toggle"}, value) do
    bool = truthy?(value)
    {:ok, if(bool, do: "True", else: "False"), bool}
  end

  defp protocol_arg(%{"type" => type}, value) when type in ["number", "slider"] do
    int_value =
      case value do
        n when is_integer(n) ->
          n

        n when is_float(n) ->
          round(n)

        value when is_binary(value) ->
          case Float.parse(value) do
            {parsed, _rest} -> round(parsed)
            :error -> 0
          end

        _ ->
          0
      end

    {:ok, Integer.to_string(int_value), int_value}
  end

  defp protocol_arg(%{"type" => "choice", "options" => options}, value) when is_list(options) do
    case Enum.find(options, &(Map.get(&1, "value") == value)) do
      %{"constructor" => constructor} when is_binary(constructor) and constructor != "" ->
        {:ok, constructor, %{"ctor" => constructor, "args" => []}}

      _ ->
        :error
    end
  end

  defp protocol_arg(_control, _value), do: :error
end
