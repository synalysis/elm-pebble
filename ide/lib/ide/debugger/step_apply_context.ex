defmodule Ide.Debugger.StepApplyContext do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.StepApplyCallbacks
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime

  @type host :: StepApplyCallbacks.host()

  @type deps :: %{
          required(:host) => host(),
          required(:surface_compile) => SurfaceCompileArtifacts.attach_ctx(),
          required(:runtime_init) => Ide.Debugger.RuntimeInitApply.ctx(),
          required(:protocol_events) => ProtocolEvents.ctx(),
          required(:protocol_rx) => ProtocolRx.ctx(),
          required(:device_data) => DeviceDataResponses.apply_ctx(),
          required(:geolocation) => GeolocationResponses.apply_ctx(),
          required(:companion_bridge) => CompanionBridgeRuntime.ctx(),
          required(:runtime_followups) => RuntimeFollowups.apply_ctx()
        }

  @spec build(deps()) :: StepApply.ctx()
  def build(%{} = deps), do: StepApplyCallbacks.build(deps)
end
