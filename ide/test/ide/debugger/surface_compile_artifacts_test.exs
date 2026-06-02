defmodule Ide.Debugger.SurfaceCompileArtifactsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SurfaceCompileArtifacts

  test "surface_has_versioned_runtime_artifacts? is false without elmx artifacts on surface" do
    state = RuntimeSurfaces.default_watch()
    refute SurfaceCompileArtifacts.surface_has_versioned_runtime_artifacts?(state, :watch)
  end
end
