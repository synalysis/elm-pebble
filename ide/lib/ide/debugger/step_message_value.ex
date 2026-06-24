defmodule Ide.Debugger.StepMessageValue do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.Types

  @spec normalize(
          Types.runtime_state(),
          Types.surface_target(),
          Types.subscription_payload() | nil,
          Types.app_model(),
          (-> ProtocolEvents.ctx())
        ) :: Types.subscription_payload() | nil
  def normalize(_state, _target, nil, _model, _events_ctx), do: nil

  def normalize(state, target, message_value, model, events_ctx)
      when is_map(state) and is_map(message_value) and is_function(events_ctx, 0) do
    if explicit_subscription_inject_value?(message_value) do
      message_value
    else
      ProtocolEvents.normalize_subscription_message_value(
        state,
        target,
        message_value,
        model,
        events_ctx.()
      )
    end
  end

  def normalize(_state, _target, message_value, _model, _events_ctx), do: message_value

  @spec explicit_subscription_inject_value?(Types.subscription_payload()) :: boolean()
  defp explicit_subscription_inject_value?(%{"ctor" => _ctor, "args" => [first | _]})
       when is_map(first) do
    case Map.get(first, "ctor") do
      result when result in ["Ok", "Err"] -> true
      _ -> false
    end
  end

  defp explicit_subscription_inject_value?(%{ctor: _ctor, args: [first | _]}) when is_map(first) do
    case Map.get(first, :ctor) do
      result when result in ["Ok", "Err"] -> true
      _ -> false
    end
  end

  defp explicit_subscription_inject_value?(_value), do: false
end
