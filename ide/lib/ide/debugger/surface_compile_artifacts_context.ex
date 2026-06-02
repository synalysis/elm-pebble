defmodule Ide.Debugger.SurfaceCompileArtifactsContext do
  @moduledoc false

  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.Types

  @type host :: %{
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:merge_runtime_artifacts) => (Types.runtime_state(),
                                                 Types.surface_target(),
                                                 map() ->
                                                   Types.runtime_state())
        }

  @spec build(host()) :: SurfaceCompileArtifacts.attach_ctx()
  def build(host) when is_map(host), do: host
end
