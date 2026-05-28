defmodule Ide.Debugger.RuntimeArtifactMerge do
  @moduledoc false

  alias Ide.Debugger.RuntimeSurfaceMerge
  alias Ide.Debugger.Types

  @spec merge_into_state(Types.runtime_state(), Types.surface_target(), Types.elmc_surface_fields()) ::
          Types.runtime_state()
  def merge_into_state(state, target, fields)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(fields) do
    RuntimeSurfaceMerge.merge_into_state(state, target, fields)
  end

  @spec maybe_merge(Types.runtime_state(), Types.surface_target() | nil, Types.elmc_surface_fields()) ::
          Types.runtime_state()
  def maybe_merge(state, target, fields)
      when target in [:watch, :companion, :phone] and is_map(fields) and map_size(fields) > 0 do
    merge_into_state(state, target, fields)
  end

  def maybe_merge(state, _target, _fields), do: state
end
