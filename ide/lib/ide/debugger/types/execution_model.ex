defmodule Ide.Debugger.Types.ExecutionModel do
  @moduledoc """
  Debugger execution surface: shell artifacts merged with app/runtime fields.

  Produced by `RuntimeArtifacts.execution_model/1`. Field merges use
  `Ide.Debugger.RuntimeSurfaceMerge.merge_fields/2`.
  """

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{InnerRuntimeModel, Shell}

  @type t :: Shell.t() | wire_map()

  @type wire_map :: %{
          optional(:runtime_model) => InnerRuntimeModel.t() | InnerRuntimeModel.wire_map(),
          optional(:elm_introspect) => map(),
          optional(:elmx_manifest) => map(),
          optional(:elmx_revision) => String.t(),
          optional(:vector_resource_indices) => map(),
          optional(:bitmap_resource_indices) => map(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @spec from_surface(Surface.surface_map()) :: wire_map()
  def from_surface(surface) when is_map(surface), do: RuntimeArtifacts.execution_model(surface)

  def from_surface(_surface), do: %{}
end
