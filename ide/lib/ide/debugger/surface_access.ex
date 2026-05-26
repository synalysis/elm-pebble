defmodule Ide.Debugger.SurfaceAccess do
  @moduledoc false

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @spec surface(Types.runtime_state(), Types.surface_target()) :: Surface.t()
  def surface(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    Surface.from_state(state, target)
  end

  @spec app_model(Types.runtime_state(), Types.surface_target()) :: Types.app_model()
  def app_model(state, target) when is_map(state) do
    state |> surface(target) |> Surface.app_model()
  end

  @spec introspect(Types.runtime_state(), Types.surface_target()) :: Types.elm_introspect() | nil
  def introspect(state, target) when is_map(state) do
    state |> surface(target) |> Surface.introspect()
  end
end
