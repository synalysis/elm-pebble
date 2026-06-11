defmodule IdeWeb.WorkspaceLive.DebuggerPage.SubscriptionControls do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type trigger_row :: SupportTypes.trigger_button_row()
  @type wire_input :: SupportTypes.wire_value()

  @spec enabled?([map()], String.t(), String.t()) :: boolean()
  def enabled?(disabled_subscriptions, target, trigger)
      when is_list(disabled_subscriptions) and is_binary(target) and is_binary(trigger) do
    not Enum.any?(disabled_subscriptions, fn row ->
      row_target = Map.get(row, "target") || Map.get(row, :target)
      row_trigger = Map.get(row, "trigger") || Map.get(row, :trigger)
      row_target == auto_fire_target(target) and row_trigger == trigger
    end)
  end

  def enabled?(_disabled_subscriptions, _target, _trigger), do: true

  @spec injection_supported?(trigger_row()) :: boolean()
  def injection_supported?(%{injection_supported?: true}), do: true
  def injection_supported?(%{"injection_supported?" => true}), do: true
  def injection_supported?(_row), do: false

  @spec button_title(trigger_row()) :: String.t()
  def button_title(row) when is_map(row) do
    model_active? = Map.get(row, :model_active?, Map.get(row, "model_active?", true)) == true

    cond do
      not model_active? ->
        "Inactive for the current model state"

      injection_supported?(row) ->
        "Fire this subscribed event"

      true ->
        "This subscribed event needs a payload shape the debugger form cannot represent."
    end
  end

  @spec auto_fire_enabled?([map()], String.t(), String.t()) :: boolean()
  def auto_fire_enabled?(auto_fire_subscriptions, target, trigger)
      when is_list(auto_fire_subscriptions) and is_binary(target) and is_binary(trigger) do
    Enum.any?(auto_fire_subscriptions, fn row ->
      row_target = Map.get(row, "target") || Map.get(row, :target)
      row_trigger = Map.get(row, "trigger") || Map.get(row, :trigger)

      row_target == auto_fire_target(target) and
        (row_trigger == "*" or row_trigger == trigger)
    end)
  end

  def auto_fire_enabled?(_auto_fire_subscriptions, _target, _trigger), do: false

  @spec auto_fire_toggle_visible?([map()], String.t(), trigger_row()) :: boolean()
  def auto_fire_toggle_visible?(auto_fire_subscriptions, target, row)
      when is_list(auto_fire_subscriptions) and is_binary(target) and is_map(row) do
    trigger = to_string(Map.get(row, :trigger) || Map.get(row, "trigger") || "")
    interval_ms = Map.get(row, :interval_ms) || Map.get(row, "interval_ms")

    interval_auto? = is_integer(interval_ms) and interval_ms > 0
    recurring_event? = recurring_auto_fire_trigger?(trigger)

    interval_auto? or recurring_event? or
      auto_fire_enabled?(auto_fire_subscriptions, target, trigger)
  end

  def auto_fire_toggle_visible?(_auto_fire_subscriptions, _target, _row), do: false

  @spec auto_fire_target(wire_input()) :: String.t()
  def auto_fire_target("protocol"), do: "protocol"
  def auto_fire_target("companion"), do: "phone"
  def auto_fire_target(_target), do: "watch"

  @spec recurring_auto_fire_trigger?(String.t()) :: boolean()
  defp recurring_auto_fire_trigger?(trigger) when is_binary(trigger) do
    trigger =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    String.contains?(trigger, "ontick") or
      String.contains?(trigger, "onsecondchange") or
      String.contains?(trigger, "onminutechange") or
      String.contains?(trigger, "onhourchange")
  end
end
