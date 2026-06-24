defmodule Ide.Debugger.TriggerDisplay do
  @moduledoc false

  alias Ide.Debugger.SurfaceAccess
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.TriggerSurface
  alias Ide.Debugger.Types

  @type introspect_fn :: (Types.runtime_state(), Types.surface_target() ->
                            Types.elm_introspect())

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type host :: %{
          required(:introspect_for) => introspect_fn(),
          required(:normalize_target) => normalize_target_fn()
        }

  @spec label_for(Types.runtime_state(), String.t(), String.t(), host()) :: String.t()
  def label_for(state, trigger, target_name, host)
      when is_map(state) and is_binary(trigger) and is_binary(target_name) and is_map(host) do
    TriggerSurface.display_for(
      state,
      trigger,
      target_name,
      host.introspect_for,
      host.normalize_target
    )
  end

  def label_for(_state, trigger, _target_name, _host) when is_binary(trigger),
    do: TriggerCandidates.subscription_trigger_display_for(%{}, trigger)

  def label_for(_state, _trigger, _target_name, _host), do: "Trigger"

  @spec default_host() :: host()
  def default_host do
    %{
      introspect_for: &SurfaceAccess.introspect/2,
      normalize_target: &SurfaceTargets.normalize/1
    }
  end
end
