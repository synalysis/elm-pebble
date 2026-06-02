defmodule Ide.Debugger.AutoFireRuntime do
  @moduledoc false

  alias Ide.Debugger.SubscriptionActivation
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:trigger_candidates) => (Types.runtime_state(), Types.surface_target() ->
                                              [Types.trigger_candidate()]),
          required(:trigger_message) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         String.t()
                                         | nil ->
                                           String.t()),
          required(:apply_step) => (Types.runtime_state(),
                                    Types.surface_target(),
                                    String.t(),
                                    map()
                                    | nil,
                                    String.t(),
                                    String.t() ->
                                      Types.runtime_state()),
          required(:subscription_row_enabled?) => (Types.runtime_state(),
                                                   Types.surface_target(),
                                                   map() ->
                                                     boolean()),
          required(:auto_fire_row_enabled?) => (Types.runtime_state(),
                                                Types.surface_target(),
                                                map() ->
                                                  boolean()),
          required(:simulator_now) => (Types.runtime_state(), Types.surface_target() ->
                                         NaiveDateTime.t()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          optional(:apply_device_data_responses) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t() ->
                                                       Types.runtime_state()),
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
          resolved_message =
            ctx.trigger_message.(row_acc, target, trigger, message)
            |> resolved_auto_fire_message(message)

          {_step_message, message_value} =
            TimelineMessage.message_value_for_step(resolved_message)

          row_acc
          |> apply_auto_fire_step(target, resolved_message, message_value, trigger, ctx)
          |> SubscriptionPayload.advance_simulator_clock_for_auto_fire(trigger)
        end)
        |> then(fn st -> put_clock(st, target, clock_snapshot(st, target, ctx), ctx) end)
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

  defp apply_auto_fire_step(state, target, message, message_value, trigger, ctx)
       when target in [:watch, :companion, :phone] and is_map(state) and is_map(ctx) do
    before_seq = Map.get(state, :debugger_seq, 0)

    stepped =
      ctx.apply_step.(
        state,
        target,
        message,
        message_value,
        "subscription_auto_fire",
        trigger
      )

    if device_data_response_appended?(stepped, before_seq, target, ctx) do
      stepped
    else
      case Map.get(ctx, :apply_device_data_responses) do
        fun when is_function(fun, 3) -> fun.(stepped, target, message)
        _ -> stepped
      end
    end
  end

  defp device_data_response_appended?(state, before_seq, target, ctx)
       when is_map(state) and is_integer(before_seq) and target in [:watch, :companion, :phone] and
              is_map(ctx) do
    source_root = ctx.source_root_for_target.(target)

    state
    |> Map.get(:debugger_timeline, [])
    |> Enum.any?(fn
      %{seq: seq, target: ^source_root, message_source: "device_data"} when is_integer(seq) ->
        seq > before_seq

      %{"seq" => seq, "target" => ^source_root, "message_source" => "device_data"}
      when is_integer(seq) ->
        seq > before_seq

      _ ->
        false
    end)
  end

  defp device_data_response_appended?(_state, _before_seq, _target, _ctx), do: false

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

  @spec clock_for_target(Types.runtime_state(), Types.surface_target(), apply_ctx()) ::
          Types.wire_map()
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
  def initialize_clocks(state, targets, ctx)
      when is_map(state) and is_list(targets) and is_map(ctx) do
    Enum.reduce(targets, state, fn target, acc ->
      now = ctx.simulator_now.(acc, target)
      seed = clock_seed(acc, target, now, ctx)
      put_clock(acc, target, seed, ctx)
    end)
  end

  @spec clock_seed(Types.runtime_state(), Types.surface_target(), NaiveDateTime.t(), apply_ctx()) ::
          NaiveDateTime.t()
  defp clock_seed(state, target, %NaiveDateTime{} = now, ctx)
       when is_map(state) and is_map(ctx) do
    if simulated_time_for_target?(state, target) do
      NaiveDateTime.add(now, -1, :minute)
    else
      now
    end
  end

  @spec clock_snapshot(Types.runtime_state(), Types.surface_target(), apply_ctx()) ::
          NaiveDateTime.t()
  defp clock_snapshot(state, target, ctx) when is_map(state) and is_map(ctx) do
    now = ctx.simulator_now.(state, target)

    if simulated_time_for_target?(state, target) do
      NaiveDateTime.add(now, -1, :minute)
    else
      now
    end
  end

  @spec simulated_time_for_target?(Types.runtime_state(), Types.surface_target()) :: boolean()
  defp simulated_time_for_target?(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> Map.get(target, %{})
    |> Map.get(:model, %{})
    |> Ide.Debugger.SimulatorSettings.from_model()
    |> Map.get("use_simulated_time", false) == true
  end

  @spec worker_interval_ms(
          Types.runtime_state(),
          [:watch | :companion | :phone],
          [Types.subscription_row_input()],
          apply_ctx()
        ) :: pos_integer()
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

  @spec row_selected?(Types.auto_fire_candidate(), [Types.subscription_row_input()]) :: boolean()
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

  @spec resolved_auto_fire_message(String.t() | nil, String.t() | nil) :: String.t()
  defp resolved_auto_fire_message(resolved, fallback) do
    if is_binary(resolved) and String.trim(resolved) != "" do
      resolved
    else
      fallback || ""
    end
  end

  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end
end
