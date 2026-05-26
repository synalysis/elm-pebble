defmodule Ide.Debugger.SubscriptionTriggerWire do
  @moduledoc false

  alias Ide.Debugger.CompanionSubscriptionTrigger
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @opaque_gateway_triggers ~w(phonetowatch watchtophone)

  @spec constructor_message(Types.wire_input()) :: String.t() | nil
  def constructor_message(message) when is_binary(message) do
    trimmed = String.trim(message)
    if trimmed == "", do: nil, else: trimmed
  end

  def constructor_message(_message), do: nil

  @spec opaque_gateway_trigger?(String.t()) :: boolean()
  def opaque_gateway_trigger?(trigger) when is_binary(trigger) do
    normalized =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    Enum.any?(@opaque_gateway_triggers, &String.contains?(normalized, &1))
  end

  def opaque_gateway_trigger?(_trigger), do: false

  @spec debugger_simulated_payload_trigger?(String.t()) :: boolean()
  def debugger_simulated_payload_trigger?(trigger) when is_binary(trigger) do
    normalized = String.downcase(trigger)

    contains_any?(normalized, ["on_minute_change", "onminutechange"]) or
      contains_any?(normalized, ["on_hour_change", "onhourchange"]) or
      contains_any?(normalized, ["on_day_change", "ondaychange"]) or
      contains_any?(normalized, ["on_month_change", "onmonthchange"]) or
      contains_any?(normalized, ["on_year_change", "onyearchange"]) or
      contains_any?(normalized, ["on_battery_change", "onbatterychange"]) or
      contains_any?(normalized, ["on_connection_change", "onconnectionchange"]) or
      contains_any?(normalized, ["on_second_change", "onsecondchange"]) or
      contains_any?(normalized, ["on_compass_change", "oncompasschange"]) or
      contains_any?(normalized, ["on_app_focus_change", "onappfocuschange"]) or
      contains_any?(normalized, ["on_unobstructed_will_change", "onunobstructedwillchange"]) or
      contains_any?(normalized, ["on_unobstructed_changing", "onunobstructedchanging"]) or
      contains_any?(normalized, ["on_unobstructed_did_change", "onunobstructeddidchange"]) or
      contains_any?(normalized, ["on_dictation_status", "ondictationstatus"]) or
      contains_any?(normalized, ["on_dictation_result", "ondictationresult"])
  end

  def debugger_simulated_payload_trigger?(_trigger), do: false

  @spec message_value(String.t(), Types.subscription_payload()) :: Types.subscription_payload() | nil
  def message_value(message, %{} = value) when is_binary(message) do
    cond do
      Map.has_key?(value, "ctor") or Map.has_key?(value, :ctor) ->
        value

      true ->
        constructor =
          message
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()
          |> to_string()

        if constructor == "" do
          value
        else
          %{"ctor" => constructor, "args" => [value]}
        end
    end
  end

  def message_value(_message, _value), do: nil

  @type injection_modal_ctx :: %{
          required(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect() | map()),
          required(:normalize_target) => (String.t() -> Types.surface_target())
        }

  @spec injection_modal_supported?(Types.runtime_state(), map(), injection_modal_ctx()) :: boolean()
  def injection_modal_supported?(state, row, ctx)
      when is_map(state) and is_map(row) and is_map(ctx) do
    trigger =
      TriggerCandidates.row_field(row, :trigger)
      |> to_string()
      |> String.trim()

    target_s =
      TriggerCandidates.row_field(row, :target)
      |> to_string()
      |> String.trim()

    message = TriggerCandidates.row_field(row, :message)

    cond do
      trigger == "" ->
        false

      opaque_gateway_trigger?(trigger) ->
        false

      debugger_simulated_payload_trigger?(trigger) ->
        true

      CompanionSubscriptionTrigger.companion_trigger?(trigger) ->
        true

      true ->
        case constructor_message(message) do
          nil ->
            false

          constructor ->
            target_atom = ctx.normalize_target.(target_s)

            case ctx.introspect_for.(state, target_atom) do
              %{"msg_constructor_arities" => %{} = arities} when map_size(arities) > 0 ->
                case Map.fetch(arities, constructor) do
                  {:ok, arity} when is_integer(arity) and arity >= 0 and arity <= 1 -> true
                  _ -> false
                end

              _ ->
                false
            end
        end
    end
  end

  def injection_modal_supported?(_state, _row, _ctx), do: false

  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end
end
