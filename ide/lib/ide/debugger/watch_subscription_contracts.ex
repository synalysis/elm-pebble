defmodule Ide.Debugger.WatchSubscriptionContracts do
  @moduledoc false

  alias Ide.Debugger.SubscriptionCallLookup
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  defmodule ApiSuffixes do
    @moduledoc false

    @spec suffixes(String.t(), [String.t()]) :: [String.t()]
    def suffixes(module, ops) when is_binary(module) and is_list(ops) do
      Enum.flat_map(ops, fn op ->
        [
          ".Pebble.#{module}.#{op}",
          ".#{module}.#{op}",
          "#{module}.#{op}"
        ]
      end)
    end
  end

  @speaker_finished_contract %{
    id: :speaker_finished,
    target_suffixes:
      ApiSuffixes.suffixes("Speaker", ["onFinished"]) ++
        [
          "Elm.Kernel.PebbleWatch.onSpeakerFinished",
          ".Elm.Kernel.PebbleWatch.onSpeakerFinished"
        ],
    simulator_arg_types: %{
      "Speaker.FinishReason" => "FinishedDone"
    }
  }

  @contracts [@speaker_finished_contract]

  @spec contracts() :: [Types.watch_subscription_contract()]
  def contracts, do: @contracts

  @spec speaker_finished() :: Types.watch_subscription_contract()
  def speaker_finished, do: @speaker_finished_contract

  @spec find_subscription_call(Types.elm_introspect(), Types.watch_subscription_contract()) ::
          Types.cmd_call() | nil
  def find_subscription_call(ei, contract) when is_map(ei) and is_map(contract) do
    SubscriptionCallLookup.find_by_target_suffixes(ei, Map.get(contract, :target_suffixes, []))
  end

  @spec trigger_for_contract(Types.elm_introspect(), Types.watch_subscription_contract()) ::
          String.t() | nil
  def trigger_for_contract(ei, contract) when is_map(ei) and is_map(contract) do
    case find_subscription_call(ei, contract) do
      nil -> nil
      op -> TriggerCandidates.subscription_trigger_for_call(op)
    end
  end

  @spec message_for_contract(Types.elm_introspect(), Types.watch_subscription_contract()) ::
          String.t() | nil
  def message_for_contract(ei, contract) when is_map(ei) and is_map(contract) do
    case find_subscription_call(ei, contract) do
      %{"callback_constructor" => message} when is_binary(message) and message != "" -> message
      _ -> nil
    end
  end

  @spec simulator_payload_suffix(
          Types.elm_introspect(),
          String.t(),
          Types.watch_subscription_contract()
        ) :: String.t() | nil
  def simulator_payload_suffix(ei, message_ctor, contract)
      when is_map(ei) and is_binary(message_ctor) and is_map(contract) do
    with type when is_binary(type) <- msg_constructor_arg_type(ei, message_ctor),
         suffix when is_binary(suffix) and suffix != "" <-
           Map.get(Map.get(contract, :simulator_arg_types, %{}), type) do
      suffix
    else
      _ -> nil
    end
  end

  @spec simulator_payload_suffix_for_trigger(
          Types.elm_introspect(),
          String.t(),
          String.t()
        ) :: String.t() | nil
  def simulator_payload_suffix_for_trigger(ei, trigger, message_ctor)
      when is_map(ei) and is_binary(trigger) and is_binary(message_ctor) do
    case SubscriptionCallLookup.find_by_trigger(ei, trigger) do
      nil ->
        nil

      %{"callback_constructor" => ^message_ctor} ->
        case contract_for_trigger(ei, trigger) do
          nil -> nil
          contract -> simulator_payload_suffix(ei, message_ctor, contract)
        end

      _ ->
        nil
    end
  end

  def simulator_payload_suffix_for_trigger(_ei, _trigger, _message_ctor), do: nil

  @spec contract_for_trigger(Types.elm_introspect(), String.t()) ::
          Types.watch_subscription_contract() | nil
  defp contract_for_trigger(ei, trigger) when is_map(ei) and is_binary(trigger) do
    Enum.find_value(@contracts, fn contract ->
      case find_subscription_call(ei, contract) do
        nil ->
          nil

        op ->
          if TriggerCandidates.subscription_trigger_for_call(op) == trigger, do: contract, else: nil
      end
    end)
  end

  defp contract_for_trigger(_ei, _trigger), do: nil

  @spec msg_constructor_arg_type(Types.elm_introspect(), String.t()) :: String.t() | nil
  defp msg_constructor_arg_type(ei, ctor) when is_map(ei) and is_binary(ctor) do
    case Map.get(ei, "msg_constructor_arg_types") do
      types when is_map(types) -> Map.get(types, ctor)
      _ -> nil
    end
  end
end
