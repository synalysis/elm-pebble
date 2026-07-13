defmodule Ide.Debugger.AutoTickWorkers do
  @moduledoc false

  alias Ide.Debugger.AutoFireRuntime
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type tick_payload :: %{
          required(:target) => String.t(),
          required(:count) => non_neg_integer()
        }

  @type tick_fn :: (String.t(), tick_payload() -> {:ok, Types.runtime_state()})
  @type update_fn :: (String.t(), (Types.runtime_state() -> Types.runtime_state()) ->
                        {:ok, Types.runtime_state()})

  @type fire_ctx :: AutoFireRuntime.apply_ctx()

  @spec stop_worker(Types.runtime_state()) :: Types.runtime_state()
  def stop_worker(state) when is_map(state) do
    auto_tick = Map.get(state, :auto_tick, %{})
    worker = Map.get(auto_tick, :worker_pid)

    if is_pid(worker) and Process.alive?(worker) do
      send(worker, :stop)
    end

    Map.put(state, :auto_tick, SessionDefaults.default_auto_tick())
  end

  @spec tick_loop(String.t(), pos_integer(), [Types.surface_target()], pos_integer(), tick_fn()) ::
          :ok
  def tick_loop(project_slug, interval_ms, targets, count, tick_fn)
      when is_binary(project_slug) and is_integer(interval_ms) and interval_ms >= 100 and
             is_function(tick_fn, 2) do
    receive do
      :stop -> :ok
    after
      interval_ms ->
        Enum.each(List.wrap(targets), fn target ->
          tick_fn.(project_slug, %{target: SurfaceTargets.source_root(target), count: count})
        end)

        tick_loop(project_slug, interval_ms, targets, count, tick_fn)
    end
  end

  @spec fire_loop(
          String.t(),
          pos_integer(),
          [Types.surface_target()],
          non_neg_integer(),
          update_fn(),
          fire_ctx()
        ) ::
          :ok
  def fire_loop(project_slug, interval_ms, targets, cursor, update_fn, fire_ctx)
      when is_binary(project_slug) and is_integer(interval_ms) and interval_ms >= 100 and
             is_integer(cursor) and
             cursor >= 0 and is_function(update_fn, 2) and is_map(fire_ctx) do
    receive do
      :stop -> :ok
    after
      interval_ms ->
        update_fn.(project_slug, fn state ->
          AutoFireRuntime.apply_fire(state, targets, fire_ctx)
        end)

        fire_loop(project_slug, interval_ms, targets, cursor + 1, update_fn, fire_ctx)
    end
  end

  @spec restart_auto_fire(
          Types.runtime_state(),
          String.t(),
          [Types.surface_target()],
          [Types.trigger_candidate()],
          update_fn(),
          fire_ctx()
        ) :: Types.runtime_state()
  def restart_auto_fire(state, project_slug, targets, subscriptions, update_fn, fire_ctx)
      when is_map(state) and is_binary(project_slug) and is_list(targets) and is_map(fire_ctx) do
    state = stop_worker(state)

    case targets do
      [] ->
        state

      [_ | _] ->
        interval_ms = AutoFireRuntime.worker_interval_ms(state, targets, subscriptions, fire_ctx)
        count = 1

        worker =
          spawn(fn ->
            fire_loop(project_slug, interval_ms, targets, 0, update_fn, fire_ctx)
          end)

        state
        |> AutoFireRuntime.initialize_clocks(targets, fire_ctx)
        |> Map.put(:auto_tick, %{
          enabled: true,
          interval_ms: interval_ms,
          target: SubscriptionAutoFireState.target_label(targets, &SurfaceTargets.source_root/1),
          targets: Enum.map(targets, &SurfaceTargets.source_root/1),
          subscriptions: subscriptions,
          count: count,
          worker_pid: worker
        })
    end
  end
end
