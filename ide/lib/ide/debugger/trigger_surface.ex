defmodule Ide.Debugger.TriggerSurface do
  @moduledoc false

  alias Ide.Debugger.SubscriptionActivation
  alias Ide.Debugger.TickMessageResolution
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.TriggerMessageSurface
  alias Ide.Debugger.Types

  @type introspect_fn :: (Types.runtime_state(), Types.surface_target() ->
                            Types.elm_introspect())
  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type candidates_ctx :: %{
          required(:introspect_for) => introspect_fn(),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec candidates(Types.runtime_state(), Types.surface_target(), candidates_ctx()) ::
          [Types.trigger_candidate()]
  def candidates(state, target, %{
        introspect_for: introspect_for,
        source_root_for_target: source_root_for_target
      })
      when is_map(state) and target in [:watch, :companion, :phone] and
             is_function(introspect_for, 2) and
             is_function(source_root_for_target, 1) do
    ei = introspect_for.(state, target) || %{}
    target_name = source_root_for_target.(target)

    model_active = fn row -> SubscriptionActivation.model_active?(state, target, row) end

    TriggerCandidates.for_surface(ei, target_name, model_active)
  end

  def candidates(_state, _target, _ctx), do: []

  @spec display_for(
          Types.runtime_state(),
          String.t(),
          String.t(),
          introspect_fn(),
          normalize_target_fn()
        ) :: String.t()
  def display_for(state, trigger, target_name, introspect_for, normalize_target)
      when is_map(state) and is_binary(trigger) and is_binary(target_name) and
             is_function(introspect_for, 2) and
             is_function(normalize_target, 1) do
    target = normalize_target.(target_name)
    ei = introspect_for.(state, target) || %{}
    TriggerCandidates.subscription_trigger_display_for(ei, trigger)
  end

  def display_for(_state, trigger, _target_name, _introspect_for, _normalize_target)
      when is_binary(trigger),
      do: TriggerCandidates.subscription_trigger_display_for(%{}, trigger)

  def display_for(_state, _trigger, _target_name, _introspect_for, _normalize_target),
    do: "Trigger"

  @spec tick_message(
          Types.runtime_state(),
          Types.surface_target(),
          TriggerMessageSurface.resolve_ctx()
        ) :: String.t()
  def tick_message(state, target, resolution_ctx) when is_map(state) and is_map(resolution_ctx) do
    TickMessageResolution.message_for_surface(state, target, resolution_ctx)
  end

  @spec trigger_message(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          TriggerMessageSurface.resolve_ctx()
        ) :: String.t()
  def trigger_message(state, target, trigger, requested_message, resolution_ctx)
      when is_map(state) and is_binary(trigger) and is_map(resolution_ctx) do
    TriggerMessageSurface.resolve(state, target, trigger, requested_message, resolution_ctx)
  end
end
