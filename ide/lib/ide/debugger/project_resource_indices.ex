defmodule Ide.Debugger.ProjectResourceIndices do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @spec attach_vector(Types.runtime_state(), String.t()) :: Types.runtime_state()
  def attach_vector(state, project_slug) when is_map(state) and is_binary(project_slug) do
    case RuntimeArtifacts.vector_resource_indices_for_project(project_slug) do
      indices when is_map(indices) and map_size(indices) > 0 ->
        Surface.update_in_state(state, :watch, fn surface ->
          Surface.put_shell(surface, Map.put(surface.shell, "vector_resource_indices", indices))
        end)

      _ ->
        state
    end
  end

  def attach_vector(state, _project_slug), do: state

  @spec attach_bitmap(Types.runtime_state(), String.t()) :: Types.runtime_state()
  def attach_bitmap(state, project_slug) when is_map(state) and is_binary(project_slug) do
    case RuntimeArtifacts.bitmap_resource_indices_for_project(project_slug) do
      indices when is_map(indices) and map_size(indices) > 0 ->
        Surface.update_in_state(state, :watch, fn surface ->
          Surface.put_shell(surface, Map.put(surface.shell, "bitmap_resource_indices", indices))
        end)

      _ ->
        state
    end
  end

  def attach_bitmap(state, _project_slug), do: state

  @spec attach_animation(Types.runtime_state(), String.t()) :: Types.runtime_state()
  def attach_animation(state, project_slug) when is_map(state) and is_binary(project_slug) do
    case RuntimeArtifacts.animation_resource_indices_for_project(project_slug) do
      indices when is_map(indices) and map_size(indices) > 0 ->
        Surface.update_in_state(state, :watch, fn surface ->
          Surface.put_shell(
            surface,
            Map.put(surface.shell, "animation_resource_indices", indices)
          )
        end)

      _ ->
        state
    end
  end

  def attach_animation(state, _project_slug), do: state

  @spec attach_all(Types.runtime_state(), String.t()) :: Types.runtime_state()
  def attach_all(state, project_slug) when is_map(state) and is_binary(project_slug) do
    state
    |> attach_vector(project_slug)
    |> attach_bitmap(project_slug)
    |> attach_animation(project_slug)
  end
end
