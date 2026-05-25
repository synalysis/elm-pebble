defmodule Ide.Debugger.RuntimeSurfaceMerge do
  @moduledoc """
  Merges wire field maps into debugger surfaces (`model` + `shell` partitions).

  Used by `ingest_elmc_*`, runtime artifacts, and other paths that call
  `Ide.Debugger` `merge_runtime_model/3`.
  """

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type fields :: Types.elmc_surface_fields() | map()

  @type surface_target :: Types.surface_target()

  @spec merge_fields(Surface.surface_map() | map(), fields()) :: Surface.surface_map()
  def merge_fields(surface, fields) when is_map(surface) and is_map(fields) do
    normalized = Surface.from_map(surface) |> Surface.to_map()
    model = Map.get(normalized, :model) || %{}
    shell = Map.get(normalized, :shell) || %{}

    {legacy_app, legacy_shell} = RuntimeArtifacts.partition_fields(model)
    {app_fields, shell_fields} = RuntimeArtifacts.partition_fields(fields)

    Map.merge(normalized, %{
      model: Map.merge(legacy_app, app_fields),
      shell: Map.merge(shell, Map.merge(legacy_shell, shell_fields))
    })
  end

  @spec merge_into_state(map(), surface_target(), fields()) :: map()
  def merge_into_state(state, target, fields)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(fields) do
    state
    |> Surface.from_state(target)
    |> Surface.to_map()
    |> merge_fields(fields)
    |> then(&Surface.put_in_state(state, target, &1))
  end
end
