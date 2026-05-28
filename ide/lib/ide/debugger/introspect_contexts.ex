defmodule Ide.Debugger.IntrospectContexts do
  @moduledoc false

  alias Ide.Debugger.ElmIntrospectSnapshot
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeModelHydrate
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ElmIntrospectEventPayload

  @type snapshot_host :: %{
          required(:executor) => module(),
          required(:attach_compile_artifacts) =>
            (Types.runtime_state(), Types.surface_target(), Types.elm_introspect() ->
               Types.runtime_state()),
          required(:append_event) =>
            (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
               Types.runtime_state()),
          required(:append_debugger_event) =>
            (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:runtime_status_after_init) =>
            (Types.runtime_state(), Types.surface_target(), Types.app_model(),
             Types.elm_introspect() -> Types.runtime_state()),
          required(:apply_runtime_followups) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t(), list() ->
               Types.runtime_state()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx())
        }

  @type merge_host :: %{
          required(:snapshot_apply_ctx) => ElmIntrospectSnapshot.apply_ctx(),
          required(:init_surface_effects_ctx) => (-> InitSurfaceEffects.ctx()),
          required(:refresh_runtime_preview_for_target) =>
            (Types.runtime_state(), Types.surface_target() -> Types.runtime_state()),
          required(:apply_simulator_settings) => (Types.runtime_state() -> Types.runtime_state())
        }

  @spec snapshot_apply(snapshot_host()) :: ElmIntrospectSnapshot.apply_ctx()
  def snapshot_apply(host) when is_map(host) do
    %{
      executor: host.executor,
      attach_compile_artifacts: host.attach_compile_artifacts,
      hydrate_runtime_model: &RuntimeModelHydrate.for_message/3,
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      runtime_status_after_init: host.runtime_status_after_init,
      apply_runtime_followups: host.apply_runtime_followups,
      drain_app_message_queue: fn st, target ->
        ProtocolRx.drain_message_queue(st, target, host.protocol_rx_ctx.())
      end
    }
  end

  @spec merge(merge_host()) :: ElmIntrospectSnapshot.merge_ctx()
  def merge(host) when is_map(host) do
    %{
      apply_snapshot: host.snapshot_apply_ctx,
      after_apply: fn state, target, _source_root ->
        state
        |> InitSurfaceEffects.apply_all(target, host.init_surface_effects_ctx.())
        |> then(fn reloaded ->
          if target == :watch do
            host.refresh_runtime_preview_for_target.(reloaded, :watch)
          else
            reloaded
          end
        end)
      end,
      apply_simulator_settings: host.apply_simulator_settings,
      introspect_event_payload: fn ei, rel_path, source_root ->
        ElmIntrospectEventPayload.from_introspect(
          ei,
          rel_path,
          source_root,
          StepExecution.introspect_view_usable?(Map.get(ei, "view_tree") || %{}, ei)
        )
      end
    }
  end
end
