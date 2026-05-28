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
    Task.start(__MODULE__, :run, [scope_key])
    :ok
  end

  @spec run(String.t()) :: :ok
  def run(scope_key) when is_binary(scope_key) do
    state = apply_deferred_companion_effects(scope_key)
    RuntimeBackgroundDrains.schedule_all(scope_key, state)
    RuntimeBackgroundNotify.broadcast(scope_key)
    :ok
  end

  @spec apply_deferred_companion_effects(String.t()) :: map()
  defp apply_deferred_companion_effects(scope_key) when is_binary(scope_key) do
    hosts = AgentSession.hosts()
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

    state
  end
end
