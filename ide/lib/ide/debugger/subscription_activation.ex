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

      companion_catalog_active?(state, target, row) ->
        true

      true ->
        false
    end
  end

  def model_active?(_state, _target, _row), do: true

  @spec companion_catalog_active?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  defp companion_catalog_active?(state, target, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    trigger = TriggerCandidates.row_field(row, :trigger) |> to_string()
    message = row_message(row)

    with true <- CompanionSubscriptionTrigger.companion_trigger?(trigger),
         %{} = ei <- Surface.from_state(state, target) |> Surface.introspect() do
      ei
      |> IntrospectAccess.cmd_calls("subscription_calls")
      |> Enum.any?(fn call ->
        catalog_trigger = TriggerCandidates.subscription_trigger_for_call(call) |> to_string()
        catalog_message = Map.get(call, "callback_constructor") || ""

        RuntimeActiveSubscriptions.triggers_equivalent?(trigger, catalog_trigger) and
          messages_compatible?(message, catalog_message)
      end)
    else
      _ -> false
    end
  end

  defp companion_catalog_active?(_state, _target, _row), do: false

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
