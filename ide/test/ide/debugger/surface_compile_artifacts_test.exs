defmodule Ide.Debugger.SurfaceCompileArtifactsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SurfaceCompileArtifacts

  test "surface_has_core_ir? is false without decoded core ir on surface" do
    state = RuntimeSurfaces.default_watch()
    refute SurfaceCompileArtifacts.surface_has_core_ir?(state, :watch)
  end
end
