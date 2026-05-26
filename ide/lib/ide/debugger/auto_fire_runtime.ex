defmodule Ide.Debugger.AutoFireRuntime do
  @moduledoc false

  alias Ide.Debugger.SubscriptionActivation
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:trigger_candidates) =>
            (Types.runtime_state(), Types.surface_target() -> [Types.trigger_candidate()]),
          required(:trigger_message) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t() | nil -> String.t()),
          required(:apply_step) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:subscription_row_enabled?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:auto_fire_row_enabled?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:simulator_now) =>
            (Types.runtime_state(), Types.surface_target() -> NaiveDateTime.t()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          optional(:default_interval_ms) => pos_integer()
        }

  @default_interval_ms 1_000

  @spec apply_fire(Types.runtime_state(), [:watch | :companion | :phone], apply_ctx()) ::
          Types.runtime_state()
  def apply_fire(state, targets, ctx)
      when is_map(state) and is_list(targets) and is_map(ctx) do
    if Map.get(state, :running, false) do
      Enum.reduce(targets, state, fn target, acc ->
        now = ctx.simulator_now.(acc, target)
        {rows, acc} = subscription_candidates(acc, target, now, ctx)

        rows
        |> Enum.reduce(acc, fn %{message: message, trigger: trigger}, row_acc ->
          resolved_message = ctx.trigger_message.(row_acc, target, trigger, message)

          ctx.apply_step.(
            row_acc,
            target,
            resolved_message,
            "subscription_auto_fire",
            trigger
          )
        end)
        |> put_clock(target, now, ctx)
      end)
    else
      state
    end
  end

  @spec subscription_candidates(
          Types.runtime_state(),
          Types.surface_target(),
          NaiveDateTime.t(),
          apply_ctx()
        ) :: {[map()], Types.runtime_state()}
  def subscription_candidates(state, target, %NaiveDateTime{} = now, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    rows =
      state
      |> ctx.trigger_candidates.(target)
      |> Enum.filter(fn row ->
        Map.get(row, :source) == "subscription" and is_binary(Map.get(row, :message)) and
          Map.get(row, :message) != "" and is_binary(Map.get(row, :trigger)) and
          Map.get(row, :trigger) != "" and ctx.subscription_row_enabled?.(state, target, row) and
          ctx.auto_fire_row_enabled?.(state, target, row) and
          SubscriptionActivation.model_active?(state, target, row)
      end)

    {Enum.filter(rows, &subscription_due?(state, target, &1, now, ctx)), state}
  end

  def subscription_candidates(state, _target, _now, _ctx), do: {[], state}

  @spec subscription_due?(
          Types.runtime_state(),
          Types.surface_target(),
          map(),
          NaiveDateTime.t(),
          apply_ctx()
        ) :: boolean()
  def subscription_due?(state, target, row, %NaiveDateTime{} = now, ctx)
      when is_map(state) and is_map(row) and is_map(ctx) do
    trigger =
      row
      |> Map.get(:trigger)
      |> to_string()
      |> String.downcase()

    clock = clock_for_target(state, target, ctx)

    cond do
      SubscriptionPayload.frame_subscription_trigger?(trigger) ->
        true

      contains_any?(trigger, ["on_second_change", "onsecondchange", "second"]) ->
        Map.get(clock, "second") != now.second

      contains_any?(trigger, ["on_minute_change", "onminutechange", "minute"]) ->
        Map.get(clock, "minute") != now.minute

      contains_any?(trigger, ["on_hour_change", "onhourchange", "hour"]) ->
        Map.get(clock, "hour") != now.hour

      contains_any?(trigger, ["on_day_change", "ondaychange", "day"]) ->
        Map.get(clock, "day") != now.day

      contains_any?(trigger, ["on_month_change", "onmonthchange", "month"]) ->
        Map.get(clock, "month") != now.month

      contains_any?(trigger, ["on_year_change", "onyearchange", "year"]) ->
        Map.get(clock, "year") != now.year

      true ->
        false
    end
  end

  def subscription_due?(_state, _target, _row, _now, _ctx), do: false

  @spec clock_for_target(Types.runtime_state(), Types.surface_target(), apply_ctx()) :: map()
  def clock_for_target(state, target, ctx) when is_map(state) and is_map(ctx) do
    state
    |> Map.get(:auto_fire_clock, %{})
    |> Map.get(ctx.source_root_for_target.(target), %{})
  end

  @spec put_clock(Types.runtime_state(), Types.surface_target(), NaiveDateTime.t(), apply_ctx()) ::
          Types.runtime_state()
  def put_clock(state, target, %NaiveDateTime{} = now, ctx) when is_map(state) and is_map(ctx) do
    clock =
      state
      |> Map.get(:auto_fire_clock, %{})
      |> Map.put(ctx.source_root_for_target.(target), %{
        "year" => now.year,
        "month" => now.month,
        "day" => now.day,
        "hour" => now.hour,
        "minute" => now.minute,
        "second" => now.second
      })

    Map.put(state, :auto_fire_clock, clock)
  end

  @spec initialize_clocks(Types.runtime_state(), [:watch | :companion | :phone], apply_ctx()) ::
          Types.runtime_state()
  def initialize_clocks(state, targets, ctx) when is_map(state) and is_list(targets) and is_map(ctx) do
    now = NaiveDateTime.local_now()
    Enum.reduce(targets, state, &put_clock(&2, &1, now, ctx))
  end

  @spec worker_interval_ms(Types.runtime_state(), [:watch | :companion | :phone], [map()], apply_ctx()) ::
          pos_integer()
  def worker_interval_ms(state, targets, subscriptions, ctx)
      when is_map(state) and is_list(targets) and is_list(subscriptions) and is_map(ctx) do
    default_ms = Map.get(ctx, :default_interval_ms, @default_interval_ms)

    targets
    |> Enum.flat_map(&ctx.trigger_candidates.(state, &1))
    |> Enum.filter(&row_selected?(&1, subscriptions))
    |> Enum.map(&(Map.get(&1, :interval_ms) || Map.get(&1, "interval_ms")))
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> default_ms
      intervals -> intervals |> Enum.min() |> TriggerCandidates.clamp_auto_fire_interval_ms()
    end
  end

  def worker_interval_ms(_state, _targets, _subscriptions, ctx) when is_map(ctx) do
    Map.get(ctx, :default_interval_ms, @default_interval_ms)
  end

  @spec row_selected?(map(), [map()]) :: boolean()
  def row_selected?(row, subscriptions) when is_map(row) and is_list(subscriptions) do
    row_target = Map.get(row, :target) || Map.get(row, "target")
    row_trigger = Map.get(row, :trigger) || Map.get(row, "trigger")

    Enum.any?(subscriptions, fn sub ->
      sub_target = Map.get(sub, "target") || Map.get(sub, :target)
      sub_trigger = Map.get(sub, "trigger") || Map.get(sub, :trigger)

      sub_target == row_target and (sub_trigger == "*" or sub_trigger == row_trigger)
    end)
  end

  def row_selected?(_row, _subscriptions), do: false

  @spec subscription_row_enabled?(
          Types.runtime_state(),
          Types.surface_target(),
          map(),
          (Types.surface_target() -> String.t())
        ) :: boolean()
  def subscription_row_enabled?(state, target, row, source_root_for_target)
      when is_map(state) and is_map(row) and is_function(source_root_for_target, 1) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")

    not SubscriptionAutoFireState.subscription_trigger_disabled?(
      state,
      target,
      trigger,
      source_root_for_target
    )
  end

  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end
end
