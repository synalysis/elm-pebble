defmodule Ide.Debugger.SubscriptionAutoFireState do
  @moduledoc false

  alias Ide.Debugger.Types

  @type subscription_row :: %{required(String.t()) => String.t()}

  @spec disabled_subscriptions(Types.runtime_state()) :: [subscription_row()]
  def disabled_subscriptions(state) when is_map(state) do
    case Map.get(state, :disabled_subscriptions) || Map.get(state, "disabled_subscriptions") do
      xs when is_list(xs) -> Enum.filter(xs, &valid_disabled_subscription?/1)
      _ -> []
    end
  end

  @spec update_disabled_subscription(
          [subscription_row()],
          Types.surface_target(),
          String.t(),
          boolean(),
          (Types.surface_target() -> String.t())
        ) :: [subscription_row()]
  def update_disabled_subscription(disabled_subscriptions, target, trigger, enabled?, source_root_for_target)
      when is_list(disabled_subscriptions) and is_binary(trigger) and is_function(source_root_for_target, 1) do
    source_root = source_root_for_target.(target)
    trigger = String.trim(to_string(trigger))

    disabled_subscriptions =
      Enum.reject(disabled_subscriptions, fn row ->
        Map.get(row, "target") == source_root and Map.get(row, "trigger") == trigger
      end)

    disabled_subscriptions =
      if enabled? do
        disabled_subscriptions
      else
        [%{"target" => source_root, "trigger" => trigger} | disabled_subscriptions]
      end

    disabled_subscriptions
    |> Enum.filter(&valid_disabled_subscription?/1)
    |> Enum.uniq_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
    |> Enum.sort_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
  end

  @spec update_auto_fire_subscriptions(
          [subscription_row()],
          Types.surface_target(),
          String.t(),
          boolean(),
          (Types.surface_target() -> String.t())
        ) :: [subscription_row()]
  def update_auto_fire_subscriptions(subscriptions, target, trigger, enabled?, source_root_for_target)
      when is_list(subscriptions) and is_binary(trigger) and is_function(source_root_for_target, 1) do
    source_root = source_root_for_target.(target)
    trigger = String.trim(to_string(trigger))

    subscriptions =
      Enum.reject(subscriptions, fn row ->
        Map.get(row, "target") == source_root and Map.get(row, "trigger") == trigger
      end)

    subscriptions =
      if enabled? do
        [%{"target" => source_root, "trigger" => trigger} | subscriptions]
      else
        subscriptions
      end

    subscriptions
    |> Enum.filter(&valid_auto_fire_subscription?/1)
    |> Enum.uniq_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
    |> Enum.sort_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
  end

  @spec auto_tick_subscriptions(Types.runtime_state(), (Types.surface_target() -> String.t())) ::
          [subscription_row()]
  def auto_tick_subscriptions(state, source_root_for_target)
      when is_map(state) and is_function(source_root_for_target, 1) do
    auto_tick = Map.get(state, :auto_tick, %{})

    case Map.get(auto_tick, :subscriptions) do
      xs when is_list(xs) ->
        Enum.filter(xs, &valid_auto_fire_subscription?/1)

      _ ->
        state
        |> auto_tick_targets()
        |> Enum.map(&%{"target" => source_root_for_target.(&1), "trigger" => "*"})
    end
  end

  @spec auto_tick_targets(Types.runtime_state()) :: [:watch | :companion | :phone]
  def auto_tick_targets(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})

    auto_tick
    |> Map.get(:targets, [])
    |> Enum.map(&normalize_target/1)
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
  end

  @spec auto_fire_targets_from_subscriptions([subscription_row()], (String.t() -> Types.surface_target())) ::
          [:watch | :companion | :phone]
  def auto_fire_targets_from_subscriptions(subscriptions, normalize_target)
      when is_list(subscriptions) and is_function(normalize_target, 1) do
    subscriptions
    |> Enum.map(&(Map.get(&1, "target") || Map.get(&1, :target)))
    |> Enum.map(normalize_target)
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
  end

  @spec subscription_trigger_disabled?(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          (Types.surface_target() -> String.t())
        ) :: boolean()
  def subscription_trigger_disabled?(state, target, trigger, source_root_for_target)
      when is_map(state) and is_binary(trigger) and is_function(source_root_for_target, 1) do
    source_root = source_root_for_target.(target)

    Enum.any?(disabled_subscriptions(state), fn row ->
      Map.get(row, "target") == source_root and Map.get(row, "trigger") == trigger
    end)
  end

  @spec auto_fire_subscription_enabled?(
          Types.runtime_state(),
          Types.surface_target(),
          map(),
          (Types.surface_target() -> String.t())
        ) :: boolean()
  def auto_fire_subscription_enabled?(state, target, row, source_root_for_target)
      when is_map(state) and is_map(row) and is_function(source_root_for_target, 1) do
    subscriptions = auto_tick_subscriptions(state, source_root_for_target)
    source_root = source_root_for_target.(target)
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")

    Enum.any?(subscriptions, fn sub ->
      Map.get(sub, "target") == source_root and
        (Map.get(sub, "trigger") == "*" or Map.get(sub, "trigger") == trigger)
    end)
  end

  @spec update_auto_fire_targets(
          [:watch | :companion | :phone],
          Types.surface_target(),
          boolean()
        ) :: [:watch | :companion | :phone]
  def update_auto_fire_targets(targets, target, enabled?) when is_list(targets) do
    targets =
      if enabled? do
        [target | targets]
      else
        Enum.reject(targets, &(&1 == target))
      end

    targets
    |> Enum.filter(&(&1 in [:watch, :companion]))
    |> Enum.uniq()
    |> Enum.sort_by(fn
      :watch -> 0
      :companion -> 1
      :phone -> 2
    end)
  end

  @spec target_label([Types.surface_target()], (Types.surface_target() -> String.t())) :: String.t()
  def target_label([single], source_root_for_target), do: source_root_for_target.(single)
  def target_label(_targets, _source_root_for_target), do: "selected"

  @spec valid_auto_fire_subscription?(Types.subscription_row_input()) :: boolean()
  def valid_auto_fire_subscription?(%{"target" => target, "trigger" => trigger})
      when target in ["watch", "protocol"] and is_binary(trigger) and trigger != "",
      do: true

  def valid_auto_fire_subscription?(_), do: false

  @spec valid_disabled_subscription?(Types.subscription_row_input()) :: boolean()
  def valid_disabled_subscription?(%{"target" => target, "trigger" => trigger})
      when target in ["watch", "protocol"] and is_binary(trigger) and trigger != "",
      do: true

  def valid_disabled_subscription?(_), do: false

  defp normalize_target("watch"), do: :watch
  defp normalize_target("companion"), do: :companion
  defp normalize_target("phone"), do: :companion
  defp normalize_target(:watch), do: :watch
  defp normalize_target(:companion), do: :companion
  defp normalize_target(:phone), do: :companion
  defp normalize_target(_), do: :watch
end
