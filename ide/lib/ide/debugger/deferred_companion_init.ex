defmodule Ide.Debugger.DeferredCompanionInit do
  @moduledoc """
  Runs companion init surface effects and message-queue drain after a fast
  parser-only bootstrap reload, so the LiveView banner can clear immediately.
  """

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeBackgroundNotify
  alias Ide.Debugger.Types

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

  @spec apply_deferred_companion_effects(String.t()) :: Types.runtime_state()
  defp apply_deferred_companion_effects(scope_key) when is_binary(scope_key) do
    hosts = AgentSession.hosts()
    contexts = AgentHosts.contexts(hosts)
    init_ctx = Map.fetch!(contexts, :init_surface_effects)
    bridge_ctx = Map.fetch!(contexts, :companion_bridge)
    protocol_rx_ctx = Map.fetch!(contexts, :protocol_rx)

    {:ok, state} =
      AgentSession.mutate(scope_key, fn state ->
        {defer?, state} = BootstrapInit.take_defer_surface_effects(state)

        if defer? do
          state
          |> InitSurfaceEffects.apply_all(:companion, init_ctx)
          |> retry_companion_geolocation_if_needed(init_ctx, bridge_ctx)
          |> ProtocolRx.drain_message_queue(:companion, protocol_rx_ctx)
        else
          state
        end
      end)

    state
  end

  @spec retry_companion_geolocation_if_needed(
          Types.runtime_state(),
          InitSurfaceEffects.ctx(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  defp retry_companion_geolocation_if_needed(state, init_ctx, bridge_ctx)
       when is_map(state) and is_map(init_ctx) and is_map(bridge_ctx) do
    companion_model = get_in(state, [:companion, :model, "runtime_model"]) || %{}

    if companion_location_missing?(companion_model) do
      state
      |> Map.delete(:runtime_geolocation_applied)
      |> InitSurfaceEffects.apply_geolocation_response(:companion, init_ctx)
      |> CompanionBridgeRuntime.apply_init_commands(:companion, bridge_ctx)
      |> CompanionBridgeRuntime.flush_deferred_steps(bridge_ctx)
    else
      state
    end
  end

  defp retry_companion_geolocation_if_needed(state, _init_ctx, _bridge_ctx), do: state

  @spec companion_location_missing?(Types.inner_runtime_model()) :: boolean()
  defp companion_location_missing?(%{"lastLocation" => %{"ctor" => "Just"}}), do: false
  defp companion_location_missing?(%{"lastLocation" => %{ctor: "Just"}}), do: false
  defp companion_location_missing?(_), do: true
end
