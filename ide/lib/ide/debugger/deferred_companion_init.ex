defmodule Ide.Debugger.DeferredCompanionInit do
  @moduledoc """
  Runs companion init surface effects and message-queue drain after a fast
  parser-only bootstrap reload, so the LiveView banner can clear immediately.
  """

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeBackgroundNotify

  @spec schedule(String.t()) :: :ok
  def schedule(scope_key) when is_binary(scope_key) do
    Task.start(fn -> run(scope_key) end)
    :ok
  end

  @spec run(String.t()) :: :ok
  def run(scope_key) when is_binary(scope_key) do
    AgentSession.with_hosts(fn hosts ->
      contexts = AgentHosts.contexts(hosts)
      init_ctx = Map.fetch!(contexts, :init_surface_effects)
      protocol_rx_ctx = Map.fetch!(contexts, :protocol_rx)

      {:ok, state} =
        AgentSession.mutate(scope_key, fn state ->
          {defer?, state} = BootstrapInit.take_defer_surface_effects(state)

          if defer? do
            state
            |> InitSurfaceEffects.apply_all(:companion, init_ctx)
            |> ProtocolRx.drain_message_queue(:companion, protocol_rx_ctx)
          else
            state
          end
        end)

      RuntimeBackgroundDrains.schedule_all(scope_key, state)
      RuntimeBackgroundNotify.broadcast(scope_key)
    end)

    :ok
  end
end
