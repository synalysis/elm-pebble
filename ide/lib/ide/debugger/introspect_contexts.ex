defmodule Ide.Debugger.IntrospectContexts do
  @moduledoc false

  alias ElmEx.DebuggerContract
  alias Ide.Debugger.DebuggerContractSnapshot
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.DebuggerContractEventPayload

  @type snapshot_host :: %{
          required(:executor) => module(),
          required(:attach_compile_artifacts) => (Types.runtime_state(),
                                                  Types.surface_target(),
                                                  Types.elm_introspect() ->
                                                    Types.runtime_state()),
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:append_debugger_event) => (Types.runtime_state(),
                                               String.t(),
                                               Types.surface_target(),
                                               String.t(),
                                               String.t(),
                                               Types.timeline_step_message_value() ->
                                                 Types.runtime_state()),
          required(:runtime_status_after_init) => (Types.runtime_state(),
                                                   Types.surface_target(),
                                                   Types.step_executor_result()
                                                   | Types.wire_map(),
                                                   Types.elm_introspect() ->
                                                     Types.runtime_state()),
          required(:apply_runtime_followups) => (Types.runtime_state(),
                                                 Types.surface_target(),
                                                 String.t(),
                                                 String.t(),
                                                 [Types.runtime_followup_row()] ->
                                                   Types.runtime_state()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:drain_app_message_queue) => (Types.runtime_state(), Types.surface_target() ->
                                                   Types.runtime_state())
        }

  @type merge_host :: %{
          required(:snapshot_apply_ctx) => DebuggerContractSnapshot.apply_ctx(),
          required(:surface_compile) => Ide.Debugger.SurfaceCompileArtifacts.attach_ctx(),
          required(:init_surface_effects_ctx) => (-> InitSurfaceEffects.ctx()),
          required(:refresh_runtime_preview_for_target) => (Types.runtime_state(),
                                                            Types.surface_target() ->
                                                              Types.runtime_state()),
          required(:apply_simulator_settings) => (Types.runtime_state() -> Types.runtime_state()),
          required(:deliver_companion_status_after_watch_init) =>
            (Types.runtime_state() -> Types.runtime_state()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx())
        }

  @spec snapshot_apply(snapshot_host()) :: DebuggerContractSnapshot.apply_ctx()
  def snapshot_apply(host) when is_map(host) do
    %{
      executor: host.executor,
      attach_compile_artifacts: host.attach_compile_artifacts,
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      runtime_status_after_init: host.runtime_status_after_init,
      apply_runtime_followups: host.apply_runtime_followups,
      drain_app_message_queue: fn st, target ->
        ProtocolRx.drain_message_queue(st, target, host.protocol_rx_ctx.())
      end,
      protocol_rx_ctx: host.protocol_rx_ctx
    }
  end

  @spec merge(merge_host()) :: DebuggerContractSnapshot.merge_ctx()
  def merge(host) when is_map(host) do
    %{
      apply_snapshot: host.snapshot_apply_ctx,
      surface_compile: host.surface_compile,
      after_apply: fn state, target, _source_root ->
        state
        |> InitSurfaceEffects.apply_all(target, host.init_surface_effects_ctx.())
        |> ProtocolRx.flush_inline_protocol_deliveries(host.protocol_rx_ctx.())
        |> then(fn reloaded ->
          reloaded =
            if target == :watch do
              host.deliver_companion_status_after_watch_init.(reloaded)
            else
              reloaded
            end

          if target == :watch and refresh_watch_preview_after_apply?(reloaded) do
            host.refresh_runtime_preview_for_target.(reloaded, :watch)
          else
            reloaded
          end
        end)
      end,
      apply_simulator_settings: host.apply_simulator_settings,
      introspect_event_payload: fn ei, rel_path, source_root ->
        DebuggerContractEventPayload.from_introspect(
          ei,
          rel_path,
          source_root,
          StepExecution.introspect_view_usable?(Map.get(ei, "view_tree") || %{}, ei)
        )
      end
    }
  end

  @spec refresh_watch_preview_after_apply?(Types.runtime_state()) :: boolean()
  defp refresh_watch_preview_after_apply?(state) when is_map(state) do
    watch = Surface.from_state(state, :watch)
    ei = Surface.shell(watch)["debugger_contract"] || %{}
    model = Surface.app_model(watch)
    view_tree = watch.view_tree || %{}

    cond do
      not DebuggerContract.parser_expression_view?(%{"debugger_contract" => ei}) ->
        true

      RuntimePreview.has_drawable_output?(model) ->
        true

      StepExecution.view_tree_has_draw_ops?(view_tree) ->
        true

      true ->
        false
    end
  end
end
