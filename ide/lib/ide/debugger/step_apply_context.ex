defmodule Ide.Debugger.StepApplyContext do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeModelHydrate
  alias Ide.Debugger.RuntimeModelNormalize
  alias Ide.Debugger.SampleViewTrees
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.Types

  @type host :: %{
          required(:ensure_compile_artifacts) => (map(), Types.surface_target() -> map()),
          required(:normalize_message_value) =>
            (map(), Types.surface_target(), Types.subscription_payload() | map() | nil, map() ->
               Types.subscription_payload() | map() | nil),
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:append_runtime_exec) => (map(), Types.surface_target(), map() -> map()),
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:append_debugger_event) =>
            (map(), String.t(), Types.surface_target(), String.t(), String.t() -> map()),
          required(:maybe_append_runtime_status) => (map(), Types.surface_target() -> map()),
          required(:device_data_responses) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:geolocation_response) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:companion_bridge_command_responses) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:companion_bridge_responses) =>
            (map(), Types.surface_target(), String.t() -> map()),
          required(:static_task_followups) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
             String.t() -> map()),
          required(:runtime_followups) =>
            (map(), Types.surface_target(), String.t(), String.t(), list() -> map())
        }

  @spec build(host()) :: StepApply.ctx()
  def build(host) when is_map(host) do
    %{
      ensure_compile_artifacts: host.ensure_compile_artifacts,
      hydrate_runtime_model: &RuntimeModelHydrate.for_message/3,
      normalize_message_value: host.normalize_message_value,
      normalize_runtime_patch: &RuntimeModelNormalize.patch_values/2,
      patched_runtime_model_fields: &RuntimeModelHydrate.patched_fields/1,
      preserve_protocol_metadata: &Ide.Debugger.ProtocolRuntimeMetadata.preserve/2,
      default_view_tree: &SampleViewTrees.default_for_target/1,
      introspect_for: host.introspect_for,
      protocol_events_ctx: host.protocol_events_ctx,
      protocol_rx_ctx: host.protocol_rx_ctx,
      source_root_for_target: host.source_root_for_target,
      append_runtime_exec: host.append_runtime_exec,
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      maybe_append_runtime_status: host.maybe_append_runtime_status,
      device_data_responses: host.device_data_responses,
      geolocation_response: host.geolocation_response,
      companion_bridge_command_responses: host.companion_bridge_command_responses,
      companion_bridge_responses: host.companion_bridge_responses,
      static_task_followups: host.static_task_followups,
      runtime_followups: host.runtime_followups
    }
  end
end
