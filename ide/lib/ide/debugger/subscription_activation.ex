defmodule Ide.Debugger.SubscriptionActivation do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.SubscriptionGuards
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.TriggerCandidate

  @spec guards_for_row(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: SubscriptionGuards.guards()
  def guards_for_row(state, target, row)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    ei = state |> Surface.from_state(target) |> Surface.introspect()
    calls = IntrospectAccess.cmd_calls(ei, "subscription_calls")

    row_trigger =
      row
      |> TriggerCandidates.row_field(:trigger)
      |> to_string()
      |> TriggerCandidates.normalize_trigger_id()

    row_message =
      row
      |> TriggerCandidates.row_field(:message)
      |> case do
        message when is_binary(message) -> String.trim(message)
        _ -> ""
      end

    matching =
      Enum.filter(calls, fn call ->
        call_trigger =
          call
          |> TriggerCandidates.subscription_trigger_for_call()
          |> to_string()
          |> TriggerCandidates.normalize_trigger_id()

        call_message = Map.get(call, "callback_constructor") |> to_string()

        call_trigger == row_trigger and
          (row_message == "" or call_message == "" or call_message == row_message)
      end)

    case matching do
      [%{"activation_guards" => guards} | _] when is_list(guards) and guards != [] ->
        guards

      _ ->
        :always
    end
  end

  def guards_for_row(_state, _target, _row), do: :always

  @spec model_active?(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerCandidate.wire_map()
        ) :: boolean()
  def model_active?(state, target, row)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(row) do
    guards = guards_for_row(state, target, row)
    guards == :always or SubscriptionGuards.satisfied?(state, target, guards)
  end

  def model_active?(_state, _target, _row), do: true
end
