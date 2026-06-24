defmodule Ide.Debugger.TickMessageResolution do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.Types

  @type resolve_ctx :: %{
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() ->
                                          Types.elm_introspect()),
          required(:attach_payload) => (Types.runtime_state(),
                                        Types.surface_target(),
                                        String.t(),
                                        String.t() ->
                                          String.t())
        }

  @spec message_for_surface(Types.runtime_state(), Types.surface_target(), resolve_ctx()) ::
          String.t()
  def message_for_surface(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    case RuntimeActiveSubscriptions.tick_candidate(state, target) do
      %{message: message, trigger: trigger} ->
        ctx.attach_payload.(state, target, message, trigger)

      nil ->
        message_for_surface_from_introspect(state, target, ctx)
    end
  end

  def message_for_surface(_state, _target, _ctx), do: "Tick"

  @spec message_for_surface_from_introspect(
          Types.runtime_state(),
          Types.surface_target(),
          resolve_ctx()
        ) :: String.t()
  defp message_for_surface_from_introspect(state, target, ctx)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    ei = ctx.introspect_for.(state, target)
    msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
    update_branches = IntrospectAccess.list(ei, "update_case_branches")
    subscription_ops = IntrospectAccess.list(ei, "subscription_ops")
    known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches

    cond do
      known_messages == [] ->
        "Tick"

      subscription_ops != [] ->
        {message, matched_op} =
          pick_subscription_message(known_messages, subscription_ops, "tick")

        ctx.attach_payload.(state, target, message, matched_op || "tick")

      true ->
        Enum.find(known_messages, "Tick", &tickish_message?/1)
    end
  end

  @spec pick_subscription_message([String.t()], [String.t()], String.t()) ::
          {String.t(), String.t() | nil}
  def pick_subscription_message(known_messages, subscription_ops, trigger)
      when is_list(known_messages) and is_list(subscription_ops) and is_binary(trigger) do
    ranked =
      known_messages
      |> Enum.with_index()
      |> Enum.flat_map(fn {message, index} ->
        message_tokens = normalized_event_tokens(message)

        subscription_ops
        |> Enum.filter(&subscription_op_matches_message?(&1, message, message_tokens))
        |> Enum.map(fn op ->
          {subscription_match_priority(op, trigger), index, message, op}
        end)
      end)
      |> Enum.sort()

    case ranked do
      [{_priority, _index, message, op} | _] -> {message, op}
      _ -> {List.first(known_messages) || "Tick", nil}
    end
  end

  @spec subscription_match_priority(String.t(), String.t()) :: 0 | 1 | 2 | 3 | 4
  def subscription_match_priority(op, trigger) when is_binary(op) and is_binary(trigger) do
    op_down = String.downcase(op)
    trigger_down = String.downcase(trigger)

    if contains_any?(trigger_down, ["tick", "time", "clock"]) do
      cond do
        contains_any?(op_down, ["second"]) -> 0
        contains_any?(op_down, ["minute"]) -> 1
        contains_any?(op_down, ["tick", "time", "clock"]) -> 2
        contains_any?(op_down, ["hour"]) -> 3
        true -> 4
      end
    else
      0
    end
  end

  @spec tickish_message?(String.t()) :: boolean()
  def tickish_message?(message) when is_binary(message) do
    contains_any?(String.downcase(message), ["tick", "time", "clock", "second", "minute", "hour"])
  end

  @spec subscription_op_matches_message?(String.t(), String.t(), [String.t()]) :: boolean()
  def subscription_op_matches_message?(op, message, message_tokens)
      when is_binary(op) and is_binary(message) and is_list(message_tokens) do
    op_down = String.downcase(op)
    message_down = String.downcase(message)
    op_tokens = normalized_event_tokens(op)

    direct_match? =
      String.contains?(op_down, message_down) or String.contains?(message_down, op_down)

    token_match? =
      message_tokens
      |> Enum.reject(&(&1 in ["on", "event", "change", "changed", "subscription"]))
      |> Enum.any?(&(&1 in op_tokens))

    direct_match? or token_match?
  end

  def subscription_op_matches_message?(_op, _message, _message_tokens), do: false

  @spec normalized_event_tokens(String.t()) :: [String.t()]
  def normalized_event_tokens(text) when is_binary(text) do
    text
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.replace(~r/[^A-Za-z0-9]+/, " ")
    |> String.downcase()
    |> String.split(" ", trim: true)
  end

  def normalized_event_tokens(_text), do: []

  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end
end
