defmodule Ide.Debugger.RuntimeBackgroundDrains do
  @moduledoc false

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.PendingProtocolDelivery
  alias Ide.Debugger.PendingSpeakerFollowups
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeBackgroundWork
  alias Ide.Debugger.Types

  @spec schedule_all(String.t(), Types.runtime_state()) :: :ok
  def schedule_all(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    PendingProtocolDelivery.maybe_schedule_drain(project_slug, state)
    PendingHttpFollowups.maybe_schedule_drain(project_slug, state)
    PendingSpeakerFollowups.maybe_schedule(project_slug, state)
    :ok
  end

  @spec await_idle(String.t(), timeout()) :: :ok | :timeout
  def await_idle(project_slug, timeout \\ 120_000) do
  unless PendingProtocolDelivery.async?() do
      AgentSession.with_hosts(fn hosts ->
        contexts = AgentHosts.contexts(hosts)
        protocol_rx = Map.fetch!(contexts, :protocol_rx)
        bridge_ctx = Map.fetch!(contexts, :companion_bridge)

        PendingProtocolDelivery.drain_pending_sync(project_slug, protocol_rx)

        AgentSession.mutate(project_slug, fn state ->
          state
          |> CompanionBridgeRuntime.flush_deferred_steps(bridge_ctx)
          |> ProtocolRx.flush_inline_protocol_deliveries(protocol_rx)
        end)
      end)
    end

    RuntimeBackgroundWork.await_idle(project_slug, timeout)
  end
end
