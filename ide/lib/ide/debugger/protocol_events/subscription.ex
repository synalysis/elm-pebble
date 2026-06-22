defmodule Ide.Debugger.ProtocolEvents.Subscription do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.Types
  alias Ide.Debugger.WireDisplay

  @protocol_subscription_wrapper_ctors ~w(FromWatch FromPhone)

  @type ctx :: ProtocolEvents.ctx()

  @spec normalize_subscription_message_value(
          Types.runtime_state(),
          Types.surface_target(),
          Types.subscription_payload(),
          ctx()
        ) :: Types.subscription_payload()
  def normalize_subscription_message_value(state, recipient, message_value, events_ctx)
      when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(message_value) and
             is_map(events_ctx) do
    normalize_subscription_message_value(
      state,
      recipient,
      message_value,
      events_ctx.surface_app_model.(state, recipient),
      events_ctx
    )
  end

  @spec normalize_subscription_message_value(
          Types.runtime_state(),
          Types.surface_target(),
          Types.subscription_payload(),
          Types.app_model(),
          ctx()
        ) :: Types.subscription_payload()
  def normalize_subscription_message_value(state, recipient, message_value, app_model, events_ctx)
      when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(message_value) and
             is_map(app_model) and is_map(events_ctx) do
    direction =
      case recipient do
        :watch -> :phone_to_watch
        _ -> :watch_to_phone
      end

    case Ide.Debugger.ProtocolEvents.CmdCall.protocol_schema_from_state_or_model(
           state,
           app_model,
           events_ctx
         ) do
      {:ok, schema} ->
        normalize_protocol_subscription_callback_value(schema, direction, message_value)

      _ ->
        message_value
    end
  end

  def normalize_subscription_message_value(
        _state,
        _recipient,
        message_value,
        _app_model,
        _events_ctx
      ),
      do: message_value

  @spec parenthesize_elm_arg(String.t()) :: String.t()
  def parenthesize_elm_arg(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> trimmed
      String.starts_with?(trimmed, "(") -> trimmed
      String.contains?(trimmed, " ") -> "(" <> trimmed <> ")"
      true -> trimmed
    end
  end

  @spec normalize_protocol_subscription_callback_value(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          Types.subscription_payload()
        ) :: Types.subscription_payload()
  defp normalize_protocol_subscription_callback_value(
         schema,
         direction,
         %{"ctor" => callback, "args" => [inner | _]} = wrapped
       )
       when is_binary(callback) and is_map(schema) and
              direction in [:watch_to_phone, :phone_to_watch] do
    normalized_inner = normalize_protocol_subscription_payload(schema, direction, inner)

    if normalized_inner == inner do
      wrapped
    else
      %{"ctor" => callback, "args" => [normalized_inner]}
    end
  end

  defp normalize_protocol_subscription_callback_value(_schema, _direction, message_value),
    do: message_value

  @spec normalize_protocol_subscription_payload(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          Types.subscription_payload()
        ) :: Types.subscription_payload()
  defp normalize_protocol_subscription_payload(
         schema,
         direction,
         %{"ctor" => "Ok", "args" => [inner | _]} = value
       )
       when is_map(schema) and is_map(inner) do
    normalized_inner = normalize_protocol_subscription_payload(schema, direction, inner)

    if normalized_inner == inner do
      value
    else
      %{"ctor" => "Ok", "args" => [normalized_inner]}
    end
  end

  defp normalize_protocol_subscription_payload(schema, direction, inner) when is_map(inner) do
    ctor = Ide.Debugger.ProtocolEvents.CmdCall.protocol_message_ctor(inner) || ""

    case Ide.Debugger.ProtocolEvents.CmdCall.normalize_protocol_message_value_from_schema(
           schema,
           direction,
           inner,
           ctor
         ) do
      {_message, normalized_inner} -> normalized_inner
      :error -> inner
    end
  end

  defp normalize_protocol_subscription_payload(_schema, _direction, value), do: value

  @spec protocol_message_display(String.t(), [Types.protocol_wire_arg()]) :: String.t()
  defp protocol_message_display(ctor, args) when is_binary(ctor) and is_list(args) do
    case args do
      [] -> ctor
      _ -> ctor <> " " <> Enum.map_join(args, " ", &protocol_arg_display/1)
    end
  end

  @spec inbound_display_message(String.t(), Types.subscription_payload() | nil) :: String.t()
  def inbound_display_message(message, message_value) when is_binary(message) do
    case protocol_wire_message_display(message_value) do
      wire when is_binary(wire) and wire != "" -> wire
      _ -> message
    end
  end

  @spec protocol_wire_message_display(Types.subscription_payload() | nil) :: String.t() | nil
  defp protocol_wire_message_display(message_value) when is_map(message_value) do
    case protocol_wire_message_value(message_value) do
      %{"ctor" => ctor, "args" => args} when is_binary(ctor) and ctor != "" ->
        protocol_message_display(ctor, List.wrap(args))

      _ ->
        nil
    end
  end

  defp protocol_wire_message_display(_message_value), do: nil

  @spec protocol_wire_message_value(Types.subscription_payload()) ::
          Types.protocol_ctor_value() | nil
  defp protocol_wire_message_value(%{"ctor" => ctor, "args" => args})
       when ctor in @protocol_subscription_wrapper_ctors and is_list(args) do
    case List.wrap(args) do
      [%{"ctor" => result, "args" => [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        protocol_wire_message_value(inner)

      [%{ctor: result, args: [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        protocol_wire_message_value(inner)

      _ ->
        nil
    end
  end

  defp protocol_wire_message_value(%{"ctor" => _ctor, "args" => _args} = value), do: value
  defp protocol_wire_message_value(_value), do: nil

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

  defp protocol_arg_display(value), do: WireDisplay.format(value)
end
