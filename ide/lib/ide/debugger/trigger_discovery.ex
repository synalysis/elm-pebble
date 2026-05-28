defmodule Ide.Debugger.TriggerDiscovery do
  @moduledoc false

  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.TriggerSurface
  alias Ide.Debugger.Types

  @type trigger_surface_ctx :: TriggerSurface.candidates_ctx() | (-> TriggerSurface.candidates_ctx())

  @type host :: %{required(:trigger_surface) => trigger_surface_ctx()}

  @spec candidates(Types.runtime_state(), :watch | :companion | :phone | nil, host()) ::
          [Types.trigger_candidate()]
  def candidates(state, target, host) when is_map(host) do
    trigger_surface = resolve_trigger_surface(host)

    case state do
      %{} = runtime_state when is_map(runtime_state) ->
        targets = if target in [:watch, :companion, :phone], do: [target], else: [:watch]

        targets
        |> Enum.flat_map(&TriggerSurface.candidates(runtime_state, &1, trigger_surface))
        |> Enum.uniq_by(fn row ->
          {Map.get(row, :target), Map.get(row, :trigger), Map.get(row, :message)}
        end)

      _ ->
        []
    end
  end

  @spec normalize_optional_target(Types.wire_input()) :: Types.surface_target() | nil
  def normalize_optional_target(value), do: SurfaceTargets.normalize_optional(value)

  @spec resolve_trigger_surface(host()) :: TriggerSurface.candidates_ctx()
  def resolve_trigger_surface(%{trigger_surface: surface}) do
    if is_function(surface, 0), do: surface.(), else: surface
  end
end
