defmodule Ide.Debugger.SubscriptionCallLookup do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @spec find_by_target_suffixes(Types.elm_introspect(), [String.t()]) ::
          Types.cmd_call() | nil
  def find_by_target_suffixes(ei, target_suffixes)
      when is_map(ei) and is_list(target_suffixes) do
    IntrospectAccess.cmd_calls(ei, "subscription_calls")
    |> Enum.find(&CmdCall.subscription_call_matches?(&1, target_suffixes))
  end

  def find_by_target_suffixes(_ei, _target_suffixes), do: nil

  @spec find_by_trigger(Types.elm_introspect(), String.t()) :: Types.cmd_call() | nil
  def find_by_trigger(ei, trigger) when is_map(ei) and is_binary(trigger) do
    IntrospectAccess.cmd_calls(ei, "subscription_calls")
    |> Enum.find(fn op ->
      TriggerCandidates.subscription_trigger_for_call(op) == trigger
    end)
  end

  def find_by_trigger(_ei, _trigger), do: nil
end
