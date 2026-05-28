defmodule Ide.Debugger.InitSurfaceEffectsContext do
  @moduledoc false

  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.Types

  @type host :: %{
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:apply_step_once) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
             String.t(), String.t() -> map()),
          required(:apply_device_data_followups) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:apply_subscription_ok_response) =>
            (map(), Types.surface_target(), String.t(), map(), String.t(), String.t() -> map()),
          required(:protocol_events_ctx) => (-> map()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:companion_bridge_ctx) => (-> map()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec build(host()) :: InitSurfaceEffects.ctx()
  def build(host) when is_map(host), do: host
end
