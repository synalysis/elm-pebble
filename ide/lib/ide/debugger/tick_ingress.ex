defmodule Ide.Debugger.TickIngress do
  @moduledoc false

  alias Ide.Debugger.Attrs
  alias Ide.Debugger.AutoTickWorkers
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type apply_step_fn ::
          (Types.runtime_state(),
           Types.surface_target(),
           String.t(),
           Types.subscription_payload()
           | nil,
           String.t(),
           String.t() ->
             Types.runtime_state())

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type tick_message_fn :: (Types.runtime_state(), Types.surface_target() -> String.t())

  @type replay_label_fn :: (Types.surface_target() | nil -> String.t())

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type update_fn ::
          (String.t(), (Types.runtime_state() -> Types.runtime_state()) ->
             {:ok, Types.runtime_state()})

  @type host :: %{
          required(:apply_step_once) => apply_step_fn(),
          required(:append_event) => append_event_fn(),
          required(:tick_message_for_surface) => tick_message_fn(),
          required(:replay_label) => replay_label_fn(),
          required(:source_root_for_target) => source_root_fn(),
          required(:normalize_target) => normalize_target_fn(),
          required(:update) => update_fn(),
          required(:contexts) => (-> RuntimeContexts.t())
        }

  @spec tick(Types.runtime_state(), Types.step_attrs(), host()) :: Types.runtime_state()
  def tick(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      count = Attrs.parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))

      target =
        SurfaceTargets.normalize_optional(Map.get(attrs, :target) || Map.get(attrs, "target"))

      targets = SurfaceTargets.tick_targets(target)

      ticked =
        Enum.reduce(1..count, state, fn _, acc ->
          Enum.reduce(targets, acc, fn surface_target, next_state ->
            message = host.tick_message_for_surface.(next_state, surface_target)

            host.apply_step_once.(
              next_state,
              surface_target,
              message,
              nil,
              "subscription_tick",
              "tick"
            )
          end)
        end)

      host.append_event.(
        ticked,
        "debugger.tick",
        Types.TickEventPayload.from_tick(
          host.replay_label.(target),
          count,
          Enum.map(targets, fn surface_target -> host.source_root_for_target.(surface_target) end)
        )
      )
    else
      state
    end
  end

  @spec start_auto_tick(Types.runtime_state(), String.t(), Types.step_attrs(), host()) ::
          Types.runtime_state()
  def start_auto_tick(state, project_slug, attrs, host)
      when is_map(state) and is_binary(project_slug) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      interval_ms =
        Attrs.parse_tick_interval_ms(
          Map.get(attrs, :interval_ms) || Map.get(attrs, "interval_ms")
        )

      count = Attrs.parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))

      target =
        SurfaceTargets.normalize_optional(Map.get(attrs, :target) || Map.get(attrs, "target"))

      targets = SurfaceTargets.tick_targets(target)

      state = AutoTickWorkers.stop_worker(state)

      tick_fn = fn slug, tick_attrs ->
        host.update.(slug, fn inner -> tick(inner, tick_attrs, host) end)
      end

      worker =
        spawn(fn ->
          AutoTickWorkers.tick_loop(project_slug, interval_ms, targets, count, tick_fn)
        end)

      state
      |> Map.put(:auto_tick, %{
        enabled: true,
        interval_ms: interval_ms,
        target: host.replay_label.(target),
        targets:
          Enum.map(targets, fn surface_target -> host.source_root_for_target.(surface_target) end),
        count: count,
        worker_pid: worker
      })
      |> host.append_event.(
        "debugger.tick_auto",
        Types.TickAutoEventPayload.start(
          host.replay_label.(target),
          interval_ms,
          Enum.map(targets, fn surface_target -> host.source_root_for_target.(surface_target) end),
          count
        )
      )
    else
      state
    end
  end

  @spec stop_auto_tick(Types.runtime_state(), append_event_fn()) :: Types.runtime_state()
  def stop_auto_tick(state, append_event) when is_map(state) and is_function(append_event, 3) do
    state
    |> AutoTickWorkers.stop_worker()
    |> append_event.("debugger.tick_auto", Types.TickAutoEventPayload.stop())
  end

  @spec set_auto_fire(Types.runtime_state(), String.t(), Types.step_attrs(), host()) ::
          Types.runtime_state()
  def set_auto_fire(state, project_slug, attrs, host)
      when is_map(state) and is_binary(project_slug) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      target = host.normalize_target.(Map.get(attrs, :target) || Map.get(attrs, "target"))
      enabled? = Attrs.parse_checkbox_bool(Map.get(attrs, :enabled) || Map.get(attrs, "enabled"))
      trigger = Map.get(attrs, :trigger) || Map.get(attrs, "trigger")

      subscriptions =
        if is_binary(trigger) and String.trim(trigger) != "" do
          state
          |> SubscriptionAutoFireState.auto_tick_subscriptions(host.source_root_for_target)
          |> SubscriptionAutoFireState.update_auto_fire_subscriptions(
            target,
            trigger,
            enabled?,
            host.source_root_for_target
          )
        else
          state
          |> SubscriptionAutoFireState.auto_tick_targets()
          |> SubscriptionAutoFireState.update_auto_fire_targets(target, enabled?)
          |> Enum.map(&%{"target" => host.source_root_for_target.(&1), "trigger" => "*"})
        end

      targets =
        SubscriptionAutoFireState.auto_fire_targets_from_subscriptions(
          subscriptions,
          host.normalize_target
        )

      ctx = host.contexts.()

      state
      |> AutoTickWorkers.restart_auto_fire(
        project_slug,
        targets,
        subscriptions,
        host.update,
        ctx.auto_fire
      )
      |> host.append_event.(
        "debugger.tick_auto",
        Types.TickAutoEventPayload.set_auto_fire(
          host.source_root_for_target.(target),
          trigger,
          enabled?,
          Enum.map(targets, fn surface_target -> host.source_root_for_target.(surface_target) end),
          subscriptions
        )
      )
    else
      state
    end
  end
end
