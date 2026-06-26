defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Live.Triggers do
  @moduledoc false
  @dialyzer {:no_return, [trigger_button_row: 2, trigger_buttons: 1, subscription_trigger_buttons: 2]}

  alias Ide.Debugger
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.WorkspaceLive.DebuggerFlow.Types, as: FlowTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type debugger_state_map :: Types.debugger_state_map()
  @type trigger_button_row :: Types.trigger_button_row()
  @type trigger_candidate :: DebuggerTypes.trigger_candidate()
  @type surface_target :: :watch | :companion

  @spec trigger_buttons(debugger_state_map()) :: [trigger_button_row()]
  def trigger_buttons(debugger_state) when is_map(debugger_state) do
    [:watch, :companion]
    |> Enum.flat_map(&Debugger.trigger_candidates(debugger_state, &1))
    |> Enum.map(&trigger_button_row(&1, debugger_state))
    |> Enum.filter(fn row ->
      is_binary(row.id) and row.id != "" and is_binary(row.trigger) and row.trigger != ""
    end)
  end

  def trigger_buttons(_), do: []

  @spec subscription_trigger_buttons(debugger_state_map(), surface_target()) ::
          [trigger_button_row()]
  def subscription_trigger_buttons(debugger_state, target)
      when is_map(debugger_state) and target in [:watch, :companion] do
    debugger_state
    |> Debugger.trigger_candidates(target)
    |> Enum.map(&trigger_button_row(&1, debugger_state))
    |> Enum.filter(fn row ->
      row.source == "subscription" and is_binary(row.id) and row.id != "" and
        is_binary(row.trigger) and row.trigger != ""
    end)
  end

  def subscription_trigger_buttons(_debugger_state, _target), do: []

  @spec auto_fire_enabled?(debugger_state_map(), surface_target()) :: boolean()
  def auto_fire_enabled?(debugger_state, target)
      when is_map(debugger_state) and target in [:watch, :companion] do
    auto_tick = Map.get(debugger_state, :auto_tick, %{})
    source_root = if target == :companion, do: "phone", else: "watch"

    Map.get(auto_tick, :enabled) == true and
      source_root in List.wrap(Map.get(auto_tick, :targets, []))
  end

  def auto_fire_enabled?(_debugger_state, _target), do: false

  @spec auto_fire_subscriptions(debugger_state_map()) :: [FlowTypes.auto_fire_subscription_row()]
  def auto_fire_subscriptions(debugger_state) when is_map(debugger_state) do
    auto_tick = Map.get(debugger_state, :auto_tick, %{})

    case Map.get(auto_tick, :subscriptions) do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  @spec disabled_subscriptions(debugger_state_map()) :: [DebuggerTypes.disabled_subscription()]
  def disabled_subscriptions(debugger_state) when is_map(debugger_state) do
    case Map.get(debugger_state, :disabled_subscriptions) ||
           Map.get(debugger_state, "disabled_subscriptions") do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  @spec trigger_button_row(trigger_candidate(), debugger_state_map()) :: trigger_button_row()
  defp trigger_button_row(row, debugger_state) when is_map(row) and is_map(debugger_state) do
    %{
      id: Map.get(row, :id) || Map.get(row, "id"),
      label: Map.get(row, :label) || Map.get(row, "label"),
      trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
      trigger_display: Map.get(row, :trigger_display) || Map.get(row, "trigger_display"),
      target: Map.get(row, :target) || Map.get(row, "target"),
      message: Map.get(row, :message) || Map.get(row, "message"),
      source: Map.get(row, :source) || Map.get(row, "source"),
      button: Map.get(row, :button) || Map.get(row, "button"),
      button_event: Map.get(row, :button_event) || Map.get(row, "button_event"),
      interval_ms: Map.get(row, :interval_ms) || Map.get(row, "interval_ms"),
      declared_interval_ms:
        Map.get(row, :declared_interval_ms) || Map.get(row, "declared_interval_ms"),
      model_active?: Map.get(row, :model_active, Map.get(row, "model_active", true)) == true,
      injection_supported?:
        Debugger.subscription_trigger_injection_modal_supported?(debugger_state, row)
    }
  end
end
