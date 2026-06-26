defmodule Ide.Debugger.SubscriptionActivation do
  @moduledoc false

  alias Ide.Debugger.CompanionSubscriptionTrigger
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.TriggerCandidate

  @spec model_active?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  def model_active?(state, target, row)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    active = RuntimeActiveSubscriptions.for_surface(state, target)

    cond do
      not RuntimeActiveSubscriptions.present?(state, target) ->
        true

      RuntimeActiveSubscriptions.row_active?(row, active) ->
        true

      companion_subscription_active?(target, row) ->
        true

      catalog_subscription_active?(state, target, row) ->
        true

      active == [] and fallback_catalog_trigger?(state, target, row) ->
        true

      true ->
        false
    end
  end

  def model_active?(_state, _target, _row), do: true

  @spec catalog_subscription_active?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  defp catalog_subscription_active?(state, target, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    active = RuntimeActiveSubscriptions.for_surface(state, target)

    if active == [] do
      catalog_subscription_row?(state, target, row)
    else
      false
    end
  end

  defp catalog_subscription_active?(_state, _target, _row), do: false

  @spec companion_subscription_active?(Types.surface_target(), TriggerCandidate.wire_map()) ::
          boolean()
  defp companion_subscription_active?(target, row)
       when target in [:companion, :phone] and is_map(row) do
    row
    |> TriggerCandidates.row_field(:trigger)
    |> to_string()
    |> CompanionSubscriptionTrigger.companion_trigger?()
  end

  defp companion_subscription_active?(_target, _row), do: false

  @spec catalog_subscription_row?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  defp catalog_subscription_row?(state, target, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    trigger = TriggerCandidates.row_field(row, :trigger) |> to_string()
    message = row_message(row)

    with %{} = ei <- Surface.from_state(state, target) |> Surface.introspect() do
      ei
      |> IntrospectAccess.cmd_calls("subscription_calls")
      |> Enum.any?(fn call ->
        catalog_trigger = TriggerCandidates.subscription_trigger_for_call(call) |> to_string()
        catalog_message = Map.get(call, "callback_constructor") || ""
        guards = Map.get(call, "activation_guards") || Map.get(call, :activation_guards) || []

        guards == [] and
          RuntimeActiveSubscriptions.triggers_equivalent?(trigger, catalog_trigger) and
          messages_compatible?(message, catalog_message)
      end)
    else
      _ -> false
    end
  end

  defp catalog_subscription_row?(_state, _target, _row), do: false

  @spec fallback_catalog_trigger?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  defp fallback_catalog_trigger?(state, target, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    trigger = TriggerCandidates.row_field(row, :trigger) |> to_string()

    if TriggerCandidates.fallback_catalog_trigger?(trigger) do
      ei = Surface.from_state(state, target) |> Surface.introspect() || %{}

      catalog_triggers =
        ei
        |> IntrospectAccess.cmd_calls("subscription_calls")
        |> Enum.map(&TriggerCandidates.subscription_trigger_for_call/1)
        |> Enum.map(&to_string/1)

      not Enum.any?(catalog_triggers, fn catalog_trigger ->
        RuntimeActiveSubscriptions.triggers_equivalent?(trigger, catalog_trigger)
      end)
    else
      false
    end
  end

  defp fallback_catalog_trigger?(_state, _target, _row), do: false

  @spec row_message(TriggerCandidate.wire_map()) :: String.t()
  defp row_message(row) do
    row
    |> TriggerCandidates.row_field(:message)
    |> case do
      message when is_binary(message) -> String.trim(message)
      _ -> ""
    end
  end

  @spec messages_compatible?(String.t(), String.t()) :: boolean()
  defp messages_compatible?("", _), do: true
  defp messages_compatible?(_, ""), do: true

  defp messages_compatible?(left, right) when is_binary(left) and is_binary(right) do
    left == right or
      RuntimeModelMessages.wire_constructor(left) == RuntimeModelMessages.wire_constructor(right)
  end

  defp messages_compatible?(_, _), do: false
end
